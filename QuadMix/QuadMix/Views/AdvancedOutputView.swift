import SwiftUI

private let R = Color(red: 1.0, green: 0.15, blue: 0.15)

/// Advanced Output — Resolume-style canvas + controls.
struct AdvancedOutputView: View {
    let outputConfig: OutputConfig
    let renderEngine: RenderEngine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let panelScale = min(1.3, max(0.65, w / 550.0))
            // sc passed to functions but we use scaleEffect for uniform scaling
            let sc: CGFloat = 1.0

            VStack(spacing: 0) {
                // Top bar — always full size
                HStack(spacing: 6) {
                    Rectangle().fill(R).frame(width: 2, height: 10)
                    Text("ADV OUT")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(.white)

                    canvasModeBarInline(sc)

                    Spacer()

                    ndiSendButton(sc)
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color(red: 0.05, green: 0.05, blue: 0.06))

                // Main content
                HStack(spacing: 0) {
                    // Canvas — fills remaining space
                    outputCanvas(sc, size: geo.size)
                        .frame(maxWidth: .infinity)

                    Rectangle().fill(R.opacity(0.1)).frame(width: 1)

                    // Right panel — liquid scaled like main mixer
                    let panelW = min(max(w * 0.35, 180), 280)
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 12) {
                            screenTabs(sc)
                            destinationPicker(sc)
                            sliceList(sc)
                            if let slice = selectedSliceBinding {
                                transformSection(slice, sc)
                                inputSection(slice, sc)
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
                )).labelsHidden().tint(R).scaleEffect(0.7)
            }
        }
        .padding(.horizontal, scaled(8, sc)).padding(.vertical, scaled(4, sc))
        .background(Color(red: 0.05, green: 0.05, blue: 0.06))
    }

    // MARK: - Inline Mode Controls (embedded in top bar)

    @ViewBuilder
    private func canvasModeBarInline(_ sc: CGFloat) -> some View {
        HStack(spacing: 3) {
            modeButton("arrow.up.left.and.arrow.down.right", "TFM", .transform, sc)
            modeButton("circle.grid.3x3", "MESH", .mesh, sc)

            if outputConfig.canvasEditMode == .mesh {
                Button {
                    let si = outputConfig.selectedScreenIndex
                    let sli = outputConfig.selectedSliceIndex
                    if si < outputConfig.screens.count, sli < outputConfig.screens[si].slices.count {
                        outputConfig.screens[si].slices[sli].meshWarpEnabled = true
                        outputConfig.screens[si].slices[sli].meshWarp.subdivide()
                    }
                } label: {
                    Text("+").font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(R)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(R.opacity(0.15))
                }.buttonStyle(TactileButtonStyle())

                Button {
                    let si = outputConfig.selectedScreenIndex
                    let sli = outputConfig.selectedSliceIndex
                    if si < outputConfig.screens.count, sli < outputConfig.screens[si].slices.count {
                        outputConfig.screens[si].slices[sli].meshWarp.reset()
                    }
                } label: {
                    Text("RST").font(.system(size: 6, weight: .black, design: .monospaced))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(Color.white.opacity(0.05))
                }.buttonStyle(TactileButtonStyle())
            }
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
            // Auto-enable mesh warp on the selected slice when entering mesh mode
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
        } label: {
            HStack(spacing: scaled(3, sc)) {
                Image(systemName: icon)
                    .font(.system(size: sf(10, sc), weight: .bold))
                Text(label)
                    .font(.system(size: sf(7, sc), weight: .black, design: .monospaced))
            }
            .foregroundColor(isActive ? .white : .gray)
            .padding(.horizontal, scaled(8, sc))
            .padding(.vertical, scaled(4, sc))
            .background(isActive ? R.opacity(0.4) : Color.white.opacity(0.03))
            .overlay(
                Rectangle().stroke(isActive ? R : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(TactileButtonStyle())
    }

    // MARK: - Canvas

    @State private var dragStartX: Float = 0
    @State private var dragStartY: Float = 0
    @State private var showNDIPopover = false

    private func outputCanvas(_ sc: CGFloat, size: CGSize) -> some View {
        GeometryReader { geo in
            let idx = outputConfig.selectedScreenIndex
            if idx < outputConfig.screens.count {
                let screen = outputConfig.screens[idx]
                let aspect = CGFloat(screen.width) / CGFloat(screen.height)
                let canvasW = min(geo.size.width - 20, (geo.size.height - 20) * aspect)
                let canvasH = canvasW / aspect
                let ox = (geo.size.width - canvasW) / 2
                let oy = (geo.size.height - canvasH) / 2
                let handleSize = scaled(12, sc)

                ZStack {
                    Color(red: 0.06, green: 0.06, blue: 0.07)

                    // Program preview (non-interactive)
                    if let tex = renderEngine.outputRenderer.getScreenTexture(for: screen) {
                        PreviewView(device: MetalContext.shared.device, textureProvider: { tex })
                            .aspectRatio(aspect, contentMode: .fit)
                            .allowsHitTesting(false)
                    }

                    // Layer 1: Slice borders (non-selected) — tap to select (disabled in mesh mode)
                    ForEach(Array(screen.slices.enumerated()), id: \.element.id) { si, slice in
                        if outputConfig.selectedSliceIndex != si {
                            let x = ox + CGFloat(slice.outputX) * canvasW
                            let y = oy + CGFloat(slice.outputY) * canvasH
                            let w = CGFloat(slice.outputW) * canvasW
                            let h = CGFloat(slice.outputH) * canvasH
                            Rectangle()
                                .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                                .frame(width: w, height: h)
                                .position(x: x + w/2, y: y + h/2)
                                .contentShape(Rectangle())
                                .allowsHitTesting(outputConfig.canvasEditMode != .mesh)
                                .onTapGesture {
                                    outputConfig.selectedSliceIndex = si
                                    outputConfig.selectedNodeIndex = nil
                                    if outputConfig.canvasEditMode == .mesh {
                                        if idx < outputConfig.screens.count, si < outputConfig.screens[idx].slices.count {
                                            outputConfig.screens[idx].slices[si].meshWarpEnabled = true
                                            if outputConfig.screens[idx].slices[si].meshWarp.nodes.isEmpty {
                                                outputConfig.screens[idx].slices[si].meshWarp.generateGrid()
                                            }
                                        }
                                    }
                                }

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
                        if editMode == .transform {
                            Rectangle()
                                .fill(Color.white.opacity(0.001))
                                .frame(width: w, height: h)
                                .position(x: x + w/2, y: y + h/2)
                                .gesture(DragGesture()
                                    .onChanged { drag in
                                        if abs(drag.translation.width) < 2 && abs(drag.translation.height) < 2 {
                                            dragStartX = outputConfig.screens[idx].slices[selIdx].outputX
                                            dragStartY = outputConfig.screens[idx].slices[selIdx].outputY
                                        }
                                        let curW = outputConfig.screens[idx].slices[selIdx].outputW
                                        let curH = outputConfig.screens[idx].slices[selIdx].outputH
                                        let dx = Float(drag.translation.width / canvasW)
                                        let dy = Float(drag.translation.height / canvasH)
                                        outputConfig.screens[idx].slices[selIdx].outputX = max(0, min(1 - curW, dragStartX + dx))
                                        outputConfig.screens[idx].slices[selIdx].outputY = max(0, min(1 - curH, dragStartY + dy))
                                    }
                                    .onEnded { _ in
                                        dragStartX = outputConfig.screens[idx].slices[selIdx].outputX
                                        dragStartY = outputConfig.screens[idx].slices[selIdx].outputY
                                    })

                            cornerHandle(x: x, y: y, size: handleSize, filled: true)
                                .highPriorityGesture(DragGesture()
                                    .onChanged { drag in
                                        let newX = Float((drag.location.x - ox) / canvasW)
                                        let newY = Float((drag.location.y - oy) / canvasH)
                                        let right = outputConfig.screens[idx].slices[selIdx].outputX + outputConfig.screens[idx].slices[selIdx].outputW
                                        let bottom = outputConfig.screens[idx].slices[selIdx].outputY + outputConfig.screens[idx].slices[selIdx].outputH
                                        let cx = max(0, min(right - 0.05, newX))
                                        let cy = max(0, min(bottom - 0.05, newY))
                                        outputConfig.screens[idx].slices[selIdx].outputX = cx
                                        outputConfig.screens[idx].slices[selIdx].outputY = cy
                                        outputConfig.screens[idx].slices[selIdx].outputW = right - cx
                                        outputConfig.screens[idx].slices[selIdx].outputH = bottom - cy
                                    })

                            cornerHandle(x: x + w, y: y + h, size: handleSize, filled: true)
                                .highPriorityGesture(DragGesture()
                                    .onChanged { drag in
                                        let curX = outputConfig.screens[idx].slices[selIdx].outputX
                                        let curY = outputConfig.screens[idx].slices[selIdx].outputY
                                        outputConfig.screens[idx].slices[selIdx].outputW = max(0.05, min(1 - curX, Float((drag.location.x - x) / canvasW)))
                                        outputConfig.screens[idx].slices[selIdx].outputH = max(0.05, min(1 - curY, Float((drag.location.y - y) / canvasH)))
                                    })

                            cornerHandle(x: x + w, y: y, size: handleSize, filled: false)
                                .highPriorityGesture(DragGesture()
                                    .onChanged { drag in
                                        let curX = outputConfig.screens[idx].slices[selIdx].outputX
                                        let bottom = outputConfig.screens[idx].slices[selIdx].outputY + outputConfig.screens[idx].slices[selIdx].outputH
                                        let cy = max(0, min(bottom - 0.05, Float((drag.location.y - oy) / canvasH)))
                                        outputConfig.screens[idx].slices[selIdx].outputW = max(0.05, min(1 - curX, Float((drag.location.x - x) / canvasW)))
                                        outputConfig.screens[idx].slices[selIdx].outputY = cy
                                        outputConfig.screens[idx].slices[selIdx].outputH = bottom - cy
                                    })

                            cornerHandle(x: x, y: y + h, size: handleSize, filled: false)
                                .highPriorityGesture(DragGesture()
                                    .onChanged { drag in
                                        let right = outputConfig.screens[idx].slices[selIdx].outputX + outputConfig.screens[idx].slices[selIdx].outputW
                                        let curY = outputConfig.screens[idx].slices[selIdx].outputY
                                        let cx = max(0, min(right - 0.05, Float((drag.location.x - ox) / canvasW)))
                                        outputConfig.screens[idx].slices[selIdx].outputX = cx
                                        outputConfig.screens[idx].slices[selIdx].outputW = right - cx
                                        outputConfig.screens[idx].slices[selIdx].outputH = max(0.05, min(1 - curY, Float((drag.location.y - y) / canvasH)))
                                    })
                        }

                        // === MESH MODE: draggable nodes at grid intersections ===
                        if editMode == .mesh {
                            meshNodeOverlay(idx: idx, ox: ox, oy: oy, canvasW: canvasW, canvasH: canvasH, handleSize: handleSize)
                        }
                    }
                }
            }
        }
        .padding(scaled(6, sc))
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

                ForEach(0..<count, id: \.self) { ni in
                    // Re-read live on every body evaluation
                    let liveSI = outputConfig.selectedScreenIndex
                    let liveSLI = outputConfig.selectedSliceIndex
                    if liveSI < outputConfig.screens.count,
                       liveSLI < outputConfig.screens[liveSI].slices.count,
                       ni < outputConfig.screens[liveSI].slices[liveSLI].meshWarp.nodes.count {
                        let n = outputConfig.screens[liveSI].slices[liveSLI].meshWarp.nodes[ni]
                        Circle()
                            .fill(outputConfig.selectedNodeIndex == ni ? R : Color.white)
                            .frame(width: handleSize, height: handleSize)
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
        Group {
            if filled {
                Circle().fill(R).frame(width: size, height: size).position(x: x, y: y)
            } else {
                Circle().stroke(R, lineWidth: 2).frame(width: size, height: size).position(x: x, y: y)
            }
        }
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
                            .font(.system(size: sf(8, sc), weight: .black, design: .monospaced))
                            .foregroundColor(sel ? .white : .gray)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, scaled(3, sc))
                            .background(sel ? R.opacity(0.3) : Color.white.opacity(0.03))
                            .overlay(VStack { Rectangle().fill(sel ? R : Color.clear).frame(height: scaled(2, sc)); Spacer() })
                    }
                    .buttonStyle(TactileButtonStyle())
                }
                Button { outputConfig.addScreen() } label: {
                    Image(systemName: "plus").font(.system(size: sf(8, sc), weight: .bold)).foregroundColor(R)
                        .padding(scaled(3, sc))
                }
            }

            // Resolution inline
            let idx = outputConfig.selectedScreenIndex
            if idx < outputConfig.screens.count {
                HStack(spacing: scaled(4, sc)) {
                    numFieldInt("W", Binding(get: { outputConfig.screens[idx].width }, set: { outputConfig.screens[idx].width = $0 }), sc)
                    numFieldInt("H", Binding(get: { outputConfig.screens[idx].height }, set: { outputConfig.screens[idx].height = $0 }), sc)
                }
            }
        }
    }

    // MARK: - Destination Picker

    private func destinationPicker(_ sc: CGFloat) -> some View {
        let idx = outputConfig.selectedScreenIndex
        guard idx < outputConfig.screens.count else { return AnyView(EmptyView()) }

        return AnyView(VStack(alignment: .leading, spacing: scaled(3, sc)) {
            sectionHeader("DESTINATION", sc)
            // Uniform tab-style buttons — all same size
            HStack(spacing: scaled(2, sc)) {
                ForEach(OutputDestination.allCases) { dest in
                    let sel = outputConfig.screens[idx].destination == dest
                    Button {
                        outputConfig.screens[idx].destination = dest
                        if dest == .ndi { outputConfig.screens[idx].ndiOutputEnabled = true }
                    } label: {
                        VStack(spacing: scaled(1, sc)) {
                            Image(systemName: dest.icon).font(.system(size: sf(9, sc)))
                            Text(dest.displayName).font(.system(size: sf(6, sc), weight: .heavy, design: .monospaced))
                        }
                        .foregroundColor(sel ? .white : .gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, scaled(3, sc))
                        .background(sel ? R.opacity(0.3) : Color.white.opacity(0.03))
                        .overlay(VStack { Rectangle().fill(sel ? R : Color.clear).frame(height: scaled(2, sc)); Spacer() })
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
                        if isSelected { outputConfig.screens[idx].enabled.toggle() }
                        else {
                            outputConfig.screens[idx].displayID = display.id
                            outputConfig.screens[idx].width = 1920
                            outputConfig.screens[idx].height = 1080
                            outputConfig.screens[idx].enabled = true
                            openSingleWindow(id: "liveOutput")
                        }
                    } label: {
                        HStack(spacing: scaled(3, sc)) {
                            Circle().fill(isActive ? Color.green : Color.gray.opacity(0.4)).frame(width: scaled(6, sc), height: scaled(6, sc))
                            Image(systemName: display.isMain ? "macbook" : "display").font(.system(size: sf(8, sc)))
                            Text(display.name).font(.system(size: sf(7, sc), weight: .heavy, design: .monospaced))
                            Spacer()
                            if isSelected {
                                Text(isActive ? "ON" : "OFF").font(.system(size: sf(6, sc), weight: .black, design: .monospaced))
                                    .foregroundColor(isActive ? .green : .gray)
                            }
                        }
                        .foregroundColor(isSelected ? .white : .gray)
                        .padding(.horizontal, scaled(4, sc)).padding(.vertical, scaled(3, sc))
                        .background(isActive ? R.opacity(0.15) : Color.white.opacity(0.02))
                        .overlay(Rectangle().stroke(isActive ? R.opacity(0.4) : Color.clear, lineWidth: 0.5))
                    }.buttonStyle(TactileButtonStyle())
                }
            }

            // Open / Refresh buttons — uniform size
            HStack(spacing: scaled(2, sc)) {
                Button {
                    outputConfig.screens[idx].enabled = true
                    openSingleWindow(id: "liveOutput")
                } label: {
                    HStack(spacing: scaled(2, sc)) {
                        Image(systemName: "rectangle.on.rectangle").font(.system(size: sf(8, sc), weight: .bold))
                        Text("OPEN").font(.system(size: sf(7, sc), weight: .black, design: .monospaced))
                    }.foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, scaled(3, sc)).background(R.opacity(0.3))
                }.buttonStyle(TactileButtonStyle())

                Button { renderEngine.displayManager.refreshDisplays() } label: {
                    HStack(spacing: scaled(2, sc)) {
                        Image(systemName: "arrow.clockwise").font(.system(size: sf(8, sc), weight: .bold))
                        Text("REFRESH").font(.system(size: sf(7, sc), weight: .black, design: .monospaced))
                    }.foregroundColor(R).frame(maxWidth: .infinity).padding(.vertical, scaled(3, sc)).background(R.opacity(0.08))
                }.buttonStyle(TactileButtonStyle())
            }
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
                    HStack(spacing: scaled(4, sc)) {
                        // Color bar
                        Rectangle().fill(isSel ? R : .gray.opacity(0.4))
                            .frame(width: scaled(3, sc))

                        VStack(alignment: .leading, spacing: scaled(1, sc)) {
                            Text(slice.name)
                                .font(.system(size: sf(8, sc), weight: .black, design: .monospaced))
                                .foregroundColor(isSel ? .white : .gray)
                            HStack(spacing: scaled(4, sc)) {
                                if hasMesh {
                                    Text("MESH \(slice.meshWarp.cols)x\(slice.meshWarp.rows)")
                                        .font(.system(size: sf(5, sc), weight: .heavy, design: .monospaced))
                                        .foregroundColor(R.opacity(0.5))
                                }
                                Text(String(format: "%.0f%%x%.0f%%", slice.outputW * 100, slice.outputH * 100))
                                    .font(.system(size: sf(5, sc), weight: .bold, design: .monospaced))
                                    .foregroundColor(.gray.opacity(0.6))
                            }
                        }

                        Spacer()

                        // Enabled indicator
                        Circle()
                            .fill(slice.enabled ? Color.green.opacity(0.6) : Color.gray.opacity(0.3))
                            .frame(width: scaled(5, sc), height: scaled(5, sc))

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
                    .padding(.vertical, scaled(4, sc))
                    .padding(.horizontal, scaled(4, sc))
                    .background(isSel ? R.opacity(0.12) : Color.white.opacity(0.02))
                    .overlay(
                        Rectangle().stroke(isSel ? R.opacity(0.3) : Color.white.opacity(0.04), lineWidth: 0.5)
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

            HStack(spacing: scaled(6, sc)) {
                numField("X", slice.outputX, sc, range: 0...1, step: 0.01)
                numField("Y", slice.outputY, sc, range: 0...1, step: 0.01)
            }
            HStack(spacing: scaled(6, sc)) {
                numField("W", slice.outputW, sc, range: 0.01...1, step: 0.01)
                numField("H", slice.outputH, sc, range: 0.01...1, step: 0.01)
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
            HStack(spacing: scaled(6, sc)) {
                numField("X", slice.sourceX, sc, range: 0...1, step: 0.01)
                numField("Y", slice.sourceY, sc, range: 0...1, step: 0.01)
            }
            HStack(spacing: scaled(6, sc)) {
                numField("W", slice.sourceW, sc, range: 0.01...1, step: 0.01)
                numField("H", slice.sourceH, sc, range: 0.01...1, step: 0.01)
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
                )).labelsHidden().tint(.green).scaleEffect(0.7)

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
                    )).labelsHidden().tint(.green).scaleEffect(0.7)

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
        HStack(spacing: 4) {
            Rectangle().fill(R).frame(width: 2, height: 12)
            Text(text).font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundColor(R.opacity(0.8)).tracking(0.5)
        }
    }

    private func sublabel(_ text: String, _ sc: CGFloat) -> some View {
        Text(text).font(.system(size: sf(7, sc), weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5))
    }
}
