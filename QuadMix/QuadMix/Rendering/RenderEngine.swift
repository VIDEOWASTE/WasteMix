import Metal
import MetalKit
import QuartzCore
import AVFoundation
import Photos

/// Weak proxy so CADisplayLink doesn't retain RenderEngine (CADisplayLink
/// retains its target — without this we'd leak the engine forever).
private final class DisplayLinkProxy {
    weak var engine: RenderEngine?
    @objc func tick() { engine?.tickRender() }
}

final class RenderEngine: NSObject {
    let mixerState: MixerState
    let outputConfig = OutputConfig()
    let transitionEngine = TransitionEngine()
    let audioEngine = AudioEngine()
    let outputRenderer = OutputRenderer()
    let displayManager = DisplayManager()
    let clipLibrary = ClipLibrary()
    lazy var recorder: ProgramRecorder = ProgramRecorder(clipLibrary: clipLibrary)

    private let ctx = MetalContext.shared
    private let compositorPipeline = CompositorPipeline()
    private(set) var channelRenderers: [ChannelRenderer] = []

    /// Stable composited output. The render loop writes here every tick.
    /// Any MTKView that wants to show the program just blits this — no view
    /// owns the loop, so a backgrounded scene can't freeze output for the
    /// other windows (Advanced Output, external display, NDI).
    let programTexture: MTLTexture

    private let inflightSemaphore = DispatchSemaphore(value: 2)
    private(set) var channelPreviewTextures: [MTLTexture?] = Array(repeating: nil, count: 4)

    private var displayLink: CADisplayLink?
    private let displayLinkProxy = DisplayLinkProxy()
    private var lastTimestamp: CFTimeInterval = 0

