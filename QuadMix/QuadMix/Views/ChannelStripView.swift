import SwiftUI

struct ChannelStripView: View {
    let channel: Channel
    let renderEngine: RenderEngine
    let inputManager: InputManager
    var mixerState: MixerState?
    var isNarrow: Bool = false

    @State private var showSourcePicker = false
    @State private var showColorCorrection = false
    @State private var showEffects = false

    private let channelColors: [Color] = [
        Color(red: 0.3, green: 0.55, blue: 1.0),
        Color(red: 0.2, green: 0.78, blue: 0.45),
        Color(red: 1.0, green: 0.55, blue: 0.2),
        Color(red: 0.7, green: 0.35, blue: 1.0),
    ]

    var channelColor: Color {
        channel.id < channelColors.count ? channelColors[channel.id] : .blue
    }

    var isSelectedForPreview: Bool {
        mixerState?.selectedPreviewChannel == channel.id
    }

    var body: some View {
        VStack(spacing: 0) {
            headerCell
            cellBorder

            if isNarrow {
                narrowBody
            } else {
                fullBody
            }
        }
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
        .clipShape(Rectangle())
        .overlay(
            Rectangle()
                .stroke(
                    isSelectedForPreview ? Color.green.opacity(0.5) :
                    channelColor.opacity(channel.isActive ? 0.3 : 0.08),
                    lineWidth: isSelectedForPreview ? 1.5 : 1
                )
        )
    }

    // MARK: - Full layout (no per-channel preview)

    private var fullBody: some View {
        Group {
            sourceCell
            cellBorder
            blendCell
            cellBorder
            faderCell
            cellBorder
            transitionCell
            cellBorder
            effectsCell
            cellBorder
            colorCell
        }
    }

    // MARK: - Narrow layout

