import Metal

struct BlendUniforms {
    var opacity: Float
    var padding: (Float, Float, Float) = (0, 0, 0)
}

struct TransitionUniforms {
    var progress: Float
    var direction: Int32
    var padding: (Float, Float) = (0, 0)
}

struct PIPUniforms {
    var scale: Float
    var offsetX: Float
    var offsetY: Float
    var opacity: Float
}

struct ChannelCompositeInfo {
    let texture: MTLTexture
    let blendMode: ChannelBlendMode
    let opacity: Float
    let wipeProgress: Float?
    let wipeDirection: Int?
    let pipSettings: PIPSettings
}

final class CompositorPipeline {
    private let ctx = MetalContext.shared
    // Three intermediates: A/B for ping-pong, C for wipe scratch
    private var intermediateA: MTLTexture?
    private var intermediateB: MTLTexture?
    private var intermediateC: MTLTexture?

    func resize(width: Int, height: Int) {
        guard width > 0 && height > 0 else { return }
        intermediateA = ctx.makeTexture(width: width, height: height)
        intermediateB = ctx.makeTexture(width: width, height: height)
        intermediateC = ctx.makeTexture(width: width, height: height)
    }

    func composite(
        channels: [ChannelCompositeInfo],
        globalColorCorrection: ColorCorrection,
        into drawable: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) {
        guard !channels.isEmpty else {
            clearToBlack(drawable, commandBuffer: commandBuffer)
            return
        }

        let w = drawable.width, h = drawable.height
        if intermediateA == nil || intermediateA!.width != w || intermediateA!.height != h {
            resize(width: w, height: h)
        }
        guard let texA = intermediateA, let texB = intermediateB, let texC = intermediateC else {
            clearToBlack(drawable, commandBuffer: commandBuffer)
            return
        }

        // Vixid / Resolume-style: every channel respects its own blend mode,
        // including channel 1. Start with a black program, then composite each
        // channel via its blend mode against the accumulated result. Most
        // modes are identity-on-black for the first layer (Normal, Add,
        // Screen, Difference, Lighten, etc. all return the layer unchanged
        // when blended over black) so this is visually transparent for those
        // modes — but Multiply / HSL / Hard Mix on channel 1 will now
        // correctly resolve to black, matching pro-mixer behavior.
        clearToBlack(texA, commandBuffer: commandBuffer)
        var src = texA
        var dst = texB

        for i in 0..<channels.count {
            let ch = channels[i]
            let chTex = applyPIPIfNeeded(ch: ch, commandBuffer: commandBuffer)

            if let progress = ch.wipeProgress, let dir = ch.wipeDirection {
                renderWipeAB(base: src, layer: chTex, progress: progress, direction: dir, target: dst, commandBuffer: commandBuffer)
            } else {
                blendNormal(base: src, layer: chTex, mode: ch.blendMode, opacity: ch.opacity, target: dst, commandBuffer: commandBuffer)
            }
            swap(&src, &dst)
        }

        // Global color correction → drawable
        if globalColorCorrection.isIdentity {
            passthrough(source: src, target: drawable, commandBuffer: commandBuffer)
        } else {
            colorCorrect(source: src, target: drawable, correction: globalColorCorrection, commandBuffer: commandBuffer)
        }
    }

    // MARK: - PIP