    init(mixerState: MixerState) {
        self.mixerState = mixerState

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: Constants.defaultWidth,
            height: Constants.defaultHeight,
            mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        guard let tex = ctx.device.makeTexture(descriptor: desc) else {
            fatalError("Failed to allocate program texture")
        }
        self.programTexture = tex

        super.init()
        self.channelRenderers = mixerState.channels.map { ChannelRenderer(channel: $0) }

        displayLinkProxy.engine = self
        let link = CADisplayLink(target: displayLinkProxy, selector: #selector(DisplayLinkProxy.tick))
        link.preferredFramesPerSecond = 60
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    deinit {
        displayLink?.invalidate()
    }

    // MARK: - Lifecycle

    /// Pause GPU work, NDI sends, and camera capture when the app
    /// backgrounds. iOS will deny camera access in the background anyway,
    /// and continuing to drive the display link wastes battery + leaves
    /// the mic/cam status indicators lit. Reviewers will flag that.
    func pauseForBackground() {
        displayLink?.isPaused = true
        outputRenderer.shutdown()
        // Snapshot user-facing settings so they survive across launches.
        mixerState.savePersistedSettings()
        // Stop camera off the main thread — Apple recommends a session queue
        // and keeping the call on main can produce a 200–500ms hitch.
        DispatchQueue.global(qos: .userInitiated).async {
            CameraHub.shared.session.stopRunning()
        }
    }

    func resumeForForeground() {
        displayLink?.isPaused = false
        // Re-attach any inputs the non-multi-cam path may have detached, then
        // restart. Done off-main to avoid hitching the foreground transition.
        DispatchQueue.global(qos: .userInitiated).async {
            CameraHub.shared.reattachAllConsumers()
        }
    }

    func setSource(_ source: FrameProvider?, for channelIndex: Int) {
        NSLog("[RenderEngine] setSource called: channel=%d source=%@", channelIndex, String(describing: source))
        guard channelIndex < channelRenderers.count else {
            NSLog("[RenderEngine] ERROR: channelIndex %d >= count %d", channelIndex, channelRenderers.count)
            return
        }
        channelRenderers[channelIndex].frameProvider?.stop()
        channelRenderers[channelIndex].frameProvider = source
        source?.start()
        NSLog("[RenderEngine] source.start() called")
    }

    // MARK: - Render Tick (driven by CADisplayLink)

    fileprivate func tickRender() {
        let now = CACurrentMediaTime()
        lastTimestamp = now

        guard inflightSemaphore.wait(timeout: .now() + .milliseconds(20)) == .success else { return }

        transitionEngine.update(channels: mixerState.channels, timestamp: now)
        updateLFOs(time: Float(now))
        updateAudioReactivity()

        guard let commandBuffer = ctx.commandQueue.makeCommandBuffer() else {
            inflightSemaphore.signal()
            return
        }

        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.inflightSemaphore.signal()
        }

        var activeChannels: [ChannelCompositeInfo] = []

        for (i, renderer) in channelRenderers.enumerated() {
            let channel = mixerState.channels[i]

            let texMaybe = renderer.currentTexture(commandBuffer: commandBuffer)
            // Clear the preview slot when the source goes away — otherwise
            // the PVW MTKView keeps presenting the last frame from the
            // previously-attached source after the user hits "Clear Source".
            if texMaybe == nil {
                channelPreviewTextures[i] = nil
            }
            if let tex = texMaybe {
                channelPreviewTextures[i] = tex

                if channel.faderLevel > 0.001 {
                    // Determine wipe state:
                    // 1. If an auto-transition wipe is running, use its progress
                    // 2. If the channel's transition type is a wipe (no auto running),
                    //    the fader position IS the wipe progress — like a T-bar
                    let wipeProgress: Float?
                    let wipeDirection: Int?

                    if let transition = transitionEngine.activeTransition(for: channel),
                       transition.type.isWipe {
                        wipeProgress = channel.transitionProgress
                        wipeDirection = transition.type.wipeDirection
                    } else if channel.transitionConfig.type.isWipe {
                        wipeProgress = channel.faderLevel
                        wipeDirection = channel.transitionConfig.type.wipeDirection
                    } else {
                        wipeProgress = nil
                        wipeDirection = nil
                    }

                    activeChannels.append(ChannelCompositeInfo(
                        texture: tex,
                        blendMode: channel.blendMode,
                        opacity: channel.faderLevel * mixerState.masterLevel,
                        wipeProgress: wipeProgress,
                        wipeDirection: wipeDirection
                    ))
                }
            }
        }

        compositorPipeline.composite(
            channels: activeChannels,
            globalColorCorrection: mixerState.globalColorCorrection,
            into: programTexture,
            commandBuffer: commandBuffer
        )

        outputRenderer.render(
            programTexture: programTexture,
            channelTextures: channelPreviewTextures,
            config: outputConfig,
            commandBuffer: commandBuffer
        )

        // Capture this frame for the program recorder if active. Sits AFTER
        // the compositor's writes have been encoded so the captured pixel
        // buffer reflects the same image PVW/PGM/HDMI/NDI just rendered.
        recorder.captureFrame(programTexture, commandBuffer: commandBuffer)

        commandBuffer.commit()

        // Flush texture cache to release stale CVMetalTexture mappings
        ctx.textureConverter.flush()
    }

    // MARK: - LFO

    private func updateLFOs(time: Float) {
        // Master LFO — routed to the master target.
        if mixerState.masterLFO.isActive {
            let v = mixerState.masterLFO.compute(time: time, bpm: mixerState.bpm)
            mixerState.masterLFOCurrent = v
            switch mixerState.masterLFOTarget {
            case .masterLevel:
                mixerState.masterLevel = v
            case .crossfader:
                mixerState.masterLevel = 1.0  // not dimming when sweeping crossfader
                mixerState.crossfaderPos = v
                mixerState.applyCrossfader()
            }
        } else if mixerState.masterLevel != 1.0 {
            // No master LFO running — clear any residual dim, but only if
            // the value would actually change so we don't invalidate every
            // observer of masterLevel each frame.
            mixerState.masterLevel = 1.0
        }

        for channel in mixerState.channels {
            guard channel.lfo.isActive else { continue }

            let value = channel.lfo.compute(time: time, bpm: mixerState.bpm)
            channel.lfoCurrent = value

            switch channel.lfo.target {
            case .opacity:
                if !channel.isTransitioning && !channel.audioReact.isActive {
                    channel.faderLevel = value
                }
            case .fxIntensity:
                channel.effectIntensity = value
            case .fxParam2:
                channel.effectParam2 = value
            case .pipScale:
                channel.pipSettings.scale = 0.1 + value * 4.9 // map 0-1 to 0.1-5.0
            case .pipX:
                channel.pipSettings.offsetX = value * 2.0 - 1.0 // map 0-1 to -1..1
            case .pipY:
                channel.pipSettings.offsetY = value * 2.0 - 1.0
            case .none:
                break
            }
        }
    }

    // MARK: - Audio Reactivity

    private func updateAudioReactivity() {
        for channel in mixerState.channels {
            let react = channel.audioReact
            guard react.isActive else { continue }

            var rawValue: Float = 0
            var totalWeight: Float = 0
            for band in 0..<7 {
                let gain = react.bandGains[band]
                if gain > 0.001 {
                    rawValue += audioEngine.bandLevel(at: band) * gain
                    totalWeight += gain
                }
            }
            if totalWeight > 0 { rawValue /= totalWeight }

            let mapped = react.floor + rawValue * (react.ceiling - react.floor)
            let prev = channel.audioReactCurrent
            let smoothed = prev + (mapped - prev) * (1.0 - react.smoothing)
            // Write only the runtime scalar — the user-config (bandGains,
            // smoothing, floor, ceiling, target, enabled) doesn't change
            // and shouldn't invalidate observers each frame.
            channel.audioReactCurrent = smoothed

            switch react.target {
            case .opacity:
                if !channel.isTransitioning { channel.faderLevel = smoothed }
            case .effectIntensity:
                channel.effectIntensity = smoothed
            case .none:
                break
            }
        }
    }
}

// MARK: - Program Recorder

/// Records `RenderEngine.programTexture` to an .mp4 in the Photos library.
/// Encoded via AVAssetWriter; each display tick we blit the live program
/// texture into the writer's pixel buffer pool, then append. GPU work runs
/// async (no `waitUntilCompleted`) so the display link doesn't stall.
@Observable
final class ProgramRecorder {
    private(set) var isRecording = false
    private(set) var elapsedSeconds: Double = 0
    private(set) var lastSavedURL: URL?
    private(set) var lastError: String?

    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var startedAt: CFTimeInterval = 0
    private var outputURL: URL?
    private var textureCache: CVMetalTextureCache?
    /// Frame-pacing: don't append faster than ~30fps even if the display link
    /// runs at 60. Big files + needless GPU/encoder work otherwise.
    private var lastFrameTime: CFTimeInterval = 0
    private let minFrameInterval: CFTimeInterval = 1.0 / 60.0

