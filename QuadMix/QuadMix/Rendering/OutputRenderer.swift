import Metal
import MetalKit

/// Renders the program output through the Advanced Output pipeline:
/// slicing, corner-pin warping, mesh warp, edge blending, masks, and test patterns.
/// Each output screen gets its own rendered texture.
final class OutputRenderer {
    private let ctx = MetalContext.shared
    private var screenTextures: [UUID: MTLTexture] = [:]
    private var ndiOutputs: [UUID: NDIOutput] = [:]

    // Triple-buffered readback for NDI sends. The completion handler reads
    // from a frame-specific texture so the next frame's blit can't overwrite
    // bytes still being copied out by NDI — that race is what caused the
    // tearing/banding artifacts in the broadcast.
    private static let readbackRingSize = 3
    private var ndiReadbackRing: [MTLTexture] = []
    private var ndiReadbackIndex: Int = 0

    // NDI broadcast resolution — VGA over WiFi is rock solid and still very
    // usable for VJ projection. 1080p was saturating; 720p was OK; 640×480
    // gives plenty of headroom.
    private static let ndiBroadcastWidth: Int = 640
    private static let ndiBroadcastHeight: Int = 480
    private var ndiDownscaledTex: MTLTexture?

    // Throttle NDI sends to ~30 fps. The engine ticks at 60, but 1080p60 BGRA
    // is ~474 MB/s before NDI compression and saturates network/CPU on
    // iPad — sending every other frame keeps the program smooth and lets
    // receivers stay in sync.
    private var ndiSendFrameCounter: Int = 0
    // Engine ticks at 60fps; divisor=2 → 30fps NDI. With 640×480 the bandwidth
    // budget is now generous so we can spend it on smoother motion.
    private var ndiSendDivisor: Int { 2 }
    private var shouldSendNDIThisFrame: Bool {
        defer { ndiSendFrameCounter &+= 1 }
        return ndiSendFrameCounter % ndiSendDivisor == 0
    }

    // Cached test pattern sources (avoid recreating per frame)
    private var cachedPatternSources: [TestPatternType: PatternGeneratorSource] = [:]

    // Pre-allocated mesh vertex buffer (avoid per-frame array allocation)
    private var meshVertexBuffer: MTLBuffer?
    private var meshVertexBufferSize: Int = 0

    /// Global NDI output for the raw program feed.
    /// Mutated from Metal completion handlers (which run on Metal's internal
    /// threads); `globalNDILock` guards the lazy-init so two simultaneous
    /// frames can't both see nil and both create a sender.
    var globalNDI: NDIOutput?
    private let globalNDILock = NSLock()

    /// Per-slice source resolution. The slice picks `programTexture` (the mix)
    /// or one of the four channel textures. Caller passes both so the slice
    /// renderer can route appropriately.
    func textureForSlice(_ slice: OutputSlice,
                         programTexture: MTLTexture,
                         channelTextures: [MTLTexture?]) -> MTLTexture {
        if let i = slice.sourceType.channelIndex,
           i < channelTextures.count,
           let tex = channelTextures[i] {
            return tex
        }
        return programTexture
    }

