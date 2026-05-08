import SwiftUI

struct MixerView: View {
    let mixerState: MixerState
    let renderEngine: RenderEngine
    let inputManager: InputManager

    // Crossfader state lives on MixerState now so the master LFO can drive it.
    // bpm is on mixerState.bpm
    @State private var presetManager = PresetManager()
    @State private var showGlobalColor = false
    @State private var showPresets = false
    @State private var showAbout = false
    /// Snapshot of channel faders captured the moment the user hits FADE TO
    /// BLACK, so RECALL can restore them. `nil` means there's nothing to
    /// recall (no fade has happened, or the user has touched faders since).
    @State private var preFadeLevels: [Float]? = nil

    // Unified panel system — replaces all sheets
    enum PanelType: Equatable {
        case none
        case fxParams(Int)
        case color(Int)
        case audio(Int)
        case globalColor
        case presets
        case advancedOutput
        case masterLFO
        case source(Int)
    }
    @State private var activePanel: PanelType = .none
    @State private var sourcePickerChannel: Int? = nil
    @Environment(\.openWindow) private var openWindow

    private let R = Color(red: 1.0, green: 0.15, blue: 0.15)
    private let cc: [Color] = [
        Color(red: 1.0, green: 0.15, blue: 0.15),
        Color(red: 1.0, green: 0.15, blue: 0.15),
        Color(red: 1.0, green: 0.15, blue: 0.15),
        Color(red: 1.0, green: 0.15, blue: 0.15),
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            // Liquid layout — every region scales proportionally with the
            // window so the mixer fills the space whether it's a Slide Over
            // sliver, half-screen Stage Manager, or full-screen iPad Pro.
            // Monitors take a fixed share of height; the mixer below
            // computes its own scale to fill the remaining area.
            let monitorH = min(320, max(96, h * 0.28))
            let topBarH: CGFloat = 30
            let chromePad: CGFloat = 8
            let contentH = max(180, h - topBarH - monitorH - chromePad)
            // Natural unscaled height of the channels HStack + master
            // VStack. Empirical baseline; bump if the layout grows
            // vertically.
            let naturalContentH: CGFloat = 560
            let naturalContentW: CGFloat = 500
            let scaleW = w / naturalContentW
            let scaleH = contentH / naturalContentH
            // Pure min(scaleW, scaleH) — no floor, no ceiling. The mixer
            // gracefully shrinks for tiny windows and grows for big ones,
            // always filling the available space without scrolling or
            // clipping.
            let scaleFactor = min(scaleW, scaleH)

            VStack(spacing: 0) {
                topBar
                monitors.frame(height: monitorH)

                ZStack {
                    VStack(spacing: 0) {
                        HStack(alignment: .top, spacing: 3) {
                            ForEach(0..<4) { i in channelCell(i) }
                        }
                        .padding(.horizontal, 3).padding(.top, 3)

                        masterSection(width: w)
                            .padding(.horizontal, 3).padding(.top, 4).padding(.bottom, 8)
                    }
                    .scaleEffect(scaleFactor, anchor: .topLeading)
                    .frame(width: w / scaleFactor, alignment: .leading)
                    .frame(width: w, alignment: .leading)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .opacity(activePanel == .none ? 1 : 0.3)

                    if activePanel != .none {
                        panelOverlay(scale: scaleFactor)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .background(Color(red: 0.03, green: 0.03, blue: 0.04))
                .animation(.easeInOut(duration: 0.15), value: activePanel)
            }
            .background(Color.black)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onAppear { Haptics.prepare() }
        .statusBarHidden()
        // Route any change to `sourcePickerChannel` (set by the channel-strip
        // SourceButton) into the unified panel system so the source picker
        // opens as a panel — keeping PVW/PGM monitors visible at the top —
        // instead of a full-screen sheet that covered them.
        .onChange(of: sourcePickerChannel) { _, new in
            if let i = new {
                activePanel = .source(i)
                sourcePickerChannel = nil
            }
        }
    }

    // MARK: - Panel Overlay (replaces all sheets)

    private func panelOverlay(scale: CGFloat) -> some View {
        // Bigger ceiling for iPad — controls inside panels were too small to tap reliably.
        let fs = min(2.0, max(0.9, scale * 0.85 + 0.15))

        return VStack(spacing: 0) {
            HStack {
                panelTitle(fs)
                Spacer()
                Button {
                    activePanel = .none
                } label: {
                    Text("CLOSE")
                        .font(.system(size: 11 * fs, weight: .black, design: .monospaced))
                        .foregroundColor(R)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(R.opacity(0.15))
                        .overlay(Rectangle().stroke(R.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(TactileButtonStyle())
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color(red: 0.05, green: 0.05, blue: 0.06))

            Rectangle().fill(R.opacity(0.2)).frame(height: 1)

            ScrollView(.vertical, showsIndicators: true) {
                panelContent
                    .padding(.bottom, 20)
            }
        }
        .font(.system(size: 10 * fs, design: .monospaced))
        .background(Color(red: 0.04, green: 0.04, blue: 0.05))
    }

    @ViewBuilder
    private func panelTitle(_ fs: CGFloat) -> some View {
        let fs = 13 * fs
        switch activePanel {
        case .fxParams(let i):
            Text("FX PARAMS — CH\(i+1)")
                .font(.system(size: fs, weight: .black, design: .monospaced)).foregroundColor(.white)
        case .color(let i):
            Text("COLOR — CH\(i+1)")
                .font(.system(size: fs, weight: .black, design: .monospaced)).foregroundColor(.white)
        case .audio(let i):
            Text("AUDIO REACT — CH\(i+1)")
                .font(.system(size: fs, weight: .black, design: .monospaced)).foregroundColor(.white)
        case .globalColor:
            Text("GLOBAL COLOR")
                .font(.system(size: fs, weight: .black, design: .monospaced)).foregroundColor(.white)
        case .presets:
            Text("PRESETS")
                .font(.system(size: fs, weight: .black, design: .monospaced)).foregroundColor(.white)
        case .masterLFO:
            Text("MASTER LFO")
                .font(.system(size: fs, weight: .black, design: .monospaced)).foregroundColor(.white)
        case .source(let i):
            Text("SOURCE — CH\(i+1)")
                .font(.system(size: fs, weight: .black, design: .monospaced)).foregroundColor(.white)
        case .advancedOutput:
            EmptyView()
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private var panelContent: some View {
        switch activePanel {
        case .fxParams(let i):
            FXParamsPanel(channel: mixerState.channels[i], color: cc[i], bpm: mixerState.bpm)
        case .color(let i):
            ColorCorrectionView(title: "CH\(i+1) Color",
                correction: Binding(get: { mixerState.channels[i].colorCorrection }, set: { mixerState.channels[i].colorCorrection = $0 }))
        case .audio(let i):
            AudioReactView(channel: mixerState.channels[i], audioEngine: renderEngine.audioEngine, accentColor: cc[i])
        case .globalColor:
            ColorCorrectionView(title: "Global Color",
                correction: Binding(get: { mixerState.globalColorCorrection }, set: { mixerState.globalColorCorrection = $0 }))
        case .presets:
            PresetListView(mixerState: mixerState, presetManager: presetManager)
        case .masterLFO:
            MasterLFOView(mixerState: mixerState).padding()
        case .source(let i):
            if i < mixerState.channels.count {
                SourcePickerView(
                    channel: mixerState.channels[i],
                    renderEngine: renderEngine,
                    inputManager: inputManager,
                    onClose: { activePanel = .none }
                )
            }
        case .advancedOutput:
            EmptyView()
        case .none:
            EmptyView()
        }
    }

    // MARK: - Top Bar

    private func openAdvancedOutput() {
        // Only allow one Advanced Output window — focus existing or open new
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        // The first scene is the mixer. Any additional scene is the advanced output.
        if scenes.count > 1, let existing = scenes.dropFirst().first {
            existing.windows.first?.makeKeyAndVisible()
            return
        }
        openWindow(id: "advancedOutput")
    }

    private var topBar: some View {
        ZStack {
            // Tap WASTEMIX to open the About / NDI attribution sheet.
            Button { showAbout = true; Haptics.tap() } label: {
                Text("WASTEMIX")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(R.opacity(0.7))
                    .tracking(3)
            }
            .buttonStyle(.plain)
            HStack {
                Spacer()
                Circle().fill(R.opacity(0.5)).frame(width: 5, height: 5)
                Text("\(mixerState.frameRate)fps")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(R.opacity(0.5))
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 3)
        .background(Color(red: 0.04, green: 0.04, blue: 0.05))
        .sheet(isPresented: $showAbout) { AboutView() }
    }

    // MARK: - Monitors

    private var monitors: some View {
        HStack(spacing: 1) {
            monBox("PVW", R) {
                PreviewView(device: MetalContext.shared.device, textureProvider: {
                    let i = mixerState.selectedPreviewChannel
                    guard i < renderEngine.channelPreviewTextures.count else { return nil }
                    return renderEngine.channelPreviewTextures[i]
                })
            }
            monBox("PGM", .red) { ProgramOutputView(renderEngine: renderEngine) }
        }
        .padding(2).background(Color(red: 0.02, green: 0.02, blue: 0.025))
    }

    private func monBox<C: View>(_ label: String, _ tint: Color, @ViewBuilder c: () -> C) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Spacer()
                Rectangle().fill(tint).frame(width: 10, height: 2)
                Text(label).font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(tint).tracking(1.5)
                Rectangle().fill(tint).frame(width: 10, height: 2)
                Spacer()
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(Color.black)

            c().aspectRatio(16/9, contentMode: .fit)
                .overlay(Rectangle().stroke(tint.opacity(0.15), lineWidth: 0.5))
        }
    }

    // MARK: - Channel Cell (all controls per channel)

    // MARK: - Channel Cell — sharp industrial style

    private func channelCell(_ i: Int) -> some View {
        let ch = mixerState.channels[i]
        let sel = mixerState.selectedPreviewChannel == i
        let c = cc[i]

        return VStack(spacing: 0) {
            // Header — fatter colored top bar when this channel is the
            // active preview, plus a saturated background, so the PVW
            // selection reads at a glance instead of needing the user to
            // hunt for the small "PVW" label.
            Rectangle().fill(c).frame(height: sel ? 5 : 2)
                .shadow(color: sel ? c.opacity(0.6) : .clear, radius: 4)
            Button { mixerState.selectedPreviewChannel = i; Haptics.tap() } label: {
                HStack(spacing: 4) {
                    Text("CH\(i+1)")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundColor(sel ? .white : .white.opacity(0.85))
                    if sel {
                        Text("PVW")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(R)
                    }
                    Spacer()
                    Text("\(Int(ch.faderLevel * 100))")
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundColor(c)
                }
                .padding(.horizontal, 5).padding(.vertical, 4)
                .background(sel ? c.opacity(0.18) : Color.white.opacity(0.015))
                .overlay(
                    Rectangle().stroke(sel ? c : Color.clear, lineWidth: sel ? 1 : 0)
                )
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
            edge(c)

            // Fader
            FaderView(
                level: Binding(get: { ch.faderLevel }, set: { ch.faderLevel = $0 }),
                isTransitioning: ch.isTransitioning, channelColor: c
            )
            .frame(height: 70).padding(.horizontal, 3).padding(.vertical, 2)
            edge(c)

            // Blend
            sharpCell(c) {
                Menu {
                    ForEach(ChannelBlendMode.allCases) { m in
                        Button { ch.blendMode = m; Haptics.tap() } label: {
                            Label(m.displayName, systemImage: m == ch.blendMode ? "checkmark" : "")
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "square.stack.3d.up").font(.system(size: 9, weight: .bold))
                            .foregroundColor(c)
                        Text(ch.blendMode.shortLabel).font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundColor(ch.blendMode != .normal ? .white : .white.opacity(0.8))
                        Spacer()
                        Image(systemName: "chevron.compact.down").font(.system(size: 8)).foregroundColor(.gray)
                    }
                    .contentShape(Rectangle())
                }.menuStyle(.borderlessButton)
            }
            edge(c)

            // Source
            sharpCell(c) {
                SourceButton(channel: ch, color: c, sourcePickerChannel: $sourcePickerChannel)
            }
            edge(c)

            // Transition + GO
            sharpCell(c) {
                HStack(spacing: 2) {
                    Menu {
                        ForEach(TransitionType.allCases) { t in
                            Button { ch.transitionConfig.type = t; Haptics.tap() } label: {
                                Label(t.displayName, systemImage: t == ch.transitionConfig.type ? "checkmark" : t.icon)
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: ch.transitionConfig.type.icon).font(.system(size: 9))
                                .foregroundColor(c)
                            Text(ch.transitionConfig.type.shortLabel).font(.system(size: 9, weight: .black, design: .monospaced))
                                .foregroundColor(.white.opacity(0.8))
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }.menuStyle(.borderlessButton)

                    Button {
                        if ch.isTransitioning { renderEngine.transitionEngine.cancelTransition(for: ch) }
                        else { renderEngine.transitionEngine.triggerTransition(channel: ch, targetLevel: ch.faderLevel > 0.5 ? 0 : 1) }
                        Haptics.thud()
                    } label: {
                        Text(ch.isTransitioning ? "STOP" : "GO")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundColor(ch.isTransitioning ? .black : c)
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .background(ch.isTransitioning ? R : c.opacity(0.4))
                    }.buttonStyle(TactileButtonStyle())
                }
            }
            edge(c)

            // FX type + params button
            sharpCell(c) {
                HStack(spacing: 2) {
                    Menu {
                        ForEach(EffectType.allCases) { fx in
                            Button {
                                ch.effectType = fx
                                // Reset to the effect's natural starting strength
                                // so it visibly engages instead of sitting at 0.5
                                // (which often produces a no-op or muddy mix —
                                // notably Invert at 0.5 is fully grey).
                                ch.effectIntensity = fx.defaultIntensity
                                ch.effectParam2 = fx.defaultParam2
                                Haptics.tap()
                            } label: {
                                Label(fx.displayName, systemImage: fx == ch.effectType ? "checkmark" : fx.icon)
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: ch.effectType != .none ? ch.effectType.icon : "wand.and.stars")
                                .font(.system(size: 9)).foregroundColor(ch.effectType != .none ? c : .gray)
                            Text(ch.effectType != .none ? ch.effectType.displayName : "FX")
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .foregroundColor(ch.effectType != .none ? .white : .white.opacity(0.8))
                                .lineLimit(1)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }.menuStyle(.borderlessButton)

                    FXParamsButton(channel: ch, color: c, bpm: mixerState.bpm, onTap: { activePanel = .fxParams(i) })
                }
            }
            edge(c)

            // Audio + Color
            HStack(spacing: 1) {
                AudioReactButton(channel: ch, renderEngine: renderEngine, color: c, onTap: { activePanel = .audio(i) })
                Rectangle().fill(c.opacity(0.25)).frame(width: 1)
                ChannelColorButton(channel: ch, color: c, onTap: { activePanel = .color(i) })
            }
            .padding(.horizontal, 3).padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.045, green: 0.045, blue: 0.05))
    }

    /// Sharp-edged cell wrapper — no rounded corners
    private func sharpCell<C: View>(_ c: Color, @ViewBuilder content: () -> C) -> some View {
        content()
            .padding(.horizontal, 4).padding(.vertical, 4)
    }

    /// Hard edge separator line in channel color
    private func edge(_ c: Color) -> some View {
        Rectangle().fill(c.opacity(0.25)).frame(height: 1)
    }

    // MARK: - Master Section (full width below channels)

    private func masterSection(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 0) {
                Rectangle().fill(R).frame(height: 2)
                HStack {
                    Text("MASTER").font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(R).tracking(2)
                    Spacer()
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(R.opacity(0.03))
            }

            // Two columns: crossfader left, other controls right
            HStack(alignment: .top, spacing: 0) {
                // Crossfader
                VStack(spacing: 4) {
                    // A selector — multi-select
                    HStack(spacing: 2) {
                        Text("A").font(.system(size: 7, weight: .heavy, design: .monospaced)).foregroundColor(R.opacity(0.5)).frame(width: 12)
                        ForEach(0..<4) { i in
                            chSelectBtn(i, selected: mixerState.crossfaderA.contains(i)) {
                                if mixerState.crossfaderA.contains(i) { mixerState.crossfaderA.remove(i) }
                                else { mixerState.crossfaderA.insert(i) }
                            }
                        }
                    }

                    // Slider
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 24)
                                .overlay(Rectangle().stroke(Color.white.opacity(0.06), lineWidth: 0.5))
                            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 14).offset(x: geo.size.width / 2)
                            Rectangle().fill(R).frame(width: 32, height: 22)
                                .shadow(color: R.opacity(0.3), radius: 2)
                                .offset(x: CGFloat(mixerState.crossfaderPos) * (geo.size.width - 32))
                        }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                            mixerState.crossfaderPos = max(0, min(1, Float(v.location.x / geo.size.width)))
                            mixerState.applyCrossfader()
                        })
                    }.frame(height: 24)

                    // B selector — multi-select
                    HStack(spacing: 2) {
                        Text("B").font(.system(size: 7, weight: .heavy, design: .monospaced)).foregroundColor(R.opacity(0.5)).frame(width: 12)
                        ForEach(0..<4) { i in
                            chSelectBtn(i, selected: mixerState.crossfaderB.contains(i)) {
                                if mixerState.crossfaderB.contains(i) { mixerState.crossfaderB.remove(i) }
                                else { mixerState.crossfaderB.insert(i) }
                            }
                        }
                    }

                    Rectangle().fill(R.opacity(0.06)).frame(height: 0.5).padding(.vertical, 2)

                    // Master LFO — sits between crossfader and tempo so the
                    // automation lives next to the controls it modulates.
                    // Same shape as the per-channel "transition + GO" cell:
                    // click-through label opens the panel, separate toggle
                    // turns the LFO on/off without opening it.
                    let mlOn = mixerState.masterLFO.isActive
                    HStack(spacing: 2) {
                        Button { activePanel = .masterLFO; Haptics.tap() } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "waveform.path").font(.system(size: 11))
                                Text("MASTER LFO").font(.system(size: 9, weight: .black, design: .monospaced)).tracking(0.5)
                                Spacer()
                                if mlOn {
                                    Text("\(Int(mixerState.masterLFO.currentValue * 100))%")
                                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                }
                            }
                            .foregroundColor(mlOn ? R : .gray)
                            .padding(.horizontal, 8).padding(.vertical, 8)
                            .background(Rectangle().fill(mlOn ? R.opacity(0.25) : Color.white.opacity(0.03))
                                .overlay(Rectangle().stroke(mlOn ? R.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 0.5)))
                            .contentShape(Rectangle())
                        }.buttonStyle(TactileButtonStyle())

                        Button {
                            mixerState.masterLFO.enabled.toggle()
                            Haptics.thud()
                        } label: {
                            Text(mlOn ? "ON" : "OFF")
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .foregroundColor(mlOn ? .black : R)
                                .padding(.horizontal, 8).padding(.vertical, 8)
                                .background(mlOn ? R : R.opacity(0.15))
                                .overlay(Rectangle().stroke(R.opacity(0.4), lineWidth: 0.5))
                        }.buttonStyle(TactileButtonStyle())
                    }

                    Rectangle().fill(R.opacity(0.06)).frame(height: 0.5).padding(.vertical, 2)

                    // Tap tempo
                    TapTempoView(bpm: Binding(get: { mixerState.bpm }, set: { mixerState.bpm = $0 }))
                }
                .padding(6)
                .frame(maxWidth: .infinity)

                Rectangle().fill(R.opacity(0.06)).frame(width: 0.5)

                // Right column: global color, quick, tempo, presets
                VStack(spacing: 0) {
                    // Global Color
                    mstCellView {
                        let active = !mixerState.globalColorCorrection.isIdentity
                        Button { activePanel = .globalColor; Haptics.tap() } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "paintpalette.fill").font(.system(size: 11))
                                Text("GLOBAL COLOR").font(.system(size: 9, weight: .black, design: .monospaced))
                                    .lineLimit(1).minimumScaleFactor(0.7)
                                Spacer()
                                if active { Circle().fill(R).frame(width: 6, height: 6).shadow(color: R.opacity(0.5), radius: 3) }
                            }
                            .foregroundColor(active ? R : .gray)
                            .padding(.horizontal, 8).padding(.vertical, 7)
                            .background(Rectangle().fill(active ? R.opacity(0.3) : Color.white.opacity(0.03))
                                .overlay(Rectangle().stroke(active ? R.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 0.5)))
                            .contentShape(Rectangle())
                        }.buttonStyle(TactileButtonStyle())
                    }

                    Rectangle().fill(R.opacity(0.04)).frame(height: 0.5)

                    // Fade to black + recall (restores pre-fade fader values)
                    mstCellView {
                        HStack(spacing: 3) {
                            // Active only when at least one channel has output
                            // — fading to black from already-black is a no-op.
                            let canFade = mixerState.channels.contains { $0.faderLevel > 0.001 }
                            Button {
                                // Snapshot current levels before fading so the
                                // user can recall them. Skip channels already
                                // at 0 — recalling a true-zero is pointless.
                                preFadeLevels = mixerState.channels.map { $0.faderLevel }
                                for ch in mixerState.channels {
                                    if ch.faderLevel > 0.001 {
                                        renderEngine.transitionEngine.triggerTransition(channel: ch, targetLevel: 0)
                                    }
                                }
                                Haptics.bump()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "moon.fill").font(.system(size: 11))
                                    Text("FADE TO BLACK").font(.system(size: 9, weight: .black, design: .monospaced))
                                        .tracking(0.5)
                                        .lineLimit(1).minimumScaleFactor(0.7)
                                }
                                .foregroundColor(canFade ? .white : R.opacity(0.4))
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(canFade ? R.opacity(0.45) : R.opacity(0.08))
                                .overlay(Rectangle().stroke(canFade ? R : R.opacity(0.2), lineWidth: 1))
                            }
                            .buttonStyle(TactileButtonStyle())
                            .disabled(!canFade)

                            // RECALL — restore the snapshot. Disabled until
                            // a fade has actually happened.
                            let canRecall = preFadeLevels != nil
                            Button {
                                guard let snap = preFadeLevels else { return }
                                for (i, level) in snap.enumerated() where i < mixerState.channels.count {
                                    if level > 0.001 {
                                        renderEngine.transitionEngine.triggerTransition(channel: mixerState.channels[i], targetLevel: level)
                                    }
                                }
                                preFadeLevels = nil
                                Haptics.thud()
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.uturn.backward").font(.system(size: 11))
                                    Text("RECALL").font(.system(size: 9, weight: .black, design: .monospaced))
                                        .lineLimit(1).minimumScaleFactor(0.7)
                                }
                                .foregroundColor(canRecall ? .white : R.opacity(0.4))
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(canRecall ? R.opacity(0.45) : R.opacity(0.08))
                                .overlay(Rectangle().stroke(canRecall ? R : R.opacity(0.2), lineWidth: 1))
                            }
                            .buttonStyle(TactileButtonStyle())
                            .disabled(!canRecall)
                        }
                    }

                    // Flexible gap so the bottom-of-column group (Advanced
                    // Output + Save/Load) is pushed down to align with TAP
                    // TEMPO at the bottom of the left column. The minLength
                    // also guarantees breathing room between RECALL and
                    // ADVANCED OUTPUT so a sloppy tap on one doesn't catch
                    // the other.
                    Spacer(minLength: 28)

                    Rectangle().fill(R.opacity(0.04)).frame(height: 0.5)

                    // Advanced Output — opens separate window.
                    // Dimmed when closed; brightens when active.
                    mstCellView {
                        let active = renderEngine.outputConfig.isAdvancedOutputOpen
                        Button {
                            openAdvancedOutput()
                            Haptics.tap()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "rectangle.on.rectangle.angled")
                                    .font(.system(size: 14, weight: .bold))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("ADVANCED OUTPUT")
                                        .font(.system(size: 10, weight: .black, design: .monospaced))
                                        .tracking(1)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    Text("MAPPING")
                                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                        .tracking(2)
                                        .opacity(0.7)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.forward.app.fill")
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(active ? .white : R.opacity(0.7))
                            .frame(maxWidth: .infinity).padding(.vertical, 11).padding(.horizontal, 10)
                            .background(active ? R.opacity(0.45) : R.opacity(0.10))
                            .overlay(Rectangle().stroke(active ? R : R.opacity(0.35), lineWidth: active ? 1 : 0.5))
                        }
                        .buttonStyle(TactileButtonStyle())
                    }

                    Rectangle().fill(R.opacity(0.04)).frame(height: 0.5)

                    // Presets — sit at the bottom of the master right column
                    // so the heavier Advanced Output button reads first.
                    mstCellView {
                        HStack(spacing: 3) {
                            bigMstBtn("SAVE", icon: "square.and.arrow.down", fg: R.opacity(0.7), bg: Color(red: 1.0, green: 0.15, blue: 0.15).opacity(0.05)) {
                                let p = presetManager.capture(from: mixerState, name: "P\(presetManager.presets.count+1)", crossfaderPos: mixerState.crossfaderPos, bpm: mixerState.bpm)
                                presetManager.save(preset: p); Haptics.success()
                            }
                            Button { activePanel = .presets; Haptics.tap() } label: {
                                VStack(spacing: 1) {
                                    Image(systemName: "list.bullet").font(.system(size: 10))
                                    Text("LOAD").font(.system(size: 6, weight: .heavy, design: .monospaced))
                                }
                                .foregroundColor(.gray).frame(maxWidth: .infinity).padding(.vertical, 6)
                                .background(Rectangle().fill(Color.white.opacity(0.03)))
                            }.buttonStyle(TactileButtonStyle())
                        }
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity)
            }
        }
        .background(Color(red: 0.04, green: 0.04, blue: 0.05))
    }

    // MARK: - Helpers

    private func pill(_ fill: Color) -> some View {
        Rectangle().fill(fill)
            .overlay(Rectangle().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
    }

    // applyCrossfader was moved to MixerState so the master LFO can call it too.

    private func chSelectBtn(_ i: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button { action(); Haptics.tap() } label: {
            Text("\(i+1)").font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(selected ? .white : .gray)
                .frame(maxWidth: .infinity).padding(.vertical, 5)
                .background(selected ? cc[i].opacity(0.35) : Color.white.opacity(0.03))
                .overlay(
                    VStack(spacing: 0) {
                        Rectangle().fill(selected ? cc[i] : Color.clear).frame(height: 2)
                        Spacer()
                    }
                )
        }.buttonStyle(TactileButtonStyle())
    }

    private func mstCellView<C: View>(@ViewBuilder content: () -> C) -> some View {
        content()
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
    }

    private func bigMstBtn(_ label: String, icon: String, fg: Color, bg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: icon).font(.system(size: 10))
                Text(label).font(.system(size: 6, weight: .heavy, design: .monospaced))
            }
            .foregroundColor(fg).frame(maxWidth: .infinity).padding(.vertical, 6)
            .background(Rectangle().fill(bg)
                .overlay(Rectangle().stroke(fg.opacity(0.15), lineWidth: 0.5)))
        }.buttonStyle(TactileButtonStyle())
    }
}