    private var narrowBody: some View {
        VStack(spacing: 0) {
            // Fader + level
            HStack(spacing: 4) {
                FaderView(
                    level: Binding(
                        get: { channel.faderLevel },
                        set: { channel.faderLevel = $0 }
                    ),
                    isTransitioning: channel.isTransitioning,
                    channelColor: channelColor
                )
                .frame(height: 55)

                Text("\(Int(channel.faderLevel * 100))")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 24)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 4)

            cellBorder

            sourceCell
            cellBorder

            // Blend + transition row
            HStack(spacing: 0) {
                blendCell
                Rectangle().fill(Color.white.opacity(0.04)).frame(width: 0.5)
                transitionCellCompact
            }
            cellBorder

            // FX + Color + AUTO button row
            HStack(spacing: 3) {
                compactButton(
                    icon: channel.isFrozen ? "pause.circle.fill" : "wand.and.stars",
                    label: "FX",
                    active: channel.effectType != .none || channel.isFrozen,
                    tint: channelColor
                ) {
                    showEffects.toggle()
                }
                .popover(isPresented: $showEffects) {
                    EffectsPopover(channel: channel, accentColor: channelColor)
                        .frame(width: 280)
                }

                compactButton(
                    icon: "slider.horizontal.3",
                    label: "CLR",
                    active: !channel.colorCorrection.isIdentity,
                    tint: .orange
                ) {
                    showColorCorrection.toggle()
                }
                .popover(isPresented: $showColorCorrection) {
                    ColorCorrectionView(
                        title: "\(channel.displayName) Color",
                        correction: Binding(
                            get: { channel.colorCorrection },
                            set: { channel.colorCorrection = $0 }
                        )
                    )
                    .frame(width: 300)
                }

                Button {
                    if channel.isTransitioning {
                        renderEngine.transitionEngine.cancelTransition(for: channel)
                    } else {
                        let target: Float = channel.faderLevel > 0.5 ? 0.0 : 1.0
                        renderEngine.transitionEngine.triggerTransition(channel: channel, targetLevel: target)
                    }
                    Haptics.thud()
                } label: {
                    Text(channel.isTransitioning ? "STP" : "AUT")
                        .font(.system(size: 7, weight: .heavy, design: .monospaced))
                        .foregroundColor(channel.isTransitioning ? .orange : .white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            Rectangle()
                                .fill(channel.isTransitioning ? Color.orange.opacity(0.3) : channelColor.opacity(0.15))
                        )
                }
                .buttonStyle(TactileButtonStyle())
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Cells

    private var headerCell: some View {
        Button {
            mixerState?.selectedPreviewChannel = channel.id
            Haptics.tap()
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(channel.isActive ? channelColor : Color.gray.opacity(0.15))
                    .frame(width: 6, height: 6)
                    .shadow(color: channel.isActive ? channelColor.opacity(0.6) : .clear, radius: 4)

                Text(channel.displayName)
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(channel.isActive ? .white : .gray.opacity(0.5))
                    .tracking(1)

                Spacer()

                // PVW indicator when this channel is selected for preview
                if isSelectedForPreview {
                    Text("PVW")
                        .font(.system(size: 7, weight: .heavy, design: .monospaced))
                        .foregroundColor(.green)
                        .tracking(0.5)
                }

                Text("\(Int(channel.faderLevel * 100))%")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(channel.faderLevel > 0.001 ? channelColor : .gray.opacity(0.3))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                isSelectedForPreview
                    ? channelColor.opacity(0.12)
                    : channelColor.opacity(channel.isActive ? 0.08 : 0.02)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sourceCell: some View {
        Button {
            showSourcePicker = true
            Haptics.tap()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: sourceIcon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(channel.source != nil ? .white : channelColor)
                    .frame(width: 18, height: 18)

                Text(channel.source?.displayName ?? "SELECT SOURCE")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundColor(channel.source != nil ? .white : channelColor)
                    .lineLimit(1)
                    .tracking(channel.source == nil ? 0.5 : 0)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(channel.source != nil ? .white.opacity(0.4) : channelColor.opacity(0.6))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                Rectangle()
                    .fill(channel.source != nil ? channelColor.opacity(0.2) : channelColor.opacity(0.08))
                    .overlay(
                        Rectangle()
                            .stroke(channelColor.opacity(channel.source != nil ? 0.4 : 0.25), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(TactileButtonStyle())
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .fullScreenCover(isPresented: $showSourcePicker) {
            SourcePickerView(channel: channel, renderEngine: renderEngine, inputManager: inputManager)
        }
    }

    private var blendCell: some View {
        HStack(spacing: 3) {
            Text("BLD")
                .font(.system(size: 7, weight: .heavy, design: .monospaced))
                .foregroundColor(.gray.opacity(0.4))
                .frame(width: 20, alignment: .leading)
            BlendModePickerView(
                selectedMode: Binding(
                    get: { channel.blendMode },
                    set: { channel.blendMode = $0 }
                ),
                accentColor: channelColor
            )
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 3)
    }

    private var faderCell: some View {
        HStack(spacing: 6) {
            FaderView(
                level: Binding(
                    get: { channel.faderLevel },
                    set: { channel.faderLevel = $0 }
                ),
                isTransitioning: channel.isTransitioning,
                channelColor: channelColor
            )
            .frame(height: 65)
            levelMeter
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
    }

    private var transitionCell: some View {
        TransitionControlView(
            channel: channel,
            transitionEngine: renderEngine.transitionEngine,
            accentColor: channelColor
        )
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
    }

    private var transitionCellCompact: some View {
        TransitionControlView(
            channel: channel,
            transitionEngine: renderEngine.transitionEngine,
            accentColor: channelColor
        )
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
    }

    private var effectsCell: some View {
        EffectsControlView(channel: channel, accentColor: channelColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
    }

    private var colorCell: some View {
        let isActive = !channel.colorCorrection.isIdentity
        let tint: Color = .orange

        return Button {
            showColorCorrection.toggle()
            Haptics.tap()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isActive ? .white : tint)
                    .frame(width: 18, height: 18)
                Text(isActive ? "COLOR ON" : "COLOR")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundColor(isActive ? .white : tint)
                    .tracking(0.5)
                Spacer()
                if isActive {
                    Circle().fill(tint).frame(width: 6, height: 6)
                        .shadow(color: tint.opacity(0.6), radius: 3)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(isActive ? .white.opacity(0.4) : tint.opacity(0.6))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                Rectangle()
                    .fill(isActive ? tint.opacity(0.25) : tint.opacity(0.08))
                    .overlay(
                        Rectangle()
                            .stroke(tint.opacity(isActive ? 0.5 : 0.25), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(TactileButtonStyle())
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .popover(isPresented: $showColorCorrection) {
            ColorCorrectionView(
                title: "\(channel.displayName) Color",
                correction: Binding(
                    get: { channel.colorCorrection },
                    set: { channel.colorCorrection = $0 }
                )
            )
            .frame(width: 320)
        }
    }

    // MARK: - Helpers

    private var cellBorder: some View {
        Rectangle().fill(Color.white.opacity(0.04)).frame(height: 0.5)
    }

    private var levelMeter: some View {
        VStack(spacing: 1.5) {
            ForEach((0..<10).reversed(), id: \.self) { i in
                let isLit = channel.faderLevel > Float(i) / 10.0
                Rectangle()
                    .fill(meterColor(for: i, lit: isLit))
                    .frame(width: 8, height: 5)
            }
        }
    }

    private func meterColor(for index: Int, lit: Bool) -> Color {
        guard lit else { return Color.white.opacity(0.04) }
        if index >= 8 { return .red.opacity(0.8) }
        if index >= 6 { return .yellow.opacity(0.7) }
        return .green.opacity(0.6)
    }

    private var sourceIcon: String {
        guard let source = channel.source else { return "plus.circle" }
        switch source {
        case .camera: return "camera.fill"
        case .externalCamera: return "cable.connector"
        case .mediaFile: return "film"
        case .image: return "photo"
        case .solidColor: return "circle.fill"
        case .pattern: return "checkerboard.rectangle"
        case .ndi: return "network"
        case .audioVisualizer(let style): return style.icon
        }
    }

    private func compactButton(icon: String, label: String, active: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: { action(); Haptics.tap() }) {
            VStack(spacing: 1) {
                Image(systemName: icon).font(.system(size: 9))
                Text(label).font(.system(size: 6, weight: .heavy, design: .monospaced))
            }
            .foregroundColor(active ? .white : tint.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                Rectangle()
                    .fill(active ? tint.opacity(0.25) : Color.white.opacity(0.03))
                    .overlay(
                        Rectangle()
                            .stroke(active ? tint.opacity(0.4) : Color.white.opacity(0.05), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(TactileButtonStyle())
    }
}

struct EffectsPopover: View {
    let channel: Channel
    var accentColor: Color = .blue
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Effects — \(channel.displayName)").font(.headline)
            EffectsControlView(channel: channel, accentColor: accentColor)
        }
        .padding()
    }
}