    /// Render all output screens. `programTexture` is the mix; `channelTextures`
    /// provides the post-processed per-channel output so slices can pull a
    /// single channel instead of the full mix.
    func render(programTexture: MTLTexture,
                channelTextures: [MTLTexture?],
                config: OutputConfig,
                commandBuffer: MTLCommandBuffer) {
        // Decide once per render call whether NDI sends fire this frame.
        // Reads are stable across both per-screen and global-program paths.
        let sendNDI = shouldSendNDIThisFrame

        // Always render every screen's texture so the Advanced Output canvas
        // preview is live; `enabled` only gates whether output is actually sent
        // to NDI / external display.
        for screen in config.screens {
            let target = ensureScreenTexture(screen)

            if screen.showTestPattern {
                renderTestPattern(type: screen.testPatternType, to: target, commandBuffer: commandBuffer)
            } else {
                renderScreen(screen: screen,
                             programTexture: programTexture,
                             channelTextures: channelTextures,
                             to: target,
                             commandBuffer: commandBuffer)
            }

            // Per-screen NDI output (still gated by enabled + destination)
            if screen.enabled && screen.ndiOutputEnabled && screen.destination == .ndi {
                if sendNDI {
                    let readback = ensureReadbackTexture(width: target.width, height: target.height, key: screen.id)
                    blitTexture(from: target, to: readback, commandBuffer: commandBuffer)

                    let ndi = ensureNDIOutput(for: screen)
                    commandBuffer.addCompletedHandler { _ in
                        ndi.sendTexture(readback)
                    }
                }
            } else {
                stopNDIOutput(for: screen)
            }
        }

        // Global NDI output (raw program feed) — downscaled to 720p so iPad +
        // WiFi can sustain it. Render pass scales 1080p → 720p, then blit to
        // a CPU-readable ring slot for the NDI library.
        if config.globalNDIOutput && sendNDI {
            let nw = Self.ndiBroadcastWidth
            let nh = Self.ndiBroadcastHeight

            // Lazy-init the downscale target (private storage, render target)
            if ndiDownscaledTex == nil
                || ndiDownscaledTex!.width != nw
                || ndiDownscaledTex!.height != nh {
                let desc = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .bgra8Unorm, width: nw, height: nh, mipmapped: false)
                desc.usage = [.renderTarget, .shaderRead]
                desc.storageMode = .private
                ndiDownscaledTex = ctx.device.makeTexture(descriptor: desc)
            }

            // Lazy-init readback ring at the broadcast resolution
            if ndiReadbackRing.isEmpty || ndiReadbackRing[0].width != nw || ndiReadbackRing[0].height != nh {
                ndiReadbackRing.removeAll()
                for _ in 0..<Self.readbackRingSize {
                    let desc = MTLTextureDescriptor.texture2DDescriptor(
                        pixelFormat: .bgra8Unorm, width: nw, height: nh, mipmapped: false)
                    desc.storageMode = .shared
                    desc.usage = [.shaderRead]
                    if let t = ctx.device.makeTexture(descriptor: desc) { ndiReadbackRing.append(t) }
                }
                ndiReadbackIndex = 0
            }

            // 1) Downscale: program → ndiDownscaledTex via passthrough render
            if let downscale = ndiDownscaledTex {
                let desc = MTLRenderPassDescriptor()
                desc.colorAttachments[0].texture = downscale
                desc.colorAttachments[0].loadAction = .dontCare
                desc.colorAttachments[0].storeAction = .store
                if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: desc) {
                    enc.setRenderPipelineState(ctx.passthroughPipeline)
                    enc.setVertexBuffer(ctx.quadVertexBuffer, offset: 0, index: 0)
                    enc.setFragmentTexture(programTexture, index: 0)
                    enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
                    enc.endEncoding()
                }

                // 2) Blit downscaled → readback (.shared so CPU can read)
                let readback = ndiReadbackRing[ndiReadbackIndex]
                ndiReadbackIndex = (ndiReadbackIndex + 1) % ndiReadbackRing.count

                if let blit = commandBuffer.makeBlitCommandEncoder() {
                    blit.copy(from: downscale, sourceSlice: 0, sourceLevel: 0,
                              sourceOrigin: MTLOrigin(), sourceSize: MTLSize(width: nw, height: nh, depth: 1),
                              to: readback, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
                    blit.endEncoding()
                }

                commandBuffer.addCompletedHandler { [weak self] _ in
                    guard let self = self else { return }
                    // Lazy-init under a lock so two adjacent frames whose
                    // completion handlers fire on different Metal threads
                    // can't both create+start the sender.
                    self.globalNDILock.lock()
                    if self.globalNDI == nil {
                        let ndi = NDIOutput(name: config.globalNDIName)
                        ndi.start()
                        self.globalNDI = ndi
                    }
                    let ndi = self.globalNDI
                    self.globalNDILock.unlock()
                    ndi?.sendTexture(readback)
                }
            }
        } else if !config.globalNDIOutput {
            globalNDILock.lock()
            let ndi = globalNDI
            globalNDI = nil
            globalNDILock.unlock()
            ndi?.stop()
        }
        // (config.globalNDIOutput && !sendNDI) → just skip this tick, keep sender alive
    }

    func getScreenTexture(for screen: OutputScreen) -> MTLTexture? {
        screenTextures[screen.id]
    }

    func shutdown() {
        globalNDILock.lock()
        let g = globalNDI
        globalNDI = nil
        globalNDILock.unlock()
        g?.stop()
        for (_, ndi) in ndiOutputs { ndi.stop() }
        ndiOutputs.removeAll()
    }

    // MARK: - Internal

    private var screenReadbackRing: [UUID: [MTLTexture]] = [:]
    private var screenReadbackIndex: [UUID: Int] = [:]

    private func ensureReadbackTexture(width: Int, height: Int, key: UUID) -> MTLTexture {
        var ring = screenReadbackRing[key] ?? []
        if ring.isEmpty || ring[0].width != width || ring[0].height != height {
            ring.removeAll()
            for _ in 0..<Self.readbackRingSize {
                let desc = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
                desc.storageMode = .shared
                desc.usage = [.shaderRead]
                if let t = ctx.device.makeTexture(descriptor: desc) { ring.append(t) }
            }
            screenReadbackRing[key] = ring
            screenReadbackIndex[key] = 0
        }
        let idx = (screenReadbackIndex[key] ?? 0) % ring.count
        screenReadbackIndex[key] = (idx + 1) % ring.count
        return ring[idx]
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
        // Defensive clamp — the user-facing W/H text fields don't bound their
        // values, so a typo of 0 or 100000 reaches us here. We allocate at
        // sane minimums/maxes rather than crash with a force-unwrap.
        let safeW = max(64, min(screen.width, 4096))
        let safeH = max(64, min(screen.height, 4096))
        if let tex = screenTextures[screen.id], tex.width == safeW, tex.height == safeH {
            return tex
        }
        if let tex = ctx.makeTexture(width: safeW, height: safeH) {
            screenTextures[screen.id] = tex
            return tex
        }
        // Last-resort tiny fallback so the render pass can still proceed
        // instead of crashing the whole engine.
        if let fallback = ctx.makeTexture(width: 64, height: 64) {
            screenTextures[screen.id] = fallback
            return fallback
        }
        fatalError("Metal texture allocation failed for screen output")
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

    /// Render one output screen: composite all slices from their chosen sources.
    private func renderScreen(screen: OutputScreen,
                              programTexture: MTLTexture,
                              channelTextures: [MTLTexture?],
                              to target: MTLTexture,
                              commandBuffer: MTLCommandBuffer) {
        // Clear to black
        let clearDesc = MTLRenderPassDescriptor()
        clearDesc.colorAttachments[0].texture = target
        clearDesc.colorAttachments[0].loadAction = .clear
        clearDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        clearDesc.colorAttachments[0].storeAction = .store
        if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: clearDesc) {
            enc.endEncoding()
        }

        // Render each slice from its own picked source.
        for slice in screen.slices where slice.enabled {
            let srcTex = textureForSlice(slice, programTexture: programTexture, channelTextures: channelTextures)
            renderSlice(slice, programTexture: srcTex, to: target, commandBuffer: commandBuffer)
        }
    }

    /// Render a single slice with corner-pin or mesh warp.
    /// `programTexture` here is the slice's chosen source (mix or channel).
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
