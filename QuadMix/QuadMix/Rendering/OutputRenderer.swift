import Metal
import MetalKit

/// Renders the program output through the Advanced Output pipeline:
/// slicing, corner-pin warping, mesh warp, edge blending, masks, and test patterns.
/// Each output screen gets its own rendered texture.
final class OutputRenderer {
    private let ctx = MetalContext.shared
    private var screenTextures: [UUID: MTLTexture] = [:]
    private var ndiOutputs: [UUID: NDIOutput] = [:]
    private var ndiReadbackTexture: MTLTexture?

    // Cached test pattern sources (avoid recreating per frame)
    private var cachedPatternSources: [TestPatternType: PatternGeneratorSource] = [:]

    // Pre-allocated mesh vertex buffer (avoid per-frame array allocation)
    private var meshVertexBuffer: MTLBuffer?
    private var meshVertexBufferSize: Int = 0

    /// Global NDI output for the raw program feed
    var globalNDI: NDIOutput?

    /// Render all output screens from the program texture.
    func render(programTexture: MTLTexture, config: OutputConfig, commandBuffer: MTLCommandBuffer) {
        // Render each enabled screen
        for screen in config.screens where screen.enabled {
            let target = ensureScreenTexture(screen)

            if screen.showTestPattern {
                renderTestPattern(type: screen.testPatternType, to: target, commandBuffer: commandBuffer)
            } else {
                renderScreen(screen: screen, programTexture: programTexture, to: target, commandBuffer: commandBuffer)
            }

            // Per-screen NDI output
            if screen.ndiOutputEnabled && screen.destination == .ndi {
                let readback = ensureReadbackTexture(width: target.width, height: target.height, key: screen.id)
                blitTexture(from: target, to: readback, commandBuffer: commandBuffer)

                let ndi = ensureNDIOutput(for: screen)
                commandBuffer.addCompletedHandler { _ in
                    ndi.sendTexture(readback)
                }
            } else {
                stopNDIOutput(for: screen)
            }
        }

        // Global NDI output (raw program feed)
        if config.globalNDIOutput {
            if ndiReadbackTexture == nil
                || ndiReadbackTexture!.width != programTexture.width
                || ndiReadbackTexture!.height != programTexture.height {
                let desc = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .bgra8Unorm,
                    width: programTexture.width, height: programTexture.height, mipmapped: false)
                desc.storageMode = .shared
                desc.usage = [.shaderRead]
                ndiReadbackTexture = ctx.device.makeTexture(descriptor: desc)
            }

            if let blit = commandBuffer.makeBlitCommandEncoder(), let readback = ndiReadbackTexture {
                blit.copy(from: programTexture, sourceSlice: 0, sourceLevel: 0,
                          sourceOrigin: MTLOrigin(), sourceSize: MTLSize(width: programTexture.width, height: programTexture.height, depth: 1),
                          to: readback, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
                blit.endEncoding()
            }

            commandBuffer.addCompletedHandler { [weak self] _ in
                guard let self = self, let readback = self.ndiReadbackTexture else { return }
                if self.globalNDI == nil {
                    self.globalNDI = NDIOutput(name: config.globalNDIName)
                    self.globalNDI?.start()
                }
                self.globalNDI?.sendTexture(readback)
            }
        } else {
            if globalNDI != nil { globalNDI?.stop(); globalNDI = nil }
        }
    }

    func getScreenTexture(for screen: OutputScreen) -> MTLTexture? {
        screenTextures[screen.id]
    }

    func shutdown() {
        globalNDI?.stop()
        for (_, ndi) in ndiOutputs { ndi.stop() }
        ndiOutputs.removeAll()
    }

    // MARK: - Internal

    private var screenReadbackTextures: [UUID: MTLTexture] = [:]

