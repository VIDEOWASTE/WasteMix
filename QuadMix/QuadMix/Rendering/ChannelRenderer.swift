import Metal
import QuartzCore

final class ChannelRenderer {
    let channel: Channel
    private let ctx = MetalContext.shared
    /// Session-relative time origin. CACurrentMediaTime() is mach_absolute
    /// seconds since boot; on a Mac that's been up for weeks, casting to
    /// Float32 loses sub-millisecond precision and per-frame strobe / feedback
    /// shaders judder. Subtracting this baseline before the cast keeps shader
    /// `time` in a small range with full precision.
    private static let timeOrigin: CFTimeInterval = CACurrentMediaTime()
    private static var sessionTime: Float { Float(CACurrentMediaTime() - timeOrigin) }
    /// When the source is cleared (set to nil), drop the cached last
    /// source/freeze textures too — otherwise `currentTexture(...)` keeps
    /// reprocessing the stale frame and PVW shows the old image
    /// indefinitely. This is the actual cause of the "Clear Source still
    /// shows the last frame" bug; the earlier `RenderEngine` nil-check
    /// fired only when `currentTexture` returned nil, but `lastSourceTexture`
    /// kept it non-nil.
    var frameProvider: FrameProvider? {
        didSet {
            if frameProvider == nil {
                lastSourceTexture = nil
                frozenTexture = nil
            }
        }
    }

    private var lastSourceTexture: MTLTexture?
    private var frozenTexture: MTLTexture?

    // Dedicated output textures (not pooled — persist across frames)
    private var colorCorrectedTex: MTLTexture?
    private var effectOutputTex: MTLTexture?
    private var keyOutputTex: MTLTexture?
    // Sized to the program canvas (1920x1080), not the source. The transform
    // pass bakes rotation + letterbox/fill into this so the compositor can
    // blend portrait phones, square NDI, etc. against any other layer
    // without aspect-stretch.
    private var transformOutputTex: MTLTexture?
    // PIP runs as the final per-channel pass. Living here (rather than in
    // the compositor) means PIP shows in PVW too, not just PGM.
    private var pipOutputTex: MTLTexture?

    // Feedback effect: persistent buffer from previous frame
    private var feedbackTexA: MTLTexture?
    private var feedbackTexB: MTLTexture?
    private var feedbackPing = true

    init(channel: Channel) {
        self.channel = channel
    }

    /// Returns the fully processed texture: source → color correction → effect → keying.
    func currentTexture(commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        // Treat the .freeze effect type as a freeze trigger so the standalone
        // toggle isn't needed — picking the effect freezes the channel.
        let frozen = channel.isFrozen || channel.effectType == .freeze

        // Pull latest frame (unless frozen)
        if !frozen {
            if let provider = frameProvider, let newTex = provider.latestTexture {
                lastSourceTexture = newTex
            }
        } else {
            // On first freeze, snapshot current frame
            if frozenTexture == nil, let src = lastSourceTexture {
                frozenTexture = copyTexture(src, commandBuffer: commandBuffer)
            }
        }

        // If unfrozen, clear the frozen snapshot
        if !frozen {
            frozenTexture = nil
        }

        guard let srcTex = (frozen ? frozenTexture : lastSourceTexture) ?? lastSourceTexture else {
            return nil
        }

        var current = srcTex

        // 1. Color correction
        if !channel.colorCorrection.isIdentity {
            current = applyColorCorrection(input: current, commandBuffer: commandBuffer)
        }

        // 2. Effect
        if channel.effectType != .none && channel.effectType != .freeze {
            if let fx = applyEffect(input: current, commandBuffer: commandBuffer) {
                current = fx
            }
        }

        // 3. Keying
        if channel.keySettings.isActive {
            if let keyed = applyKey(input: current, commandBuffer: commandBuffer) {
                current = keyed
            }
        }

        // 4. Source framing — rotation override + fit/fill onto the program
        //    canvas. Always run; this is what stops portrait phones / square
        //    NDI from being aspect-stretched into 1920x1080 by the compositor.
        if let transformed = applyTransform(input: current, commandBuffer: commandBuffer) {
            current = transformed
        }

        // 5. PIP — scale, offset, rotation. Skipped at default settings to
        //    save a render pass. Running this here (instead of in the
        //    compositor) means PIP changes show up in PVW too.
        if !channel.pipSettings.isDefault {
            if let pip = applyPIP(input: current, commandBuffer: commandBuffer) {
                current = pip
            }
        }

        return current
    }

