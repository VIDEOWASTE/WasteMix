import Metal
import MetalKit
import QuartzCore

final class RenderEngine: NSObject, MTKViewDelegate {
    let mixerState: MixerState
    let outputConfig = OutputConfig()
    let transitionEngine = TransitionEngine()
    let audioEngine = AudioEngine()
    let outputRenderer = OutputRenderer()
    let displayManager = DisplayManager()

    private let ctx = MetalContext.shared
    private let compositorPipeline = CompositorPipeline()
    private(set) var channelRenderers: [ChannelRenderer] = []

    private let inflightSemaphore = DispatchSemaphore(value: 2)
    private(set) var channelPreviewTextures: [MTLTexture?] = Array(repeating: nil, count: 4)

    private var lastTimestamp: CFTimeInterval = 0

    init(mixerState: MixerState) {
        self.mixerState = mixerState
        super.init()
        self.channelRenderers = mixerState.channels.map { ChannelRenderer(channel: $0) }
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

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        compositorPipeline.resize(width: Int(size.width), height: Int(size.height))
    }

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        lastTimestamp = now

        guard inflightSemaphore.wait(timeout: .now() + .milliseconds(20)) == .success else { return }

        transitionEngine.update(channels: mixerState.channels, timestamp: now)
        updateLFOs(time: Float(now))
        updateAudioReactivity()

        guard let drawable = view.currentDrawable,
              let commandBuffer = ctx.commandQueue.makeCommandBuffer() else {
            inflightSemaphore.signal()
            return
        }

        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.inflightSemaphore.signal()
        }

        var activeChannels: [ChannelCompositeInfo] = []

        for (i, renderer) in channelRenderers.enumerated() {
            let channel = mixerState.channels[i]

            if let tex = renderer.currentTexture(commandBuffer: commandBuffer) {
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
                        // Auto-transition driving the wipe
                        wipeProgress = channel.transitionProgress
                        wipeDirection = transition.type.wipeDirection
                    } else if channel.transitionConfig.type.isWipe {
                        // Manual fader = manual T-bar wipe
                        // Fader at 0 = wipe progress 0 (channel hidden)
                        // Fader at 1 = wipe progress 1 (channel fully revealed)
                        wipeProgress = channel.faderLevel
                        wipeDirection = channel.transitionConfig.type.wipeDirection
                    } else {
                        // Mix/cut/dip: fader is pure opacity, no spatial wipe
                        wipeProgress = nil
                        wipeDirection = nil
                    }

                    activeChannels.append(ChannelCompositeInfo(
                        texture: tex,
                        blendMode: channel.blendMode,
                        opacity: channel.faderLevel,
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
            into: drawable.texture,
            commandBuffer: commandBuffer
        )

        // Advanced Output: process through output renderer (NDI out, mapping, etc.)
        outputRenderer.render(
            programTexture: drawable.texture,
            config: outputConfig,
            commandBuffer: commandBuffer
        )

        commandBuffer.present(drawable)
        commandBuffer.commit()

        // Flush texture cache to release stale CVMetalTexture mappings
        ctx.textureConverter.flush()
    }

    // MARK: - LFO

    private func updateLFOs(time: Float) {
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