// MARK: - Theme constant for extracted views
private let WMRed = Color(red: 1.0, green: 0.15, blue: 0.15)

// MARK: - Extracted Components

struct SourceButton: View {
    let channel: Channel; let color: Color
    @Binding var sourcePickerChannel: Int?
    private var hasSource: Bool { channel.source != nil }
    private var icon: String {
        guard let s = channel.source else { return "plus.circle" }
        switch s {
        case .camera: return "camera.fill"
        case .mediaFile: return "film"
        case .image: return "photo"
        case .solidColor: return "circle.fill"
        case .pattern: return "checkerboard.rectangle"
        case .ndi: return "network"
        case .audioVisualizer(let style): return style.icon
        }
    }
    var body: some View {
        Button { sourcePickerChannel = channel.id; Haptics.tap() } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10))
                Text(hasSource ? (channel.source?.displayName ?? "") : "SOURCE")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).lineLimit(1)
            }
            .foregroundColor(hasSource ? .white : color.opacity(0.7))
            .frame(maxWidth: .infinity).padding(.vertical, 5)
            .background(
                Rectangle().fill(hasSource ? color.opacity(0.2) : Color.white.opacity(0.04))
                    .overlay(Rectangle().stroke(color.opacity(hasSource ? 0.2 : 0.08), lineWidth: 0.5))
            )
            .contentShape(Rectangle())
        }.buttonStyle(TactileButtonStyle())
    }
}