    // MARK: - Processing passes

    private func applyColorCorrection(input: MTLTexture, commandBuffer: MTLCommandBuffer) -> MTLTexture {
        colorCorrectedTex = ensureTexture(colorCorrectedTex, matching: input)
        guard let out = colorCorrectedTex else { return input }

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = out
        desc.colorAttachments[0].loadAction = .dontCare
        desc.colorAttachments[0].storeAction = .store

        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return input }
        enc.setRenderPipelineState(ctx.colorCorrectionPipeline)
        enc.setVertexBuffer(ctx.quadVertexBuffer, offset: 0, index: 0)
        enc.setFragmentTexture(input, index: 0)

        var u = ColorCorrectionUniforms(
            brightness: channel.colorCorrection.brightness,
            contrast: channel.colorCorrection.contrast,
            saturation: channel.colorCorrection.saturation,
            hueShift: channel.colorCorrection.hueShift,
            redGain: channel.colorCorrection.redGain,
            greenGain: channel.colorCorrection.greenGain,
            blueGain: channel.colorCorrection.blueGain,
            blackLevel: channel.colorCorrection.blackLevel,
            liftR: channel.colorCorrection.liftR,
            liftG: channel.colorCorrection.liftG,
            liftB: channel.colorCorrection.liftB,
            padding: 0
        )
        enc.setFragmentBytes(&u, length: MemoryLayout<ColorCorrectionUniforms>.size, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        enc.endEncoding()
        return out
    }

    private func applyEffect(input: MTLTexture, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        guard let funcName = channel.effectType.metalFunctionName,
              let pipeline = ctx.effectPipelines[funcName] else { return nil }

        // Feedback effect uses ping-pong textures
        if channel.effectType.isFeedback {
            return applyFeedback(input: input, pipeline: pipeline, commandBuffer: commandBuffer)
        }

        effectOutputTex = ensureTexture(effectOutputTex, matching: input)
        guard let out = effectOutputTex else { return nil }

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = out
        desc.colorAttachments[0].loadAction = .dontCare
        desc.colorAttachments[0].storeAction = .store

        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return nil }
        enc.setRenderPipelineState(pipeline)
        enc.setVertexBuffer(ctx.quadVertexBuffer, offset: 0, index: 0)
        enc.setFragmentTexture(input, index: 0)

        var params = EffectUniforms(
            param1: channel.effectIntensity,
            param2: channel.effectParam2,
            time: Self.sessionTime,
            padding: 0
        )
        enc.setFragmentBytes(&params, length: MemoryLayout<EffectUniforms>.size, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        enc.endEncoding()
        return out
    }

    private func applyFeedback(input: MTLTexture, pipeline: MTLRenderPipelineState, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        // Ensure ping-pong feedback textures
        feedbackTexA = ensureTexture(feedbackTexA, matching: input)
        feedbackTexB = ensureTexture(feedbackTexB, matching: input)
        guard let texA = feedbackTexA, let texB = feedbackTexB else { return nil }

        // Read from one, write to the other
        let readTex = feedbackPing ? texA : texB
        let writeTex = feedbackPing ? texB : texA
        feedbackPing.toggle()

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = writeTex
        desc.colorAttachments[0].loadAction = .dontCare
        desc.colorAttachments[0].storeAction = .store

        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return nil }
        enc.setRenderPipelineState(pipeline)
        enc.setVertexBuffer(ctx.quadVertexBuffer, offset: 0, index: 0)
        enc.setFragmentTexture(input, index: 0)    // current frame
        enc.setFragmentTexture(readTex, index: 1)   // previous feedback

        var params = EffectUniforms(
            param1: channel.effectIntensity,
            param2: channel.effectParam2,
            time: Self.sessionTime,
            padding: 0
        )
        enc.setFragmentBytes(&params, length: MemoryLayout<EffectUniforms>.size, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        enc.endEncoding()
        return writeTex
    }

    private func applyPIP(input: MTLTexture, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        pipOutputTex = ensureTexture(pipOutputTex, matching: input)
        guard let out = pipOutputTex else { return nil }

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = out
        desc.colorAttachments[0].loadAction = .clear
        desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        desc.colorAttachments[0].storeAction = .store

        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return nil }
        enc.setRenderPipelineState(ctx.pipPipeline)
        enc.setVertexBuffer(ctx.quadVertexBuffer, offset: 0, index: 0)
        enc.setFragmentTexture(input, index: 0)