    /// Library that owns the on-disk clip collection. The recorder
    /// writes directly into its directory and registers each finished
    /// clip so it auto-populates the Media Center.
    private weak var clipLibrary: ClipLibrary?

    init(clipLibrary: ClipLibrary? = nil) {
        self.clipLibrary = clipLibrary
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil,
                                  MetalContext.shared.device, nil, &cache)
        self.textureCache = cache
    }

    // MARK: Public

    func toggle() {
        if isRecording { stop() } else { start() }
    }

    func captureFrame(_ texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        guard isRecording,
              let adaptor = adaptor,
              let pool = adaptor.pixelBufferPool,
              let input = input, input.isReadyForMoreMediaData,
              let textureCache = textureCache else { return }

        let now = CACurrentMediaTime()
        if now - lastFrameTime < minFrameInterval { return }
        lastFrameTime = now

        var pb: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pb) == kCVReturnSuccess,
              let pixelBuffer = pb else { return }

        var cvTex: CVMetalTexture?
        let r = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, pixelBuffer, nil,
            .bgra8Unorm,
            CVPixelBufferGetWidth(pixelBuffer),
            CVPixelBufferGetHeight(pixelBuffer),
            0, &cvTex
        )
        guard r == kCVReturnSuccess, let cv = cvTex,
              let dst = CVMetalTextureGetTexture(cv),
              let blit = commandBuffer.makeBlitCommandEncoder() else { return }

        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(),
                  sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
                  to: dst, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin())
        blit.endEncoding()

        let pts = CMTime(seconds: now - startedAt, preferredTimescale: 600)
        // Capture pixelBuffer + cvTex via the command buffer's completion so
        // the GPU has finished writing before the encoder reads it. Holding
        // `cv` keeps the CVMetalTexture alive until the GPU is done.
        let snapshot = (pixelBuffer, cv)
        commandBuffer.addCompletedHandler { [weak self] _ in
            _ = snapshot.1   // keep alive until GPU completes
            DispatchQueue.main.async {
                guard let self = self, self.isRecording, let adaptor = self.adaptor else { return }
                if adaptor.assetWriterInput.isReadyForMoreMediaData {
                    adaptor.append(snapshot.0, withPresentationTime: pts)
                }
                self.elapsedSeconds = CACurrentMediaTime() - self.startedAt
            }
        }
    }

    // MARK: Private

    private func start() {
        // Write straight into the ClipLibrary directory so finished
        // recordings auto-populate the Media Center. Fall back to the
        // temp directory if no library is wired up (shouldn't happen
        // in normal use, but keeps the recorder standalone-testable).
        let url: URL
        if let lib = clipLibrary {
            url = lib.newRecordingURL()
        } else {
            let fileName = "WasteMix_\(Int(Date().timeIntervalSince1970)).mp4"
            url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        }
        try? FileManager.default.removeItem(at: url)

        let w = Constants.defaultWidth
        let h = Constants.defaultHeight

        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: w,
                AVVideoHeightKey: h,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 12_000_000,
                    AVVideoExpectedSourceFrameRateKey: 60,
                    AVVideoMaxKeyFrameIntervalKey: 60
                ]
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: w,
                    kCVPixelBufferHeightKey as String: h,
                    kCVPixelBufferMetalCompatibilityKey as String: true
                ]
            )
            guard writer.canAdd(input) else {
                lastError = "writer can't accept video input"
                return
            }
            writer.add(input)
            guard writer.startWriting() else {
                lastError = writer.error?.localizedDescription ?? "writer.startWriting failed"
                return
            }
            writer.startSession(atSourceTime: .zero)

            self.writer = writer
            self.input = input
            self.adaptor = adaptor
            self.outputURL = url
            self.startedAt = CACurrentMediaTime()
            self.elapsedSeconds = 0
            self.lastError = nil
            self.isRecording = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func stop() {
        guard let writer = writer, let input = input, let url = outputURL else {
            isRecording = false
            return
        }
        isRecording = false
        input.markAsFinished()
        writer.finishWriting { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.lastSavedURL = url
                self.clipLibrary?.registerRecording(at: url)
                self.saveToPhotos(url: url)
                self.writer = nil
                self.input = nil
                self.adaptor = nil
                self.outputURL = nil
            }
        }
    }

    private func saveToPhotos(url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self.lastError = "Photos permission denied — file saved to \(url.path)"
                }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { ok, err in
                DispatchQueue.main.async {
                    if !ok {
                        self.lastError = err?.localizedDescription ?? "save failed"
                    } else {
                        self.lastError = nil
                    }
                    // Don't delete — the file is the canonical clip in
                    // the Media Center library now. Photos has its own copy.
                }
            }
        }
    }
}