/// FX parameters popover button — replaces the old FRZ button.
/// Contains freeze toggle, intensity slider, key settings, PIP settings.
struct FXParamsButton: View {
    let channel: Channel
    let color: Color
    var bpm: Float = 120
    var onTap: () -> Void = {}

    private var hasActivity: Bool {
        channel.isFrozen || channel.effectIntensity != 0.5 || channel.keySettings.isActive || !channel.pipSettings.isDefault || channel.lfo.isActive
    }

    var body: some View {
        Button { onTap(); Haptics.tap() } label: {
            HStack(spacing: 3) {
                Image(systemName: "slider.horizontal.below.square.and.square.filled")
                    .font(.system(size: 13, weight: .bold))
                Text("FX").font(.system(size: 10, weight: .black, design: .monospaced))
            }
            .foregroundColor(hasActivity ? .white : .gray)
            .padding(.horizontal, 8).padding(.vertical, 9)
            .background(hasActivity ? color.opacity(0.3) : Color.white.opacity(0.04))
            .overlay(Rectangle().stroke(hasActivity ? color : Color.white.opacity(0.1), lineWidth: hasActivity ? 1 : 0.5))
        }
        .buttonStyle(TactileButtonStyle())
    }
}

struct FXParamsPanel: View {
    let channel: Channel
    let color: Color
    var bpm: Float = 120
    private let R = Color(red: 1.0, green: 0.15, blue: 0.15)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("FX PARAMS — \(channel.displayName)")
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .foregroundColor(.white)