        var u = PIPUniforms(
            scale: channel.pipSettings.scale,
            offsetX: channel.pipSettings.offsetX,
            offsetY: channel.pipSettings.offsetY,
            opacity: 1.0,
            rotationRadians: channel.pipSettings.rotation * .pi / 180.0,
            targetAspect: Float(input.width) / Float(input.height)
        )
        enc.setFragmentBytes(&u, length: MemoryLayout<PIPUniforms>.size, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        enc.endEncoding()
        return out
    }

    private func applyTransform(input: MTLTexture, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        let targetW = Constants.defaultWidth
        let targetH = Constants.defaultHeight

        if transformOutputTex == nil ||
           transformOutputTex!.width != targetW ||
           transformOutputTex!.height != targetH {
            transformOutputTex = ctx.makeTexture(width: targetW, height: targetH)
        }
        guard let out = transformOutputTex else { return nil }

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = out
        desc.colorAttachments[0].loadAction = .clear
        desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        desc.colorAttachments[0].storeAction = .store

        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return nil }
        enc.setRenderPipelineState(ctx.transformPipeline)
        enc.setVertexBuffer(ctx.quadVertexBuffer, offset: 0, index: 0)
        enc.setFragmentTexture(input, index: 0)

        var u = TransformUniforms(
            rotationRadians: channel.rotation.radians,
            sourceAspect: Float(input.width) / Float(input.height),
            targetAspect: Float(targetW) / Float(targetH),
            fillMode: channel.fitMode.shaderValue
        )
        enc.setFragmentBytes(&u, length: MemoryLayout<TransformUniforms>.size, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        enc.endEncoding()
        return out
    }

    private func applyKey(input: MTLTexture, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        let pipeline: MTLRenderPipelineState
        switch channel.keySettings.type {
        case .none: return nil
        case .lumaKey: pipeline = ctx.lumaKeyPipeline
        case .chromaKey: pipeline = ctx.chromaKeyPipeline
        }

        keyOutputTex = ensureTexture(keyOutputTex, matching: input)
        guard let out = keyOutputTex else { return nil }

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = out
        desc.colorAttachments[0].loadAction = .dontCare
        desc.colorAttachments[0].storeAction = .store

        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return nil }
        enc.setRenderPipelineState(pipeline)
        enc.setVertexBuffer(ctx.quadVertexBuffer, offset: 0, index: 0)
        enc.setFragmentTexture(input, index: 0)

        var params = EffectUniforms(
            param1: channel.keySettings.threshold,
            param2: channel.keySettings.softness,
            time: channel.keySettings.keyHue,
            // Repurposed `padding` slot — carries the invert flag for the
            // luma + chroma key shaders. Other effect shaders ignore it.
            padding: channel.keySettings.invert ? 1 : 0
        )
        enc.setFragmentBytes(&params, length: MemoryLayout<EffectUniforms>.size, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        enc.endEncoding()
        return out
    }

    // MARK: - Helpers

    private func ensureTexture(_ existing: MTLTexture?, matching ref: MTLTexture) -> MTLTexture? {
        if let tex = existing, tex.width == ref.width, tex.height == ref.height {
            return tex
        }
        return ctx.makeTexture(width: ref.width, height: ref.height)
    }

    private func copyTexture(_ src: MTLTexture, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        guard let dst = ctx.makeTexture(width: src.width, height: src.height) else { return nil }
        // Use blit encoder for fast GPU-side copy (no render pipeline overhead)
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: src, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(), sourceSize: MTLSize(width: src.width, height: src.height, depth: 1),
                  to: dst, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
        blit.endEncoding()
        return dst
    }
}

struct TransformUniforms {
    var rotationRadians: Float
    var sourceAspect: Float
    var targetAspect: Float
    var fillMode: Int32  // 0 = fit (letterbox), 1 = fill (crop)
}

struct ColorCorrectionUniforms {
    var brightness: Float
    var contrast: Float
    var saturation: Float
    var hueShift: Float
    var redGain: Float
    var greenGain: Float
    var blueGain: Float
    var blackLevel: Float
    var liftR: Float
    var liftG: Float
    var liftB: Float
    var padding: Float
}
