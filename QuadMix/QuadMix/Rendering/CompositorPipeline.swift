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

        // Channel 0 → base layer
        let first = channels[0]
        let firstTex = applyPIPIfNeeded(ch: first, commandBuffer: commandBuffer)
        if let progress = first.wipeProgress, let dir = first.wipeDirection {
            renderWipeFromBlack(texture: firstTex, progress: progress, direction: dir, target: texA, commandBuffer: commandBuffer)
        } else {
            renderWithOpacity(texture: firstTex, opacity: first.opacity, target: texA, commandBuffer: commandBuffer)
        }

        var src = texA
        var dst = texB

        // Channels 1+
        for i in 1..<channels.count {
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

    /// Standard blend
    private func blendNormal(base: MTLTexture, layer: MTLTexture, mode: ChannelBlendMode, opacity: Float, target: MTLTexture, commandBuffer: MTLCommandBuffer) {
        guard let pipeline = ctx.blendPipelines[mode] else { return }
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
