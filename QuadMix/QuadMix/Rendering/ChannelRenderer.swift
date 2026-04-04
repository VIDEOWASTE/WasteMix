import Metal
import QuartzCore

final class ChannelRenderer {
    let channel: Channel
    private let ctx = MetalContext.shared
    var frameProvider: FrameProvider?

    private var lastSourceTexture: MTLTexture?
    private var frozenTexture: MTLTexture?

    // Dedicated output textures (not pooled — persist across frames)
    private var colorCorrectedTex: MTLTexture?
    private var effectOutputTex: MTLTexture?
    private var keyOutputTex: MTLTexture?

    // Feedback effect: persistent buffer from previous frame
    private var feedbackTexA: MTLTexture?
    private var feedbackTexB: MTLTexture?
    private var feedbackPing = true

    init(channel: Channel) {
        self.channel = channel
    }

    /// Returns the fully processed texture: source → color correction → effect → keying.
    func currentTexture(commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        // Pull latest frame (unless frozen)
        if !channel.isFrozen {
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
        if !channel.isFrozen {
            frozenTexture = nil
        }

        guard let srcTex = (channel.isFrozen ? frozenTexture : lastSourceTexture) ?? lastSourceTexture else {
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
            time: Float(CACurrentMediaTime()),
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
            time: Float(CACurrentMediaTime()),
            padding: 0
        )
        enc.setFragmentBytes(&params, length: MemoryLayout<EffectUniforms>.size, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        enc.endEncoding()
        return writeTex
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
            padding: 0
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