                // Effect selector
                VStack(alignment: .leading, spacing: 6) {
                    Text("EFFECT")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(.gray)

                    // Grid of effect buttons
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 85), spacing: 4)], spacing: 4) {
                        ForEach(EffectType.allCases) { fx in
                            Button {
                                if channel.effectType != fx {
                                    channel.effectType = fx
                                    channel.effectIntensity = fx.defaultIntensity
                                    channel.effectParam2 = fx.defaultParam2
                                }
                                Haptics.tap()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: fx.icon).font(.system(size: 10))
                                    Text(fx.displayName).font(.system(size: 9, weight: .black, design: .monospaced))
                                        .lineLimit(1)
                                }
                                .foregroundColor(channel.effectType == fx ? .white : .gray)
                                .frame(maxWidth: .infinity).padding(.vertical, 6)
                                .background(channel.effectType == fx ? R.opacity(0.3) : Color.white.opacity(0.03))
                                .overlay(
                                    VStack(spacing: 0) {
                                        Rectangle().fill(channel.effectType == fx ? R : Color.clear).frame(height: 2)
                                        Spacer()
                                    }
                                )
                            }
                            .buttonStyle(TactileButtonStyle())
                        }
                    }
                }

                // Effect-specific parameters
                if channel.effectType != .none && channel.effectType != .freeze {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("PARAMETERS — \(channel.effectType.displayName.uppercased())")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(R.opacity(0.7))

                        // Primary parameter
                        paramSlider(
                            label: channel.effectType.param1Label.uppercased(),
                            value: Binding(get: { channel.effectIntensity }, set: { channel.effectIntensity = $0 })
                        )

                        // Secondary parameter (if this effect has one)
                        if channel.effectType.hasParam2 {
                            paramSlider(
                                label: channel.effectType.param2Label.uppercased(),
                                value: Binding(get: { channel.effectParam2 }, set: { channel.effectParam2 = $0 })
                            )
                        }

                        // Effect-specific info
                        effectDescription
                    }
                    .padding(8)
                    .background(R.opacity(0.04))
                }

                Divider()

                // LFO — sits between EFFECT and KEYING so the effect-modulation
                // controls live next to the effect they drive.
                LFOView(channel: channel, bpm: bpm)

                Divider()

                // Keying
                VStack(alignment: .leading, spacing: 4) {
                    Text("KEYING")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(.gray)

                    Picker("Type", selection: Binding(
                        get: { channel.keySettings.type },
                        set: { channel.keySettings.type = $0 }
                    )) {
                        ForEach(KeyType.allCases) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)

                    if channel.keySettings.type != .none {
                        CorrectionSlider(label: "THRESH", value: Binding(
                            get: { channel.keySettings.threshold },
                            set: { channel.keySettings.threshold = $0 }
                        ), range: 0...1, tint: R)

                        CorrectionSlider(label: "SOFT", value: Binding(
                            get: { channel.keySettings.softness },
                            set: { channel.keySettings.softness = $0 }
                        ), range: 0...0.5, tint: R)

                        if channel.keySettings.type == .chromaKey {
                            CorrectionSlider(label: "HUE", value: Binding(
                                get: { channel.keySettings.keyHue },
                                set: { channel.keySettings.keyHue = $0 }
                            ), range: 0...360, format: "%.0f", tint: R)
                        }
                    }
                }

                Divider()

                // PIP
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("PIP / POSITION")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(.gray)
                        Spacer()
                        if !channel.pipSettings.isDefault {
                            Button("Reset") { channel.pipSettings.reset() }
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(R)
                        }
                    }

                    CorrectionSlider(label: "SCALE", value: Binding(
                        get: { channel.pipSettings.scale },
                        set: { channel.pipSettings.scale = $0 }
                    ), range: 0.1...5.0, format: "%.1fx", tint: R)

                    CorrectionSlider(label: "X POS", value: Binding(
                        get: { channel.pipSettings.offsetX },
                        set: { channel.pipSettings.offsetX = $0 }
                    ), range: -1...1, tint: R)

                    CorrectionSlider(label: "Y POS", value: Binding(
                        get: { channel.pipSettings.offsetY },
                        set: { channel.pipSettings.offsetY = $0 }
                    ), range: -1...1, tint: R)
                }
            }
            .padding()
        }
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
    }

    private func paramSlider(label: String, value: Binding<Float>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.gray)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text("\(Int(value.wrappedValue * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
            }
            Slider(
                value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Float($0) }),
                in: 0...1
            )
            .tint(R)
        }
    }

    @ViewBuilder
    private var effectDescription: some View {
        let desc: String = {
            switch channel.effectType {
            case .mirror: return "Blends between normal and horizontally mirrored image"
            case .mirrorV: return "Blends between normal and vertically mirrored image"
            case .invert: return "Inverts colors. 0% = normal, 100% = full negative"
            case .mosaic: return "Pixelates the image. Higher = larger blocks"
            case .strobe: return "Flashes the image on/off at the set speed"
            case .rgbSplit: return "Separates R/G/B channels horizontally. Use vertical split for Y axis"
            case .posterize: return "Reduces color levels. Higher = more extreme"
            case .blur: return "Softens the image. Use direction bias for directional blur"
            default: return ""
            }
        }()

        if !desc.isEmpty {
            Text(desc)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.gray)
                .padding(.top, 2)
        }
    }
}

