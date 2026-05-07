import SwiftUI

private let R = Color(red: 1.0, green: 0.15, blue: 0.15)

/// Advanced Output — Resolume-style canvas + controls.
struct AdvancedOutputView: View {
    let outputConfig: OutputConfig
    let renderEngine: RenderEngine
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            // Smaller scaling than before — Advanced Output was getting too
            // chunky on iPad Pro. Was 0.65–1.3, now 0.6–1.0.
            let panelScale = min(1.0, max(0.6, w / 700.0))
            // sc passed to functions but we use scaleEffect for uniform scaling
            let sc: CGFloat = 1.0

            VStack(spacing: 0) {
                // Top bar — TFM/MESH/zoom pushed toward center via leading
                // padding so the controls clear the iPad multitasking
                // close/minimize bubble in the top-left of the window.
                HStack(spacing: 6) {
                    Spacer().frame(width: 80)

                    canvasModeBarInline(sc)

                    Spacer()

                    ndiSendButton(sc)
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color(red: 0.05, green: 0.05, blue: 0.06))

                // Main content
                HStack(spacing: 0) {
                    // Canvas — fills remaining space, grey background.
                    // Outer padding gives a safe buffer between the canvas
                    // content (slice borders + mesh nodes) and the iPad
                    // window's edge so drags can't accidentally trigger
                    // Stage Manager resize.
                    outputCanvas(sc, size: geo.size)
                        .frame(maxWidth: .infinity)
                        .padding(.leading, 18)
                        .padding(.bottom, 18)
                        .background(Color(red: 0.06, green: 0.06, blue: 0.07))

                    Rectangle().fill(R.opacity(0.1)).frame(width: 1)

                    // Right panel — narrower default so the canvas gets more room.
                    let panelW = min(max(w * 0.3, 160), 240)
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 12) {
                            screenTabs(sc)
                            destinationPicker(sc)
                            sliceList(sc)
                            if let slice = selectedSliceBinding {
                                inputSection(slice, sc)
                                transformSection(slice, sc)
                                blendSection(slice, sc)
                            }
                            Spacer(minLength: 8)
                        }
                        .padding(10)
                        .scaleEffect(panelScale, anchor: .topLeading)
                        .frame(width: panelW / panelScale, alignment: .leading)
                        .frame(width: panelW, alignment: .leading)
                    }
                    .frame(width: panelW)
                    .clipped()
                }
            }
            // Right panel + outer chrome stay dark; canvas area is grey
            // (applied above on the canvas itself).
            .background(Color(red: 0.03, green: 0.03, blue: 0.04))
        }
    }

    private func scaled(_ v: CGFloat, _ sc: CGFloat) -> CGFloat { v }
    private func sf(_ v: CGFloat, _ sc: CGFloat) -> CGFloat { v }

    // MARK: - Top Bar

    private func outputTopBar(_ sc: CGFloat) -> some View {
        HStack(spacing: scaled(6, sc)) {
            Rectangle().fill(R).frame(width: scaled(2, sc), height: scaled(10, sc))
            Text("ADV OUTPUT")
                .font(.system(size: sf(9, sc), weight: .black, design: .monospaced))
                .foregroundColor(.white).tracking(scaled(1, sc))
            Spacer()

            // NDI sends popover
            ndiSendButton(sc)

            // LIVE toggle
            let idx = outputConfig.selectedScreenIndex
            if idx < outputConfig.screens.count {
                let screen = outputConfig.screens[idx]
                HStack(spacing: scaled(4, sc)) {
                    Circle()
                        .fill(screen.enabled && screen.destination != .none ? Color.green : Color.gray.opacity(0.5))
                        .frame(width: scaled(8, sc), height: scaled(8, sc))
                    Text(screen.enabled && screen.destination != .none ? "LIVE" : "OFF")
                        .font(.system(size: sf(8, sc), weight: .black, design: .monospaced))
                        .foregroundColor(screen.enabled && screen.destination != .none ? .green : .gray)
                }
                Toggle("", isOn: Binding(
                    get: { outputConfig.screens[idx].enabled },
                    set: { outputConfig.screens[idx].enabled = $0 }
                )).labelsHidden().tint(R).scaleEffect(1.0)
            }
        }
        .padding(.horizontal, scaled(8, sc)).padding(.vertical, scaled(4, sc))
        .background(Color(red: 0.05, green: 0.05, blue: 0.06))
    }

    // MARK: - Inline Mode Controls (embedded in top bar)

    @ViewBuilder
    private func canvasModeBarInline(_ sc: CGFloat) -> some View {
        HStack(spacing: 6) {
            modeButton("arrow.up.left.and.arrow.down.right", "TFM", .transform, sc)
            modeButton("circle.grid.3x3", "MESH", .mesh, sc)

            // Mode-specific options (mesh node controls or transform aspect lock)
            if outputConfig.canvasEditMode == .mesh {
                Button {
                    let si = outputConfig.selectedScreenIndex
                    let sli = outputConfig.selectedSliceIndex
                    if si < outputConfig.screens.count, sli < outputConfig.screens[si].slices.count {
                        outputConfig.screens[si].slices[sli].meshWarpEnabled = true
                        outputConfig.screens[si].slices[sli].meshWarp.subdivide()
                        Haptics.tap()
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(R)
                        .frame(width: 32, height: 26)
                        .background(R.opacity(0.18))
                        .overlay(Rectangle().stroke(R.opacity(0.4), lineWidth: 0.5))
                }.buttonStyle(TactileButtonStyle())

                Button {
                    let si = outputConfig.selectedScreenIndex
                    let sli = outputConfig.selectedSliceIndex
                    if si < outputConfig.screens.count, sli < outputConfig.screens[si].slices.count {
                        outputConfig.screens[si].slices[sli].meshWarp.unsubdivide()
                        Haptics.tap()
                    }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(R.opacity(0.85))
                        .frame(width: 32, height: 26)
                        .background(R.opacity(0.10))
                        .overlay(Rectangle().stroke(R.opacity(0.3), lineWidth: 0.5))
                }.buttonStyle(TactileButtonStyle())

                Button {
                    let si = outputConfig.selectedScreenIndex
                    let sli = outputConfig.selectedSliceIndex
                    if si < outputConfig.screens.count, sli < outputConfig.screens[si].slices.count {
                        outputConfig.screens[si].slices[sli].meshWarp.reset()
                        Haptics.thud()
                    }
                } label: {
                    Text("RST").font(.system(size: 9, weight: .black, design: .monospaced))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundColor(.gray)
                        .padding(.horizontal, 6).padding(.vertical, 6)
                        .background(Color.white.opacity(0.05))
                }.buttonStyle(TactileButtonStyle())
            } else if outputConfig.canvasEditMode == .transform {
                // FREE / LOCK aspect ratio — mirrors the mesh sub-options style.
                let si = outputConfig.selectedScreenIndex
                let sli = outputConfig.selectedSliceIndex
                let locked: Bool = (si < outputConfig.screens.count
                                    && sli < outputConfig.screens[si].slices.count)
                                    ? outputConfig.screens[si].slices[sli].lockAspectRatio
                                    : false
                // LOCK first since it's the default; FREE second.
                Button {
                    if si < outputConfig.screens.count, sli < outputConfig.screens[si].slices.count {
                        outputConfig.screens[si].slices[sli].lockAspectRatio = true
                        // Snap the slice's H to source aspect so it matches
                        // the video edges immediately (instead of waiting for
                        // the next corner drag to correct it).
                        let scr = outputConfig.screens[si]
                        let srcA: Float = 1920.0 / 1080.0
                        let scrA: Float = Float(scr.width) / Float(max(1, scr.height))
                        let target: Float = srcA / scrA
                        let curW = outputConfig.screens[si].slices[sli].outputW
                        outputConfig.screens[si].slices[sli].outputH = max(0.05, curW / target)
                        Haptics.tap()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold))
                        Text("LOCK").font(.system(size: 9, weight: .black, design: .monospaced))
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .foregroundColor(locked ? .white : .gray)
                    .padding(.horizontal, 6).padding(.vertical, 6)
                    .background(locked ? R.opacity(0.3) : Color.white.opacity(0.05))
                    .overlay(Rectangle().stroke(locked ? R : Color.white.opacity(0.1), lineWidth: 0.5))
                }.buttonStyle(TactileButtonStyle())
                Button {
                    if si < outputConfig.screens.count, sli < outputConfig.screens[si].slices.count {
                        outputConfig.screens[si].slices[sli].lockAspectRatio = false
                        Haptics.tap()
                    }
                } label: {
                    Text("FREE").font(.system(size: 9, weight: .black, design: .monospaced))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundColor(locked ? .gray : .white)
                        .padding(.horizontal, 6).padding(.vertical, 6)
                        .background(locked ? Color.white.opacity(0.05) : R.opacity(0.3))
                        .overlay(Rectangle().stroke(locked ? Color.white.opacity(0.1) : R, lineWidth: 0.5))
                }.buttonStyle(TactileButtonStyle())
            }

            Spacer(minLength: 4)

            // Right-side cluster: SNAP magnet + zoom −/%/+ controls. Grouped
            // into a single fixed-width HStack so outer flex spacers can't
            // compress or clip individual buttons. All four buttons share the
            // same compact 32×26 frame so the row reads as one unit.
            HStack(spacing: 3) {
                let snap = outputConfig.snapToCanvas
                Button {
                    outputConfig.snapToCanvas.toggle()
                    Haptics.tap()
                } label: {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(snap ? .white : .white.opacity(0.7))
                        .frame(width: 32, height: 26)
                        .background(snap ? R.opacity(0.45) : Color.white.opacity(0.10))
                        .overlay(Rectangle().stroke(snap ? R : Color.white.opacity(0.25), lineWidth: 0.5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(TactileButtonStyle())

                Image(systemName: "minus")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 26)
                    .background(Color.white.opacity(0.10))
                    .overlay(Rectangle().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        canvasZoom = max(0.5, canvasZoom - 0.2)
                        pinchBaseZoom = canvasZoom
                        Haptics.tap()
                    }

                Text("\(Int(canvasZoom * 100))%")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundColor(.gray)
                    .frame(width: 38, height: 26)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        canvasZoom = 1.0
                        pinchBaseZoom = 1.0
                        Haptics.tap()
                    }

                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 26)
                    .background(Color.white.opacity(0.10))
                    .overlay(Rectangle().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        canvasZoom = min(4.0, canvasZoom + 0.2)
                        pinchBaseZoom = canvasZoom
                        Haptics.tap()
                    }
            }
            .fixedSize()
        }
    }

    // MARK: - Canvas Mode Bar (legacy)

    private func canvasModeBar(_ sc: CGFloat) -> some View {
        HStack(spacing: scaled(4, sc)) {
            modeButton("arrow.up.left.and.arrow.down.right", "TRANSFORM", .transform, sc)
            modeButton("circle.grid.3x3", "MESH", .mesh, sc)

            // Add nodes / reset (only visible in mesh mode)
            if outputConfig.canvasEditMode == .mesh {
                Button {
                    let si = outputConfig.selectedScreenIndex
                    let sli = outputConfig.selectedSliceIndex
                    if si < outputConfig.screens.count, sli < outputConfig.screens[si].slices.count {
                        outputConfig.screens[si].slices[sli].meshWarpEnabled = true
                        outputConfig.screens[si].slices[sli].meshWarp.subdivide()
                    }
                } label: {
                    HStack(spacing: scaled(2, sc)) {
                        Image(systemName: "plus").font(.system(size: sf(9, sc), weight: .bold))
                        Text("ADD").font(.system(size: sf(7, sc), weight: .black, design: .monospaced))
                    }
                    .foregroundColor(R)
                    .padding(.horizontal, scaled(6, sc)).padding(.vertical, scaled(3, sc))
                    .background(R.opacity(0.15))
                }.buttonStyle(TactileButtonStyle())

                Button {
                    let si = outputConfig.selectedScreenIndex
                    let sli = outputConfig.selectedSliceIndex
                    if si < outputConfig.screens.count, sli < outputConfig.screens[si].slices.count {
                        outputConfig.screens[si].slices[sli].meshWarp.reset()
                    }
                } label: {
                    Text("RESET").font(.system(size: sf(7, sc), weight: .black, design: .monospaced))
                        .foregroundColor(.gray)
                        .padding(.horizontal, scaled(6, sc)).padding(.vertical, scaled(3, sc))
                        .background(Color.white.opacity(0.05))
                }.buttonStyle(TactileButtonStyle())

                // Grid size indicator
                let si = outputConfig.selectedScreenIndex
                let sli = outputConfig.selectedSliceIndex
                if si < outputConfig.screens.count, sli < outputConfig.screens[si].slices.count {
                    let mesh = outputConfig.screens[si].slices[sli].meshWarp
                    if !mesh.nodes.isEmpty {
                        Text("\(mesh.cols)x\(mesh.rows)")
                            .font(.system(size: sf(7, sc), weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }
            }

            Spacer()

            let mode = outputConfig.canvasEditMode
            Text(mode == .transform ? "Move / resize" : "Drag nodes to warp")
                .font(.system(size: sf(6, sc), weight: .medium, design: .monospaced))
                .foregroundColor(.gray)
        }
        .padding(.horizontal, scaled(6, sc))
        .padding(.vertical, scaled(3, sc))
        .background(Color(red: 0.04, green: 0.04, blue: 0.05))
    }

    private func modeButton(_ icon: String, _ label: String, _ mode: CanvasEditMode, _ sc: CGFloat) -> some View {
        let isActive = outputConfig.canvasEditMode == mode
        return Button {
            outputConfig.canvasEditMode = mode
            if mode == .mesh {
                let si = outputConfig.selectedScreenIndex
                let sli = outputConfig.selectedSliceIndex
                if si < outputConfig.screens.count, sli < outputConfig.screens[si].slices.count {
                    outputConfig.screens[si].slices[sli].meshWarpEnabled = true
                    if outputConfig.screens[si].slices[sli].meshWarp.nodes.isEmpty {
                        outputConfig.screens[si].slices[sli].meshWarp.generateGrid()
                    }
                }
            }
            Haptics.tap()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                Text(label)
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundColor(isActive ? .white : .gray)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isActive ? R.opacity(0.4) : Color.white.opacity(0.04))
            .overlay(
                Rectangle().stroke(isActive ? R : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(TactileButtonStyle())
        .layoutPriority(1)
    }

    // MARK: - Canvas

    @State private var dragStartX: Float = 0
    @State private var dragStartY: Float = 0
    @State private var isDraggingSlice = false
    // Corner-drag start state — captured once per drag so aspect-lock and
    // anchor-to-opposite-corner math doesn't re-evaluate against half-updated
    // values mid-drag.
    @State private var isDraggingCorner = false
    @State private var cornerStartX: Float = 0
    @State private var cornerStartY: Float = 0
    @State private var cornerStartW: Float = 0
    @State private var cornerStartH: Float = 0
    @State private var showNDIPopover = false
    @State private var canvasZoom: CGFloat = 1.0
    @State private var pinchBaseZoom: CGFloat = 1.0

    private func outputCanvas(_ sc: CGFloat, size: CGSize) -> some View {
        GeometryReader { geo in
            let idx = outputConfig.selectedScreenIndex
            if idx < outputConfig.screens.count {
                let screen = outputConfig.screens[idx]
                let aspect = CGFloat(screen.width) / CGFloat(screen.height)
                // Canvas occupies ~80% of available area at 100% zoom so there's
                // breathing room for slices that extend past the screen edges.
                let baseFit = min(geo.size.width - 20, (geo.size.height - 20) * aspect) * 0.8
                let canvasW = baseFit
                let canvasH = canvasW / aspect
                let ox = (geo.size.width - canvasW) / 2
                let oy = (geo.size.height - canvasH) / 2
                let handleSize = scaled(12, sc)

                ZStack {
                    // Dark "canvas" rect at the actual screen aspect (16:9 by
                    // default), positioned to match canvasW × canvasH. The
                    // surrounding area shows the wrapper's lighter grey so
                    // the canvas reads clearly at any zoom.
                    Rectangle()
                        .fill(Color(red: 0.02, green: 0.02, blue: 0.03))
                        .frame(width: canvasW, height: canvasH)
                        .position(x: ox + canvasW/2, y: oy + canvasH/2)

                    // Program preview (non-interactive). Sized and positioned
                    // to match canvasW/canvasH exactly so the slice borders
                    // (which are positioned in canvasW × canvasH space) align
                    // 1:1 with the rendered image — without this the preview
                    // filled geo.size with aspect-fit and the slice rect
                    // moved at a different scale, looking like a perspective.
                    if let tex = renderEngine.outputRenderer.getScreenTexture(for: screen) {
                        PreviewView(device: MetalContext.shared.device, textureProvider: { tex })
                            .frame(width: canvasW, height: canvasH)
                            .position(x: ox + canvasW/2, y: oy + canvasH/2)
                            .allowsHitTesting(false)
                    }

                    // Layer 1: Slice borders (non-selected) — tap to select (disabled in mesh mode).
                    // Sorted largest-first so SMALLER slices render on top of
                    // bigger ones — that way a tap inside the small slice
                    // hits it (instead of always picking the topmost-by-creation).
                    let sortedSlices = Array(screen.slices.enumerated())
                        .sorted { ($0.element.outputW * $0.element.outputH) > ($1.element.outputW * $1.element.outputH) }
                    ForEach(sortedSlices, id: \.element.id) { si, slice in
                        if outputConfig.selectedSliceIndex != si {
                            let x = ox + CGFloat(slice.outputX) * canvasW
                            let y = oy + CGFloat(slice.outputY) * canvasH
                            let w = CGFloat(slice.outputW) * canvasW
                            let h = CGFloat(slice.outputH) * canvasH
                            // Visual border only — selection is handled by the
                            // single canvas-wide SpatialTapGesture below so
                            // overlapping slices don't fight for taps.
                            Rectangle()
                                .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                                .frame(width: w, height: h)
                                .position(x: x + w/2, y: y + h/2)
                                .allowsHitTesting(false)

                            Text(slice.name)
                                .font(.system(size: sf(8, sc), weight: .heavy, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                                .position(x: x + scaled(25, sc), y: y + scaled(10, sc))

                            // Dim mesh grid for non-selected
                            if slice.meshWarpEnabled && !slice.meshWarp.nodes.isEmpty {
                                meshGridLines(slice: slice, x: x, y: y, w: w, h: h, color: Color.white.opacity(0.1))
                            }
                        }
                    }

                    // Layer 2: Selected slice — bounds-check at every access
                    let selIdx = min(outputConfig.selectedSliceIndex, max(0, outputConfig.screens[idx].slices.count - 1))
                    let editMode = outputConfig.canvasEditMode
                    if !outputConfig.screens[idx].slices.isEmpty && selIdx < outputConfig.screens[idx].slices.count {
                        // Read live values every render
                        let sx = CGFloat(outputConfig.screens[idx].slices[selIdx].outputX)
                        let sy = CGFloat(outputConfig.screens[idx].slices[selIdx].outputY)
                        let sw = CGFloat(outputConfig.screens[idx].slices[selIdx].outputW)
                        let sh = CGFloat(outputConfig.screens[idx].slices[selIdx].outputH)
                        let x = ox + sx * canvasW
                        let y = oy + sy * canvasH
                        let w = sw * canvasW
                        let h = sh * canvasH

                        // Thin slice border
                        Rectangle()
                            .stroke(R.opacity(0.5), lineWidth: 0.5)
                            .frame(width: w, height: h)
                            .position(x: x + w/2, y: y + h/2)
                            .allowsHitTesting(false)

                        // Label
                        Text(outputConfig.screens[idx].slices[selIdx].name)
                            .font(.system(size: sf(8, sc), weight: .heavy, design: .monospaced))
                            .foregroundColor(R)
                            .position(x: x + scaled(25, sc), y: y + scaled(10, sc))
                            .allowsHitTesting(false)

                        // Mesh grid lines (always visible if mesh enabled)
                        if outputConfig.screens[idx].slices[selIdx].meshWarpEnabled {
                            let nodeCount = outputConfig.screens[idx].slices[selIdx].meshWarp.nodes.count
                            if nodeCount > 0 {
                                meshGridLines(slice: outputConfig.screens[idx].slices[selIdx], x: x, y: y, w: w, h: h,
                                              color: editMode == .mesh ? R.opacity(0.7) : R.opacity(0.2))
                            }
                        }

                        // === TRANSFORM MODE ===
                        // Bounds relaxed to [-1, 2] so slices can extend beyond
                        // the canvas — Resolume-style overscan placement. The
                        // 0.05 minimum width/height stays so handles don't
                        // collapse to a point.
                        if editMode == .transform {
                            Rectangle()
                                .fill(Color.white.opacity(0.001))
                                .frame(width: w, height: h)
                                .position(x: x + w/2, y: y + h/2)
                                .gesture(DragGesture()
                                    .onChanged { drag in
                                        // Capture anchor on the FIRST onChanged of
                                        // each drag — the previous "translation < 2"
                                        // heuristic missed cases where a new drag
                                        // started already moving fast, leaving
                                        // dragStartX stale and making the slice
                                        // jump across the canvas.
                                        if !isDraggingSlice {
                                            dragStartX = outputConfig.screens[idx].slices[selIdx].outputX
                                            dragStartY = outputConfig.screens[idx].slices[selIdx].outputY
                                            isDraggingSlice = true
                                        }
                                        let dx = Float(drag.translation.width / canvasW)
                                        let dy = Float(drag.translation.height / canvasH)
                                        var newX = dragStartX + dx
                                        var newY = dragStartY + dy
                                        if outputConfig.snapToCanvas {
                                            let sliceW = outputConfig.screens[idx].slices[selIdx].outputW
                                            let sliceH = outputConfig.screens[idx].slices[selIdx].outputH
                                            let t: Float = 0.025
                                            // Left / right edge → 0 or 1 - sliceW
                                            if abs(newX) < t { newX = 0 }
                                            else if abs(newX + sliceW - 1) < t { newX = 1 - sliceW }
                                            if abs(newY) < t { newY = 0 }
                                            else if abs(newY + sliceH - 1) < t { newY = 1 - sliceH }
                                        }
                                        outputConfig.screens[idx].slices[selIdx].outputX = max(-1, min(2, newX))
                                        outputConfig.screens[idx].slices[selIdx].outputY = max(-1, min(2, newY))
                                    }
                                    .onEnded { _ in
                                        isDraggingSlice = false
                                    })

                            // Handles sit centered exactly on the slice corners
                            // so they "lock" to the image edges.
                            let lock = outputConfig.screens[idx].slices[selIdx].lockAspectRatio
                            // Target normalized W/H ratio so the slice's PIXEL
                            // aspect matches the SOURCE pixel aspect (no stretch).
                            // sourceAspect / screenAspect — for the common
                            // 16:9 source on a 16:9 screen this is 1.0 (square
                            // in normalized coords = 16:9 in pixels).
                            let sourceAspect: Float = 1920.0 / 1080.0
                            let screenAspect: Float = Float(screen.width) / Float(max(1, screen.height))
                            let lockAspect: Float = sourceAspect / screenAspect

                            // TL — anchor to BR (right, bottom stay fixed)
                            cornerHandle(x: x, y: y, size: handleSize, filled: true)
                                .highPriorityGesture(DragGesture()
                                    .onChanged { drag in
                                        if !isDraggingCorner {
                                            cornerStartX = outputConfig.screens[idx].slices[selIdx].outputX
                                            cornerStartY = outputConfig.screens[idx].slices[selIdx].outputY
                                            cornerStartW = outputConfig.screens[idx].slices[selIdx].outputW
                                            cornerStartH = outputConfig.screens[idx].slices[selIdx].outputH
                                            isDraggingCorner = true
                                        }
                                        let right = cornerStartX + cornerStartW
                                        let bottom = cornerStartY + cornerStartH
                                        var newX = max(-1, min(right - 0.05, Float((drag.location.x - ox) / canvasW)))
                                        var newY = max(-1, min(bottom - 0.05, Float((drag.location.y - oy) / canvasH)))
                                        if outputConfig.snapToCanvas {
                                            let t: Float = 0.025
                                            if abs(newX) < t { newX = 0 }
                                            if abs(newY) < t { newY = 0 }
                                        }
                                        if lock {
                                            let aspect = lockAspect
                                            let dxN = right - newX
                                            let dyN = bottom - newY
                                            // Pick whichever delta moved more from start
                                            if abs(dxN - cornerStartW) > abs(dyN - cornerStartH) {
                                                let h = dxN / aspect
                                                newY = bottom - h
                                            } else {
                                                let w = dyN * aspect
                                                newX = right - w
                                            }
                                        }
                                        outputConfig.screens[idx].slices[selIdx].outputX = newX
                                        outputConfig.screens[idx].slices[selIdx].outputY = newY
                                        outputConfig.screens[idx].slices[selIdx].outputW = right - newX
                                        outputConfig.screens[idx].slices[selIdx].outputH = bottom - newY
                                    }
                                    .onEnded { _ in isDraggingCorner = false })

                            // BR — anchor to TL (left, top stay fixed). Most common scale corner.
                            cornerHandle(x: x + w, y: y + h, size: handleSize, filled: true)
                                .highPriorityGesture(DragGesture()
                                    .onChanged { drag in
                                        if !isDraggingCorner {
                                            cornerStartX = outputConfig.screens[idx].slices[selIdx].outputX
                                            cornerStartY = outputConfig.screens[idx].slices[selIdx].outputY
                                            cornerStartW = outputConfig.screens[idx].slices[selIdx].outputW
                                            cornerStartH = outputConfig.screens[idx].slices[selIdx].outputH
                                            isDraggingCorner = true
                                        }
                                        var newW = max(0.05, min(2 - cornerStartX, Float((drag.location.x - x) / canvasW)))
                                        var newH = max(0.05, min(2 - cornerStartY, Float((drag.location.y - y) / canvasH)))
                                        if outputConfig.snapToCanvas {
                                            let t: Float = 0.025
                                            if abs(cornerStartX + newW - 1) < t { newW = 1 - cornerStartX }
                                            if abs(cornerStartY + newH - 1) < t { newH = 1 - cornerStartY }
                                        }
                                        if lock {
                                            let aspect = lockAspect
                                            // Pick whichever axis moved more from start
                                            if abs(newW - cornerStartW) > abs(newH - cornerStartH) {
                                                newH = max(0.05, newW / aspect)
                                            } else {
                                                newW = max(0.05, newH * aspect)
                                            }
                                        }
                                        outputConfig.screens[idx].slices[selIdx].outputW = newW
                                        outputConfig.screens[idx].slices[selIdx].outputH = newH
                                    }
                                    .onEnded { _ in isDraggingCorner = false })

                            // TR — anchor to BL
                            cornerHandle(x: x + w, y: y, size: handleSize, filled: false)
                                .highPriorityGesture(DragGesture()
                                    .onChanged { drag in
                                        if !isDraggingCorner {
                                            cornerStartX = outputConfig.screens[idx].slices[selIdx].outputX
                                            cornerStartY = outputConfig.screens[idx].slices[selIdx].outputY
                                            cornerStartW = outputConfig.screens[idx].slices[selIdx].outputW
                                            cornerStartH = outputConfig.screens[idx].slices[selIdx].outputH
                                            isDraggingCorner = true
                                        }
                                        let bottom = cornerStartY + cornerStartH
                                        var newW = max(0.05, min(2 - cornerStartX, Float((drag.location.x - x) / canvasW)))
                                        var newY = max(-1, min(bottom - 0.05, Float((drag.location.y - oy) / canvasH)))
                                        if outputConfig.snapToCanvas {
                                            let t: Float = 0.025
                                            if abs(cornerStartX + newW - 1) < t { newW = 1 - cornerStartX }
                                            if abs(newY) < t { newY = 0 }
                                        }
                                        var newH = bottom - newY
                                        if lock {
                                            let aspect = lockAspect
                                            if abs(newW - cornerStartW) > abs(newH - cornerStartH) {
                                                newH = max(0.05, newW / aspect)
                                                newY = bottom - newH
                                            } else {
                                                newW = max(0.05, newH * aspect)
                                            }
                                        }
                                        outputConfig.screens[idx].slices[selIdx].outputW = newW
                                        outputConfig.screens[idx].slices[selIdx].outputY = newY
                                        outputConfig.screens[idx].slices[selIdx].outputH = newH
                                    }
                                    .onEnded { _ in isDraggingCorner = false })

                            // BL — anchor to TR
                            cornerHandle(x: x, y: y + h, size: handleSize, filled: false)
                                .highPriorityGesture(DragGesture()
                                    .onChanged { drag in
                                        if !isDraggingCorner {
                                            cornerStartX = outputConfig.screens[idx].slices[selIdx].outputX
                                            cornerStartY = outputConfig.screens[idx].slices[selIdx].outputY
                                            cornerStartW = outputConfig.screens[idx].slices[selIdx].outputW
                                            cornerStartH = outputConfig.screens[idx].slices[selIdx].outputH
                                            isDraggingCorner = true
                                        }
                                        let right = cornerStartX + cornerStartW
                                        var newX = max(-1, min(right - 0.05, Float((drag.location.x - ox) / canvasW)))
                                        var newH = max(0.05, min(2 - cornerStartY, Float((drag.location.y - y) / canvasH)))
                                        if outputConfig.snapToCanvas {
                                            let t: Float = 0.025
                                            if abs(newX) < t { newX = 0 }
                                            if abs(cornerStartY + newH - 1) < t { newH = 1 - cornerStartY }
                                        }
                                        var newW = right - newX
                                        if lock {
                                            let aspect = lockAspect
                                            if abs(newW - cornerStartW) > abs(newH - cornerStartH) {
                                                newH = max(0.05, newW / aspect)
                                            } else {
                                                newW = max(0.05, newH * aspect)
                                                newX = right - newW
                                            }
                                        }
                                        outputConfig.screens[idx].slices[selIdx].outputX = newX
                                        outputConfig.screens[idx].slices[selIdx].outputW = newW
                                        outputConfig.screens[idx].slices[selIdx].outputH = newH
                                    }
                                    .onEnded { _ in isDraggingCorner = false })
                        }

                        // === MESH MODE: draggable nodes at grid intersections ===
                        if editMode == .mesh {
                            meshNodeOverlay(idx: idx, ox: ox, oy: oy, canvasW: canvasW, canvasH: canvasH, handleSize: handleSize)
                        }
                    }
                }
                // Canvas-wide tap → select smallest slice containing the tap.
                // simultaneousGesture so it fires alongside the selected
                // slice's drag gesture (drag won't trigger on a no-movement
                // tap, but its presence used to swallow the touch).
                .simultaneousGesture(
                    SpatialTapGesture(coordinateSpace: .local)
                        .onEnded { value in
                            // Don't change selection while editing mesh nodes
                            guard outputConfig.canvasEditMode == .transform else { return }
                            let normX = Float((value.location.x - ox) / canvasW)
                            let normY = Float((value.location.y - oy) / canvasH)
                            guard idx < outputConfig.screens.count else { return }
                            let slices = outputConfig.screens[idx].slices
                            var bestIdx: Int? = nil
                            var bestArea: Float = .greatestFiniteMagnitude
                            for (i, s) in slices.enumerated() {
                                if normX >= s.outputX && normX <= s.outputX + s.outputW &&
                                   normY >= s.outputY && normY <= s.outputY + s.outputH {
                                    let a = s.outputW * s.outputH
                                    if a < bestArea {
                                        bestArea = a
                                        bestIdx = i
                                    }
                                }
                            }
                            if let i = bestIdx {
                                outputConfig.selectedSliceIndex = i
                                outputConfig.selectedNodeIndex = nil
                            }
                        }
                )
                // Canvas zoom — pinch to scale the whole edit area. Drag
                // gestures inside still operate in unscaled coords (SwiftUI
                // scaleEffect leaves gesture coord space alone), so slice
                // moves at the right speed even at 4× zoom.
                .scaleEffect(canvasZoom, anchor: .center)
                .gesture(MagnifyGesture()
                    .onChanged { value in
                        canvasZoom = max(0.5, min(4.0, pinchBaseZoom * value.magnification))
                    }
                    .onEnded { _ in
                        pinchBaseZoom = canvasZoom
                    }
                )
            }
        }
        .padding(scaled(6, sc))
        .clipped()
    }

    // MARK: - Mesh Node Overlay (safe bounds-checked)

    @ViewBuilder
    private func meshNodeOverlay(idx: Int, ox: CGFloat, oy: CGFloat, canvasW: CGFloat, canvasH: CGFloat, handleSize: CGFloat) -> some View {
        let si = outputConfig.selectedScreenIndex
        let sli = outputConfig.selectedSliceIndex
        if si < outputConfig.screens.count,
           sli < outputConfig.screens[si].slices.count {
            let slice = outputConfig.screens[si].slices[sli]
            if slice.meshWarpEnabled && !slice.meshWarp.nodes.isEmpty {
                let sliceX = ox + CGFloat(slice.outputX) * canvasW
                let sliceY = oy + CGFloat(slice.outputY) * canvasH
                let sliceW = CGFloat(slice.outputW) * canvasW
                let sliceH = CGFloat(slice.outputH) * canvasH
                let count = slice.meshWarp.nodes.count

                // Hit zones are 44pt squares (Apple HIG min) regardless of the
                // visible dot — much easier to grab on iPad without making the
                // dots themselves obscure the canvas.
                let hitSize: CGFloat = 44
                // Iterate by stable WarpNode IDs (UUIDs) instead of by index
                // so SwiftUI doesn't recycle gesture state when subdivide
                // adds rows/cols and indices shift.
                ForEach(Array(slice.meshWarp.nodes.enumerated()), id: \.element.id) { ni, _ in
                    // Re-read live on every body evaluation
                    let liveSI = outputConfig.selectedScreenIndex
                    let liveSLI = outputConfig.selectedSliceIndex
                    if liveSI < outputConfig.screens.count,
                       liveSLI < outputConfig.screens[liveSI].slices.count,
                       ni < outputConfig.screens[liveSI].slices[liveSLI].meshWarp.nodes.count {
                        let n = outputConfig.screens[liveSI].slices[liveSLI].meshWarp.nodes[ni]
                        ZStack {
                            // Visible dot kept small so the canvas stays readable
                            Circle()
                                .fill(outputConfig.selectedNodeIndex == ni ? R : Color.white)
                                .frame(width: handleSize, height: handleSize)
                        }
                        .frame(width: hitSize, height: hitSize)
                        .contentShape(Rectangle())
                        .position(x: sliceX + CGFloat(n.x) * sliceW,
                                  y: sliceY + CGFloat(n.y) * sliceH)
                        .gesture(DragGesture(minimumDistance: 1)
                            .onChanged { drag in
                                let s = outputConfig.selectedScreenIndex
                                let sl = outputConfig.selectedSliceIndex
                                guard s < outputConfig.screens.count,
                                      sl < outputConfig.screens[s].slices.count,
                                      ni < outputConfig.screens[s].slices[sl].meshWarp.nodes.count else { return }
                                outputConfig.selectedNodeIndex = ni
                                let newX = Float((drag.location.x - sliceX) / sliceW)
                                let newY = Float((drag.location.y - sliceY) / sliceH)
                                outputConfig.screens[s].slices[sl].meshWarp.nodes[ni].x = max(0, min(1, newX))
                                outputConfig.screens[s].slices[sl].meshWarp.nodes[ni].y = max(0, min(1, newY))
                            })
                    }
                }
            }
        }
    }

    // MARK: - Canvas Helpers

    private func cornerHandle(x: CGFloat, y: CGFloat, size: CGFloat, filled: Bool) -> some View {
        // Hit zone padded out to 44pt; the dot stays at `size` for visual
        // clarity. Without this the corner pins were hard to grab on iPad.
        let hitSize: CGFloat = 44
        return ZStack {
            if filled {
                Circle().fill(R).frame(width: size, height: size)
            } else {
                Circle().stroke(R, lineWidth: 2).frame(width: size, height: size)
            }
        }
        .frame(width: hitSize, height: hitSize)
        .contentShape(Rectangle())
        .position(x: x, y: y)
    }

    private func meshGridLines(slice: OutputSlice, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, color: Color) -> some View {
        ForEach(Array(slice.meshWarp.nodes.enumerated()), id: \.element.id) { ni, node in
            let nx = x + CGFloat(node.x) * w
            let ny = y + CGFloat(node.y) * h
            if ni < slice.meshWarp.nodes.count {
                let c = ni % (slice.meshWarp.cols + 1)
                let r = ni / (slice.meshWarp.cols + 1)
                if c < slice.meshWarp.cols {
                    let nextIdx = r * (slice.meshWarp.cols + 1) + c + 1
                    if nextIdx < slice.meshWarp.nodes.count {
                        Path { p in p.move(to: CGPoint(x: nx, y: ny)); p.addLine(to: CGPoint(x: x + CGFloat(slice.meshWarp.nodes[nextIdx].x) * w, y: y + CGFloat(slice.meshWarp.nodes[nextIdx].y) * h)) }
                            .stroke(color, lineWidth: 2)
                    }
                }
                if r < slice.meshWarp.rows {
                    let belowIdx = (r + 1) * (slice.meshWarp.cols + 1) + c
                    if belowIdx < slice.meshWarp.nodes.count {
                        Path { p in p.move(to: CGPoint(x: nx, y: ny)); p.addLine(to: CGPoint(x: x + CGFloat(slice.meshWarp.nodes[belowIdx].x) * w, y: y + CGFloat(slice.meshWarp.nodes[belowIdx].y) * h)) }
                            .stroke(color, lineWidth: 2)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Screen Tabs

    private func screenTabs(_ sc: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: scaled(3, sc)) {
            sectionHeader("SCREEN", sc)
            HStack(spacing: scaled(2, sc)) {
                ForEach(Array(outputConfig.screens.enumerated()), id: \.element.id) { i, screen in
                    let sel = outputConfig.selectedScreenIndex == i
                    Button {
                        outputConfig.selectedScreenIndex = i
                        outputConfig.selectedSliceIndex = 0
                    } label: {
                        Text(screen.name)
                            .font(.system(size: sf(11, sc), weight: .black, design: .monospaced))
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .foregroundColor(sel ? .white : .gray)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, scaled(7, sc))
                            .background(sel ? R.opacity(0.3) : Color.white.opacity(0.03))
                            .overlay(VStack { Rectangle().fill(sel ? R : Color.clear).frame(height: scaled(2, sc)); Spacer() })
                    }
                    .buttonStyle(TactileButtonStyle())
                }
                Button { outputConfig.addScreen() } label: {
                    Image(systemName: "plus").font(.system(size: sf(12, sc), weight: .bold)).foregroundColor(R)
                        .padding(scaled(6, sc))
                }
            }

            // Resolution inline
            let idx = outputConfig.selectedScreenIndex
            if idx < outputConfig.screens.count {
                HStack(spacing: scaled(4, sc)) {
                    // Clamp screen dimensions to a sane range so a typo of 0
                    // or 100000 can't reach the GPU texture allocator.
                    numFieldInt("W", Binding(
                        get: { outputConfig.screens[idx].width },
                        set: { outputConfig.screens[idx].width = max(64, min(4096, $0)) }
                    ), sc)
                    numFieldInt("H", Binding(
                        get: { outputConfig.screens[idx].height },
                        set: { outputConfig.screens[idx].height = max(64, min(4096, $0)) }
                    ), sc)
                }
            }
        }
    }

    // MARK: - Destination Picker

    private func destinationPicker(_ sc: CGFloat) -> some View {
        let idx = outputConfig.selectedScreenIndex
        guard idx < outputConfig.screens.count else { return AnyView(EmptyView()) }

        return AnyView(VStack(alignment: .leading, spacing: 6) {
            sectionHeader("DESTINATION", sc)
            HStack(spacing: 3) {
                ForEach(OutputDestination.allCases) { dest in
                    let sel = outputConfig.screens[idx].destination == dest
                    Button {
                        outputConfig.screens[idx].destination = dest
                        if dest == .ndi { outputConfig.screens[idx].ndiOutputEnabled = true }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: dest.icon).font(.system(size: 18, weight: .semibold))
                            Text(dest.displayName).font(.system(size: 11, weight: .heavy, design: .monospaced))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .foregroundColor(sel ? .white : .gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(sel ? R.opacity(0.3) : Color.white.opacity(0.04))
                        .overlay(VStack { Rectangle().fill(sel ? R : Color.clear).frame(height: 2); Spacer() })
                    }
                    .buttonStyle(TactileButtonStyle())
                }
            }

            // Display controls (only when display/fullscreen selected)
            let dest = outputConfig.screens[idx].destination
            if dest == .display || dest == .fullscreen {
                displayOutputControls(sc, screenIndex: idx)
            }
        })
    }

    private func displayOutputControls(_ sc: CGFloat, screenIndex idx: Int) -> some View {
        VStack(alignment: .leading, spacing: scaled(3, sc)) {
            let displays = renderEngine.displayManager.allDisplays
            if displays.isEmpty {
                HStack(spacing: scaled(3, sc)) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: sf(8, sc))).foregroundColor(.yellow)
                    Text("No displays").font(.system(size: sf(7, sc), weight: .heavy, design: .monospaced)).foregroundColor(.yellow.opacity(0.8))
                }
            } else {
                ForEach(displays) { display in
                    let isSelected = outputConfig.screens[idx].displayID == display.id
                    let isActive = isSelected && outputConfig.screens[idx].enabled
                    Button {
                        if isSelected {
                            outputConfig.screens[idx].enabled.toggle()
                            if outputConfig.screens[idx].enabled {
                                pushToDisplay(screenIndex: idx, isExternal: !display.isMain)
                            } else {
                                // Close whichever output is up — external
                                // window OR the in-window liveOutput scene.
                                ExternalDisplayController.shared.hide()
                                dismissWindow(id: "liveOutput")
                            }
                        } else {
                            outputConfig.screens[idx].displayID = display.id
                            outputConfig.screens[idx].width = 1920
                            outputConfig.screens[idx].height = 1080
                            outputConfig.screens[idx].enabled = true
                            pushToDisplay(screenIndex: idx, isExternal: !display.isMain)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Circle().fill(isActive ? Color.green : Color.gray.opacity(0.4)).frame(width: 10, height: 10)
                            Image(systemName: display.isMain ? "macbook" : "display").font(.system(size: 16, weight: .semibold))
                            Text(display.name).font(.system(size: 12, weight: .heavy, design: .monospaced))
                                .lineLimit(1).minimumScaleFactor(0.7)
                            Spacer()
                            if isSelected {
                                Text(isActive ? "ON" : "OFF").font(.system(size: 11, weight: .black, design: .monospaced))
                                    .foregroundColor(isActive ? .green : .gray)
                            }
                        }
                        .foregroundColor(isSelected ? .white : .gray)
                        .padding(.horizontal, 10).padding(.vertical, 10)
                        .background(isActive ? R.opacity(0.18) : Color.white.opacity(0.04))
                        .overlay(Rectangle().stroke(isActive ? R.opacity(0.5) : Color.white.opacity(0.10), lineWidth: 0.5))
                    }.buttonStyle(TactileButtonStyle())
                }
            }

            // OPEN/REFRESH removed — tapping a display row toggles its
            // active state, and `UIScreen.didConnectNotification` already
            // refreshes the list automatically when displays are plugged in.
        }
    }

    /// Route the live output to either the external display (auto-fullscreen
    /// via `ExternalDisplayController` UIWindow) or, as a fallback, an
    /// in-window WindowGroup scene on the iPad's main display.
    private func pushToDisplay(screenIndex: Int, isExternal: Bool) {
        if isExternal && ExternalDisplayController.shared.hasExternalDisplay {
            ExternalDisplayController.shared.show(renderEngine: renderEngine, screenIndex: screenIndex)
        } else {
            ExternalDisplayController.shared.hide()
            openSingleWindow(id: "liveOutput")
        }
    }

    // MARK: - Slice List

    private func sliceList(_ sc: CGFloat) -> some View {
        let idx = outputConfig.selectedScreenIndex
        guard idx < outputConfig.screens.count else { return AnyView(EmptyView()) }
        return AnyView(VStack(alignment: .leading, spacing: scaled(3, sc)) {
            HStack {
                sectionHeader("SLICES", sc)
                Spacer()
                Button { outputConfig.addSlice(to: idx) } label: {
                    HStack(spacing: scaled(2, sc)) {
                        Image(systemName: "plus").font(.system(size: sf(8, sc), weight: .bold))
                        Text("ADD").font(.system(size: sf(6, sc), weight: .black, design: .monospaced))
                    }
                    .foregroundColor(R)
                    .padding(.horizontal, scaled(6, sc)).padding(.vertical, scaled(3, sc))
                    .background(R.opacity(0.1))
                }.buttonStyle(TactileButtonStyle())
            }

            ForEach(Array(outputConfig.screens[idx].slices.enumerated()), id: \.element.id) { si, slice in
                let isSel = outputConfig.selectedSliceIndex == si
                let hasMesh = slice.meshWarpEnabled && !slice.meshWarp.nodes.isEmpty

                Button {
                    outputConfig.selectedSliceIndex = si
                    outputConfig.selectedNodeIndex = nil
                    // If in mesh mode, auto-enable mesh on the newly selected slice
                    if outputConfig.canvasEditMode == .mesh {
                        let scrIdx = outputConfig.selectedScreenIndex
                        if scrIdx < outputConfig.screens.count, si < outputConfig.screens[scrIdx].slices.count {
                            outputConfig.screens[scrIdx].slices[si].meshWarpEnabled = true
                            if outputConfig.screens[scrIdx].slices[si].meshWarp.nodes.isEmpty {
                                outputConfig.screens[scrIdx].slices[si].meshWarp.generateGrid()
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        // Color bar
                        Rectangle().fill(isSel ? R : .gray.opacity(0.4))
                            .frame(width: 4)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(slice.name)
                                .font(.system(size: 12, weight: .black, design: .monospaced))
                                .foregroundColor(isSel ? .white : .gray)
                                .lineLimit(1).minimumScaleFactor(0.6)
                            HStack(spacing: 5) {
                                Text(slice.sourceType.displayName.uppercased())
                                    .font(.system(size: 9, weight: .black, design: .monospaced))
                                    .foregroundColor(R)
                                    .lineLimit(1).minimumScaleFactor(0.6).fixedSize()
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(R.opacity(0.18))
                                if hasMesh {
                                    Text("MESH \(slice.meshWarp.cols)x\(slice.meshWarp.rows)")
                                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                        .foregroundColor(R.opacity(0.5))
                                        .lineLimit(1).fixedSize()
                                }
                                Text(String(format: "%.0f%%x%.0f%%", slice.outputW * 100, slice.outputH * 100))
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundColor(.gray.opacity(0.6))
                                    .lineLimit(1).fixedSize()
                            }
                        }

                        Spacer()

                        Menu {
                            ForEach(SliceSource.allCases) { src in
                                Button {
                                    outputConfig.screens[idx].slices[si].sourceType = src
                                    Haptics.tap()
                                } label: {
                                    Label(src.displayName, systemImage: slice.sourceType == src ? "checkmark" : "")
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.triangle.swap")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(R.opacity(0.85))
                                .padding(6)
                        }

                        Circle()
                            .fill(slice.enabled ? Color.green.opacity(0.7) : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)

                        if outputConfig.screens[idx].slices.count > 1 {
                            Button {
                                outputConfig.removeSlice(screenIndex: idx, sliceIndex: si)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: sf(7, sc), weight: .bold))
                                    .foregroundColor(.gray.opacity(0.5))
                            }
                        }
                    }
                    .padding(.vertical, 9)
                    .padding(.horizontal, 8)
                    .background(isSel ? R.opacity(0.14) : Color.white.opacity(0.04))
                    .overlay(
                        Rectangle().stroke(isSel ? R.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
        })
    }

    // MARK: - Slice Binding

    private var selectedSliceBinding: Binding<OutputSlice>? {
        let si = outputConfig.selectedScreenIndex
        let sli = outputConfig.selectedSliceIndex
        guard si < outputConfig.screens.count, sli < outputConfig.screens[si].slices.count else { return nil }
        return Binding(
            get: {
                let s = outputConfig.selectedScreenIndex
                let sl = outputConfig.selectedSliceIndex
                guard s < outputConfig.screens.count, sl < outputConfig.screens[s].slices.count else {
                    return OutputSlice()
                }
                return outputConfig.screens[s].slices[sl]
            },
            set: {
                let s = outputConfig.selectedScreenIndex
                let sl = outputConfig.selectedSliceIndex
                guard s < outputConfig.screens.count, sl < outputConfig.screens[s].slices.count else { return }
                outputConfig.screens[s].slices[sl] = $0
            }
        )
    }

    // MARK: - Transform Section (Resolume-style)

    private func transformSection(_ slice: Binding<OutputSlice>, _ sc: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: scaled(4, sc)) {
            sectionHeader("TRANSFORM", sc)

            // X/Y allowed to go past the canvas edges so slices can extend
            // out of bounds (Resolume-style overscan).
            HStack(spacing: scaled(6, sc)) {
                numField("X", slice.outputX, sc, range: -1...2, step: 0.01)
                numField("Y", slice.outputY, sc, range: -1...2, step: 0.01)
            }
            HStack(spacing: scaled(6, sc)) {
                numField("W", slice.outputW, sc, range: 0.01...3, step: 0.01)
                numField("H", slice.outputH, sc, range: 0.01...3, step: 0.01)
            }
            HStack(spacing: scaled(6, sc)) {
                numField("ROT", slice.rotation, sc, range: -360...360, step: 1, fmt: "%.0f°")
                numField("BRI", slice.brightness, sc, range: -1...1, step: 0.05)
                numField("CON", slice.contrast, sc, range: 0...2, step: 0.05)
            }
        }
    }

    // MARK: - Input Section

    private func inputSection(_ slice: Binding<OutputSlice>, _ sc: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: scaled(4, sc)) {
            sectionHeader("INPUT", sc)

            // Source picker — Program (the mix) or any single channel.
            VStack(alignment: .leading, spacing: 3) {
                Text("SOURCE")
                    .font(.system(size: sf(7, sc), weight: .heavy, design: .monospaced))
                    .foregroundColor(.gray)
                let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: cols, spacing: 3) {
                    ForEach(SliceSource.allCases) { src in
                        Button {
                            slice.wrappedValue.sourceType = src
                        } label: {
                            Text(src.displayName)
                                .font(.system(size: sf(8, sc), weight: .black, design: .monospaced))
                                .lineLimit(1).minimumScaleFactor(0.7)
                                .foregroundColor(slice.wrappedValue.sourceType == src ? .white : .gray)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, scaled(4, sc))
                                .background(slice.wrappedValue.sourceType == src ? R.opacity(0.35) : Color.white.opacity(0.05))
                                .overlay(Rectangle().stroke(slice.wrappedValue.sourceType == src ? R : Color.white.opacity(0.08), lineWidth: 0.5))
                        }
                        .buttonStyle(TactileButtonStyle())
                    }
                }
            }
        }
    }

    // MARK: - Warp Section (Corner Pin)

    private func warpSection(_ slice: Binding<OutputSlice>, _ sc: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: scaled(4, sc)) {
            HStack {
                sectionHeader("PERSPECTIVE WARP", sc)
                Spacer()
                Button {
                    slice.wrappedValue.warpTL = .topLeft; slice.wrappedValue.warpTR = .topRight
                    slice.wrappedValue.warpBL = .bottomLeft; slice.wrappedValue.warpBR = .bottomRight
                } label: {
                    Text("RESET").font(.system(size: sf(7, sc), weight: .black, design: .monospaced)).foregroundColor(.gray)
                }
            }

            HStack(spacing: scaled(8, sc)) {
                VStack(spacing: scaled(2, sc)) {
                    sublabel("TL", sc)
                    numField("X", slice.warpTL.x, sc, range: -0.5...1.5, step: 0.01)
                    numField("Y", slice.warpTL.y, sc, range: -0.5...1.5, step: 0.01)
                }
                VStack(spacing: scaled(2, sc)) {
                    sublabel("TR", sc)
                    numField("X", slice.warpTR.x, sc, range: -0.5...1.5, step: 0.01)
                    numField("Y", slice.warpTR.y, sc, range: -0.5...1.5, step: 0.01)
                }
            }
            HStack(spacing: scaled(8, sc)) {
                VStack(spacing: scaled(2, sc)) {
                    sublabel("BL", sc)
                    numField("X", slice.warpBL.x, sc, range: -0.5...1.5, step: 0.01)
                    numField("Y", slice.warpBL.y, sc, range: -0.5...1.5, step: 0.01)
                }
                VStack(spacing: scaled(2, sc)) {
                    sublabel("BR", sc)
                    numField("X", slice.warpBR.x, sc, range: -0.5...1.5, step: 0.01)
                    numField("Y", slice.warpBR.y, sc, range: -0.5...1.5, step: 0.01)
                }
            }
        }
    }

    // MARK: - Blend Section

    private func blendSection(_ slice: Binding<OutputSlice>, _ sc: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: scaled(4, sc)) {
            HStack {
                sectionHeader("SOFT EDGE", sc)
                Spacer()
                Button {
                    slice.wrappedValue.resetBlend()
                } label: {
                    Text("RESET").font(.system(size: sf(7, sc), weight: .black, design: .monospaced)).foregroundColor(.gray)
                }
            }
            HStack(spacing: scaled(6, sc)) {
                numField("L", slice.blendLeft, sc, range: 0...0.5, step: 0.01)
                numField("R", slice.blendRight, sc, range: 0...0.5, step: 0.01)
                numField("T", slice.blendTop, sc, range: 0...0.5, step: 0.01)
                numField("B", slice.blendBottom, sc, range: 0...0.5, step: 0.01)
            }
            numField("GAMMA", slice.blendGamma, sc, range: 0.5...4.0, step: 0.1)
        }
    }

    // MARK: - Mesh Warp Section

    private func meshWarpSection(_ slice: Binding<OutputSlice>, _ sc: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: scaled(4, sc)) {
            HStack {
                sectionHeader("MESH WARP — \(slice.wrappedValue.name.uppercased())", sc)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { slice.wrappedValue.meshWarpEnabled },
                    set: { val in
                        slice.wrappedValue.meshWarpEnabled = val
                        if val && slice.wrappedValue.meshWarp.nodes.isEmpty {
                            slice.wrappedValue.meshWarp.generateGrid()
                        }
                    }
                )).labelsHidden().tint(R).scaleEffect(0.8)
            }

            if slice.wrappedValue.meshWarpEnabled {
                HStack(spacing: scaled(4, sc)) {
                    Text("GRID: \(slice.wrappedValue.meshWarp.cols)x\(slice.wrappedValue.meshWarp.rows)")
                        .font(.system(size: sf(8, sc), weight: .heavy, design: .monospaced)).foregroundColor(.gray)
                    Button {
                        let si = outputConfig.selectedScreenIndex
                        let sli = outputConfig.selectedSliceIndex
                        if si < outputConfig.screens.count, sli < outputConfig.screens[si].slices.count {
                            outputConfig.screens[si].slices[sli].meshWarp.subdivide()
                        }
                    } label: {
                        Text("ADD").font(.system(size: sf(7, sc), weight: .black, design: .monospaced))
                            .foregroundColor(R).padding(.horizontal, scaled(6, sc)).padding(.vertical, scaled(3, sc))
                            .background(R.opacity(0.1))
                    }.buttonStyle(TactileButtonStyle())
                    Button {
                        let si = outputConfig.selectedScreenIndex
                        let sli = outputConfig.selectedSliceIndex
                        if si < outputConfig.screens.count, sli < outputConfig.screens[si].slices.count {
                            outputConfig.screens[si].slices[sli].meshWarp.reset()
                        }
                    } label: {
                        Text("RESET").font(.system(size: sf(7, sc), weight: .black, design: .monospaced))
                            .foregroundColor(.gray).padding(.horizontal, scaled(6, sc)).padding(.vertical, scaled(3, sc))
                            .background(Color.white.opacity(0.03))
                    }.buttonStyle(TactileButtonStyle())
                }

                if let ni = outputConfig.selectedNodeIndex,
                   ni < slice.wrappedValue.meshWarp.nodes.count {
                    HStack(spacing: scaled(6, sc)) {
                        Text("NODE \(ni)").font(.system(size: sf(8, sc), weight: .heavy, design: .monospaced)).foregroundColor(R)
                        Text("X: \(String(format: "%.3f", slice.wrappedValue.meshWarp.nodes[ni].x))")
                            .font(.system(size: sf(8, sc), weight: .bold, design: .monospaced)).foregroundColor(.white.opacity(0.7))
                        Text("Y: \(String(format: "%.3f", slice.wrappedValue.meshWarp.nodes[ni].y))")
                            .font(.system(size: sf(8, sc), weight: .bold, design: .monospaced)).foregroundColor(.white.opacity(0.7))
                    }
                }
            }
        }
    }

    // MARK: - NDI

    private func ndiSection(_ sc: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: scaled(4, sc)) {
            sectionHeader("NDI OUTPUT", sc)
            Toggle("Program NDI", isOn: Binding(
                get: { outputConfig.globalNDIOutput },
                set: { outputConfig.globalNDIOutput = $0 }
            )).font(.system(size: sf(9, sc), weight: .heavy, design: .monospaced)).tint(R)

            let idx = outputConfig.selectedScreenIndex
            if idx < outputConfig.screens.count && outputConfig.screens[idx].destination == .ndi {
                HStack(spacing: scaled(3, sc)) {
                    Text("NAME").font(.system(size: sf(8, sc), weight: .heavy, design: .monospaced)).foregroundColor(.gray)
                    TextField("", text: Binding(
                        get: { outputConfig.screens[idx].ndiOutputName },
                        set: { outputConfig.screens[idx].ndiOutputName = $0 }
                    )).font(.system(size: sf(9, sc), design: .monospaced)).textFieldStyle(.plain)
                }
            }
        }
    }

    // MARK: - Numeric Field Components

    /// Numeric field with label, stepper buttons, and direct text input
    private func numField(_ lbl: String, _ val: Binding<Float>, _ sc: CGFloat,
                          range: ClosedRange<Float> = 0...1, step: Float = 0.01, fmt: String = "%.3f") -> some View {
        HStack(spacing: 3) {
            Text(lbl)
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundColor(R.opacity(0.6))
                .frame(width: 24, alignment: .trailing)

            Button {
                val.wrappedValue = max(range.lowerBound, val.wrappedValue - step)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.gray)
                    .frame(width: 18, height: 18)
            }.buttonStyle(.plain)

            TextField("", value: val, format: .number.precision(.fractionLength(2)))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.05))
                .onChange(of: val.wrappedValue) { _, newVal in
                    val.wrappedValue = min(range.upperBound, max(range.lowerBound, newVal))
                }

            Button {
                val.wrappedValue = min(range.upperBound, val.wrappedValue + step)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.gray)
                    .frame(width: 18, height: 18)
            }.buttonStyle(.plain)
        }
    }

    /// Integer numeric field
    private func numFieldInt(_ lbl: String, _ val: Binding<Int>, _ sc: CGFloat) -> some View {
        HStack(spacing: scaled(2, sc)) {
            Text(lbl)
                .font(.system(size: sf(7, sc), weight: .heavy, design: .monospaced))
                .foregroundColor(R.opacity(0.6))
                .frame(width: scaled(16, sc), alignment: .trailing)
            TextField("", value: val, format: .number)
                .font(.system(size: sf(10, sc), weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .frame(width: scaled(50, sc))
                .padding(.vertical, scaled(2, sc))
                .background(Color.white.opacity(0.04))
        }
    }

    // MARK: - NDI Send Controls

    private func ndiSendButton(_ sc: CGFloat) -> some View {
        let anyNDI = outputConfig.globalNDIOutput || outputConfig.screens.contains { $0.ndiOutputEnabled }
        return Button { showNDIPopover.toggle() } label: {
            HStack(spacing: scaled(3, sc)) {
                Circle()
                    .fill(anyNDI ? Color.green : Color.gray.opacity(0.4))
                    .frame(width: scaled(6, sc), height: scaled(6, sc))
                Image(systemName: "network").font(.system(size: sf(9, sc), weight: .bold))
                Text("NDI").font(.system(size: sf(7, sc), weight: .black, design: .monospaced))
            }
            .foregroundColor(anyNDI ? .green : .gray)
            .padding(.horizontal, scaled(6, sc)).padding(.vertical, scaled(3, sc))
            .background(anyNDI ? Color.green.opacity(0.15) : Color.white.opacity(0.03))
        }
        .buttonStyle(TactileButtonStyle())
        .popover(isPresented: $showNDIPopover) {
            ndiSendPopover()
        }
    }

    private func ndiSendPopover() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("NDI SENDS")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(R)
                Spacer()
            }

            Rectangle().fill(R.opacity(0.2)).frame(height: 1)

            // Global program NDI
            HStack(spacing: 6) {
                Toggle("", isOn: Binding(
                    get: { outputConfig.globalNDIOutput },
                    set: { outputConfig.globalNDIOutput = $0 }
                )).labelsHidden().tint(.green).scaleEffect(1.0)

                VStack(alignment: .leading, spacing: 2) {
                    Text("PROGRAM")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(outputConfig.globalNDIOutput ? .white : .gray)
                    TextField("Name", text: Binding(
                        get: { outputConfig.globalNDIName },
                        set: { outputConfig.globalNDIName = $0 }
                    ))
                    .font(.system(size: 9, design: .monospaced))
                    .textFieldStyle(.plain)
                    .padding(3)
                    .background(Color.white.opacity(0.05))
                }
            }
            .padding(.vertical, 2)

            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)

            // Per-screen NDI sends
            Text("SCREEN SENDS")
                .font(.system(size: 7, weight: .heavy, design: .monospaced))
                .foregroundColor(.gray)

            ForEach(Array(outputConfig.screens.enumerated()), id: \.element.id) { i, screen in
                HStack(spacing: 6) {
                    Toggle("", isOn: Binding(
                        get: { outputConfig.screens[i].ndiOutputEnabled },
                        set: {
                            outputConfig.screens[i].ndiOutputEnabled = $0
                            if $0 { outputConfig.screens[i].destination = .ndi }
                        }
                    )).labelsHidden().tint(.green).scaleEffect(1.0)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(screen.name)
                            .font(.system(size: 8, weight: .heavy, design: .monospaced))
                            .foregroundColor(screen.ndiOutputEnabled ? .white : .gray)
                        TextField("NDI Name", text: Binding(
                            get: { outputConfig.screens[i].ndiOutputName },
                            set: { outputConfig.screens[i].ndiOutputName = $0 }
                        ))
                        .font(.system(size: 8, design: .monospaced))
                        .textFieldStyle(.plain)
                        .padding(2)
                        .background(Color.white.opacity(0.05))
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(12)
        .frame(width: 250)
        .background(Color(red: 0.08, green: 0.08, blue: 0.09))
    }

    // MARK: - Single Window Helper

    private func openSingleWindow(id: String) {
        for scene in UIApplication.shared.connectedScenes {
            if let ws = scene as? UIWindowScene {
                let activity = ws.session.stateRestorationActivity?.activityType ?? ""
                if activity.contains(id) {
                    ws.windows.first?.makeKeyAndVisible()
                    return
                }
            }
        }
        openWindow(id: id)
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String, _ sc: CGFloat) -> some View {
        HStack(spacing: 5) {
            Rectangle().fill(R).frame(width: 3, height: 14)
            Text(text).font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundColor(R.opacity(0.9)).tracking(0.8)
        }
    }

    private func sublabel(_ text: String, _ sc: CGFloat) -> some View {
        Text(text).font(.system(size: sf(7, sc), weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5))
    }
}