    private func ensureReadbackTexture(width: Int, height: Int, key: UUID) -> MTLTexture {
        if let tex = screenReadbackTextures[key], tex.width == width, tex.height == height {
            return tex
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        desc.storageMode = .shared
        desc.usage = [.shaderRead]
        let tex = ctx.device.makeTexture(descriptor: desc)!
        screenReadbackTextures[key] = tex
        return tex
    }

    private func blitTexture(from src: MTLTexture, to dst: MTLTexture, commandBuffer: MTLCommandBuffer) {
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        blit.copy(from: src, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(),
                  sourceSize: MTLSize(width: src.width, height: src.height, depth: 1),
                  to: dst, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
        blit.endEncoding()
    }

    private func ensureScreenTexture(_ screen: OutputScreen) -> MTLTexture {
        if let tex = screenTextures[screen.id], tex.width == screen.width, tex.height == screen.height {
            return tex
        }
        let tex = ctx.makeTexture(width: screen.width, height: screen.height)!
        screenTextures[screen.id] = tex
        return tex
    }

    private func ensureNDIOutput(for screen: OutputScreen) -> NDIOutput {
        if let ndi = ndiOutputs[screen.id] { return ndi }
        let ndi = NDIOutput(name: screen.ndiOutputName)
        ndi.start()
        ndiOutputs[screen.id] = ndi
        return ndi
    }

    private func stopNDIOutput(for screen: OutputScreen) {
        ndiOutputs[screen.id]?.stop()
        ndiOutputs.removeValue(forKey: screen.id)
    }

    /// Render one output screen: composite all slices from the program
    private func renderScreen(screen: OutputScreen, programTexture: MTLTexture,
                              to target: MTLTexture, commandBuffer: MTLCommandBuffer) {
        // Clear to black
        let clearDesc = MTLRenderPassDescriptor()
        clearDesc.colorAttachments[0].texture = target
        clearDesc.colorAttachments[0].loadAction = .clear
        clearDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        clearDesc.colorAttachments[0].storeAction = .store
        if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: clearDesc) {
            enc.endEncoding()
        }

        // Render each slice
        for slice in screen.slices where slice.enabled {
            renderSlice(slice, programTexture: programTexture, to: target, commandBuffer: commandBuffer)
        }
    }

    /// Render a single slice with corner-pin or mesh warp
    private func renderSlice(_ slice: OutputSlice, programTexture: MTLTexture,
                             to target: MTLTexture, commandBuffer: MTLCommandBuffer) {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = target
        desc.colorAttachments[0].loadAction = .load
        desc.colorAttachments[0].storeAction = .store

        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }

        enc.setRenderPipelineState(ctx.passthroughPipeline)
        enc.setFragmentTexture(programTexture, index: 0)
        enc.setViewport(MTLViewport(originX: 0, originY: 0,
                                     width: Double(target.width), height: Double(target.height),
                                     znear: 0, zfar: 1))

        // Choose mesh warp (subdivided grid) or corner-pin (single quad)
        if slice.meshWarpEnabled && !slice.meshWarp.nodes.isEmpty {
            let (vertices, count) = buildMeshWarpVertices(slice)
            let byteLen = vertices.count * MemoryLayout<Float>.size
            // Use pre-allocated Metal buffer for large mesh data (avoids per-frame malloc)
            if byteLen > 4096 {
                if meshVertexBuffer == nil || meshVertexBufferSize < byteLen {
                    meshVertexBufferSize = byteLen * 2 // over-allocate for growth
                    meshVertexBuffer = ctx.device.makeBuffer(length: meshVertexBufferSize, options: .storageModeShared)
                }
                if let buf = meshVertexBuffer {
                    memcpy(buf.contents(), vertices, byteLen)
                    enc.setVertexBuffer(buf, offset: 0, index: 0)
                } else {
                    enc.setVertexBytes(vertices, length: byteLen, index: 0)
                }
            } else {
                enc.setVertexBytes(vertices, length: byteLen, index: 0)
            }
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
        } else {
            let vertices = buildSliceVertices(slice)
            enc.setVertexBytes(vertices, length: vertices.count * MemoryLayout<Float>.size, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }

        enc.endEncoding()
    }

    // MARK: - Mesh Warp Rendering

    /// Build triangles from the mesh warp grid.
    /// Each cell in the grid becomes 2 triangles.
    /// Node positions are the warped output coords; source UVs come from the original grid positions.
    private func buildMeshWarpVertices(_ slice: OutputSlice) -> ([Float], Int) {
        let mesh = slice.meshWarp
        let cols = mesh.cols
        let rows = mesh.rows
        let nodes = mesh.nodes

        guard nodes.count == (cols + 1) * (rows + 1) else {
            // Fallback to corner-pin if mesh is malformed
            return (buildSliceVertices(slice), 6)
        }

        var verts: [Float] = []
        var triCount = 0

        for r in 0..<rows {
            for c in 0..<cols {
                // Four corner indices of this cell
                let iTL = r * (cols + 1) + c
                let iTR = r * (cols + 1) + c + 1
                let iBL = (r + 1) * (cols + 1) + c
                let iBR = (r + 1) * (cols + 1) + c + 1

                // Warped output positions (from dragged nodes, 0-1 within the slice)
                let posTL = nodes[iTL]
                let posTR = nodes[iTR]
                let posBL = nodes[iBL]
                let posBR = nodes[iBR]

                // Original grid positions → source texture UVs
                let uTL = Float(c) / Float(cols)
                let vTL = Float(r) / Float(rows)
                let uTR = Float(c + 1) / Float(cols)
                let vTR = Float(r) / Float(rows)
                let uBL = Float(c) / Float(cols)
                let vBL = Float(r + 1) / Float(rows)
                let uBR = Float(c + 1) / Float(cols)
                let vBR = Float(r + 1) / Float(rows)

                // Map source UVs through the slice's source region
                func srcUV(_ u: Float, _ v: Float) -> (Float, Float) {
                    return (slice.sourceX + u * slice.sourceW, slice.sourceY + v * slice.sourceH)
                }

                // Map warped node position to clip space through the slice's output rect
                func toClip(_ node: WarpNode) -> (Float, Float) {
                    let sx = slice.outputX + node.x * slice.outputW
                    let sy = slice.outputY + node.y * slice.outputH
                    return (sx * 2.0 - 1.0, 1.0 - sy * 2.0)
                }

                let clipTL = toClip(posTL)
                let clipTR = toClip(posTR)
                let clipBL = toClip(posBL)
                let clipBR = toClip(posBR)

                let stTL = srcUV(uTL, vTL)
                let stTR = srcUV(uTR, vTR)
                let stBL = srcUV(uBL, vBL)
                let stBR = srcUV(uBR, vBR)

                // Triangle 1: TL-BL-BR
                verts.append(contentsOf: [clipTL.0, clipTL.1, stTL.0, stTL.1])
                verts.append(contentsOf: [clipBL.0, clipBL.1, stBL.0, stBL.1])
                verts.append(contentsOf: [clipBR.0, clipBR.1, stBR.0, stBR.1])

                // Triangle 2: TL-BR-TR
                verts.append(contentsOf: [clipTL.0, clipTL.1, stTL.0, stTL.1])
                verts.append(contentsOf: [clipBR.0, clipBR.1, stBR.0, stBR.1])
                verts.append(contentsOf: [clipTR.0, clipTR.1, stTR.0, stTR.1])

                triCount += 6
            }
        }

        return (verts, triCount)
    }

    // MARK: - Corner-Pin Warp (single quad)

    /// Build 6 vertices (2 triangles) for a slice with corner-pin warping
    private func buildSliceVertices(_ slice: OutputSlice) -> [Float] {
        let tl = clipPos(slice.warpTL, in: slice)
        let tr = clipPos(slice.warpTR, in: slice)
        let bl = clipPos(slice.warpBL, in: slice)
        let br = clipPos(slice.warpBR, in: slice)

        let sl = slice.sourceX
        let st = slice.sourceY
        let sr = slice.sourceX + slice.sourceW
        let sb = slice.sourceY + slice.sourceH

        return [
            tl.0, tl.1, sl, st,
            bl.0, bl.1, sl, sb,
            br.0, br.1, sr, sb,

            tl.0, tl.1, sl, st,
            br.0, br.1, sr, sb,
            tr.0, tr.1, sr, st,
        ]
    }

    private func clipPos(_ point: NormalizedPoint, in slice: OutputSlice) -> (Float, Float) {
        let screenX = slice.outputX + point.x * slice.outputW
        let screenY = slice.outputY + point.y * slice.outputH
        let clipX = screenX * 2.0 - 1.0
        let clipY = 1.0 - screenY * 2.0
        return (clipX, clipY)
    }

    /// Render a test pattern to a target texture (cached source — no alloc per frame)
    private func renderTestPattern(type: TestPatternType, to target: MTLTexture, commandBuffer: MTLCommandBuffer) {
        let pattern: PatternType
        switch type {
        case .colorBars: pattern = .colorBars
        case .gradient: pattern = .gradient
        case .grid, .crosshatch, .white: pattern = .checkerboard
        }

        let source: PatternGeneratorSource
        if let cached = cachedPatternSources[type] {
            source = cached
        } else {
            let s = PatternGeneratorSource(pattern: pattern, width: target.width, height: target.height)
            cachedPatternSources[type] = s
            source = s
        }
        if let pb = source.latestPixelBuffer,
           let tex = MetalContext.shared.textureConverter.texture(from: pb) {
            let desc = MTLRenderPassDescriptor()
            desc.colorAttachments[0].texture = target
            desc.colorAttachments[0].loadAction = .dontCare
            desc.colorAttachments[0].storeAction = .store
            if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: desc) {
                enc.setRenderPipelineState(ctx.passthroughPipeline)
                enc.setVertexBuffer(ctx.quadVertexBuffer, offset: 0, index: 0)
                enc.setFragmentTexture(tex, index: 0)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
                enc.endEncoding()
            }
        }
    }
}