    /// If channel has non-default PIP, renders it scaled/offset into intermediateC.
    /// Returns the texture to use for compositing (original if no PIP, intermediateC if PIP).
    private func applyPIPIfNeeded(ch: ChannelCompositeInfo, commandBuffer: MTLCommandBuffer) -> MTLTexture {
        guard !ch.pipSettings.isDefault, let pipTex = intermediateC else {
            return ch.texture
        }

        let desc = renderPass(pipTex, clear: true)
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else {
            return ch.texture
        }

        enc.setRenderPipelineState(ctx.pipPipeline)
        enc.setVertexBuffer(ctx.quadVertexBuffer, offset: 0, index: 0)
        enc.setFragmentTexture(ch.texture, index: 0)

        var u = PIPUniforms(
            scale: ch.pipSettings.scale,
            offsetX: ch.pipSettings.offsetX,
            offsetY: ch.pipSettings.offsetY,
            opacity: 1.0
        )
        enc.setFragmentBytes(&u, length: MemoryLayout<PIPUniforms>.size, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        enc.endEncoding()

        return pipTex
    }

    // MARK: - Render Passes

    /// Render channel at opacity onto black
    private func renderWithOpacity(texture: MTLTexture, opacity: Float, target: MTLTexture, commandBuffer: MTLCommandBuffer) {
        let desc = renderPass(target, clear: true)
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        enc.setRenderPipelineState(ctx.passthroughOpacityPipeline)
        enc.setVertexBuffer(ctx.quadVertexBuffer, offset: 0, index: 0)
        enc.setFragmentTexture(texture, index: 0)
        var u = BlendUniforms(opacity: opacity)
        enc.setFragmentBytes(&u, length: MemoryLayout<BlendUniforms>.size, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        enc.endEncoding()
    }

    /// Single-input wipe from black (for base channel)
    private func renderWipeFromBlack(texture: MTLTexture, progress: Float, direction: Int, target: MTLTexture, commandBuffer: MTLCommandBuffer) {
        let desc = renderPass(target, clear: true)
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        enc.setRenderPipelineState(ctx.wipePipeline)
        enc.setVertexBuffer(ctx.quadVertexBuffer, offset: 0, index: 0)
        enc.setFragmentTexture(texture, index: 0)
        var u = TransitionUniforms(progress: progress, direction: Int32(direction))
        enc.setFragmentBytes(&u, length: MemoryLayout<TransitionUniforms>.size, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        enc.endEncoding()
    }

    /// Two-input wipe: spatially cuts between base and layer.
    /// Like a real analog mixer T-bar wipe.
    private func renderWipeAB(base: MTLTexture, layer: MTLTexture, progress: Float, direction: Int, target: MTLTexture, commandBuffer: MTLCommandBuffer) {
        let desc = renderPass(target, clear: false)
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        enc.setRenderPipelineState(ctx.wipeABPipeline)
        enc.setVertexBuffer(ctx.quadVertexBuffer, offset: 0, index: 0)
        enc.setFragmentTexture(base, index: 0)   // A = current program
        enc.setFragmentTexture(layer, index: 1)   // B = incoming channel
        var u = TransitionUniforms(progress: progress, direction: Int32(direction))
        enc.setFragmentBytes(&u, length: MemoryLayout<TransitionUniforms>.size, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        enc.endEncoding()
    }

    /// Standard blend. Falls back to `.normal` if the requested mode's pipeline
    /// somehow isn't registered — silently dropping the channel made debugging
    /// "I picked X and nothing happened" reports impossible.
    private func blendNormal(base: MTLTexture, layer: MTLTexture, mode: ChannelBlendMode, opacity: Float, target: MTLTexture, commandBuffer: MTLCommandBuffer) {
        let pipeline: MTLRenderPipelineState
        if let p = ctx.blendPipelines[mode] {
            pipeline = p
        } else if let normal = ctx.blendPipelines[.normal] {
            Self.warnMissingPipeline(for: mode)
            pipeline = normal
        } else {
            return
        }
        let desc = renderPass(target, clear: false)
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        enc.setRenderPipelineState(pipeline)
        enc.setVertexBuffer(ctx.quadVertexBuffer, offset: 0, index: 0)
        enc.setFragmentTexture(base, index: 0)
        enc.setFragmentTexture(layer, index: 1)
        var u = BlendUniforms(opacity: opacity)
        enc.setFragmentBytes(&u, length: MemoryLayout<BlendUniforms>.size, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        enc.endEncoding()
    }

    private static var warnedMissingModes: Set<ChannelBlendMode> = []
    private static func warnMissingPipeline(for mode: ChannelBlendMode) {
        guard !warnedMissingModes.contains(mode) else { return }
        warnedMissingModes.insert(mode)
        print("CompositorPipeline: blend pipeline missing for '\(mode.rawValue)' — falling back to normal. Check that blend_\(mode.rawValue) exists in BlendModes.metal and the file is in the target's Compile Sources.")
    }

    private func passthrough(source: MTLTexture, target: MTLTexture, commandBuffer: MTLCommandBuffer) {
        let desc = renderPass(target, clear: false)
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        enc.setRenderPipelineState(ctx.passthroughPipeline)
        enc.setVertexBuffer(ctx.quadVertexBuffer, offset: 0, index: 0)
        enc.setFragmentTexture(source, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        enc.endEncoding()
    }

    private func colorCorrect(source: MTLTexture, target: MTLTexture, correction: ColorCorrection, commandBuffer: MTLCommandBuffer) {
        let desc = renderPass(target, clear: true)
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        enc.setRenderPipelineState(ctx.colorCorrectionPipeline)
        enc.setVertexBuffer(ctx.quadVertexBuffer, offset: 0, index: 0)
        enc.setFragmentTexture(source, index: 0)
        var u = ColorCorrectionUniforms(
            brightness: correction.brightness, contrast: correction.contrast,
            saturation: correction.saturation, hueShift: correction.hueShift,
            redGain: correction.redGain, greenGain: correction.greenGain,
            blueGain: correction.blueGain, blackLevel: correction.blackLevel,
            liftR: correction.liftR, liftG: correction.liftG,
            liftB: correction.liftB, padding: 0
        )
        enc.setFragmentBytes(&u, length: MemoryLayout<ColorCorrectionUniforms>.size, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        enc.endEncoding()
    }

    private func clearToBlack(_ texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        let desc = renderPass(texture, clear: true)
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }
        enc.endEncoding()
    }

    private func renderPass(_ texture: MTLTexture, clear: Bool) -> MTLRenderPassDescriptor {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = texture
        desc.colorAttachments[0].loadAction = clear ? .clear : .dontCare
        desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        desc.colorAttachments[0].storeAction = .store
        return desc
    }
}
