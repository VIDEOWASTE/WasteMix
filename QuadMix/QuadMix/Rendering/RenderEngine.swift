import Metal
import MetalKit
import QuartzCore

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
                        wipeDirection: wipeDirection,
                        pipSettings: channel.pipSettings
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

        commandBuffer.commit()

        // Flush texture cache to release stale CVMetalTexture mappings
        ctx.textureConverter.flush()
    }

    // MARK: - LFO

    private func updateLFOs(time: Float) {
        // Master LFO — routed to the master target.
        if mixerState.masterLFO.isActive {
            let v = mixerState.masterLFO.compute(time: time, bpm: mixerState.bpm)
            mixerState.masterLFO.currentValue = v
            switch mixerState.masterLFOTarget {
            case .masterLevel:
                mixerState.masterLevel = v
            case .crossfader:
                mixerState.masterLevel = 1.0  // not dimming when sweeping crossfader
                mixerState.crossfaderPos = v
                mixerState.applyCrossfader()
            }
        } else {
            // No master LFO running — make sure we're not stuck at a stale dim level.
            mixerState.masterLevel = 1.0
        }

        for channel in mixerState.channels {
            guard channel.lfo.isActive else { continue }

            let value = channel.lfo.compute(time: time, bpm: mixerState.bpm)
            channel.lfo.currentValue = value

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
            var react = channel.audioReact
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
            let prev = react.currentValue
            let smoothed = prev + (mapped - prev) * (1.0 - react.smoothing)
            react.currentValue = smoothed
            channel.audioReact = react

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