struct AudioReactButton: View {
    let channel: Channel; let renderEngine: RenderEngine; let color: Color
    var onTap: () -> Void = {}
    private var on: Bool { channel.audioReact.isActive }
    var body: some View {
        Button {
            if !renderEngine.audioEngine.isRunning { renderEngine.audioEngine.start() }
            onTap(); Haptics.tap()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "waveform").font(.system(size: 11))
                Text("AUDIO").font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundColor(on ? .white : .gray)
            .frame(maxWidth: .infinity).padding(.vertical, 7)
            .background(on ? WMRed.opacity(0.4) : Color.white.opacity(0.03))
            .overlay(Rectangle().stroke(on ? WMRed : Color.white.opacity(0.1), lineWidth: on ? 1 : 0.5))
            .contentShape(Rectangle())
        }.buttonStyle(TactileButtonStyle())
    }
}

struct ChannelColorButton: View {
    let channel: Channel; let color: Color
    var onTap: () -> Void = {}
    private var on: Bool { !channel.colorCorrection.isIdentity }
    var body: some View {
        Button { onTap(); Haptics.tap() } label: {
            HStack(spacing: 3) {
                Image(systemName: "paintpalette").font(.system(size: 11))
                Text("COLOR").font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundColor(on ? .white : .gray)
            .frame(maxWidth: .infinity).padding(.vertical, 7)
            .background(on ? WMRed.opacity(0.4) : Color.white.opacity(0.03))
            .overlay(Rectangle().stroke(on ? WMRed : Color.white.opacity(0.1), lineWidth: on ? 1 : 0.5))
            .contentShape(Rectangle())
        }.buttonStyle(TactileButtonStyle())
    }
}

