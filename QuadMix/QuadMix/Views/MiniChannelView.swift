import SwiftUI

/// Minimal channel strip for the smallest window sizes.
/// Shows fader + essential controls in a tight horizontal layout.
/// All 4 fit side by side even at 320pt width.
struct MiniChannelView: View {
    let channel: Channel
    let renderEngine: RenderEngine
    let inputManager: InputManager
    var mixerState: MixerState?

    @State private var showDetail = false

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
        VStack(spacing: 3) {
            // Channel label — tap to select for preview
            Button {
                mixerState?.selectedPreviewChannel = channel.id
                Haptics.tap()
            } label: {
                HStack(spacing: 3) {
                    Circle()
                        .fill(channel.isActive ? channelColor : .gray.opacity(0.2))
                        .frame(width: 5, height: 5)
                    Text("\(channel.id + 1)")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundColor(channel.isActive ? channelColor : .gray)
                    if isSelectedForPreview {
                        Text("PVW")
                            .font(.system(size: 5, weight: .heavy, design: .monospaced))
                            .foregroundColor(.green)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Fader
            FaderView(
                level: Binding(
                    get: { channel.faderLevel },
                    set: { channel.faderLevel = $0 }
                ),
                isTransitioning: channel.isTransitioning,
                channelColor: channelColor
            )

            // Level readout
            Text("\(Int(channel.faderLevel * 100))")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(channel.faderLevel > 0.001 ? .white.opacity(0.7) : .gray.opacity(0.3))

            // Blend mode (compact dropdown)
            Menu {
                ForEach(ChannelBlendMode.allCases) { mode in
                    Button {
                        channel.blendMode = mode
                        Haptics.tap()
                    } label: {
                        HStack {
                            Text(mode.displayName)
                            if mode == channel.blendMode { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                Text(channel.blendMode.shortLabel)
                    .font(.system(size: 7, weight: .heavy, design: .monospaced))
                    .foregroundColor(channel.blendMode != .normal ? .white : .gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                    .background(
                        Rectangle()
                            .fill(channel.blendMode != .normal ? channelColor.opacity(0.2) : Color.white.opacity(0.04))
                    )
            }
            .menuStyle(.borderlessButton)

            // Source indicator + tap to open detail
            Button {
                showDetail = true
                Haptics.tap()
            } label: {
                Image(systemName: channel.source != nil ? sourceIcon : "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(channel.source != nil ? channelColor : .gray.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(
                        Rectangle()
                            .fill(Color.white.opacity(0.04))
                            .overlay(
                                Rectangle()
                                    .stroke(channelColor.opacity(0.15), lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(TactileButtonStyle())

            // AUTO button
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
                    .padding(.vertical, 3)
                    .background(
                        Rectangle()
                            .fill(channel.isTransitioning ? Color.orange.opacity(0.3) : channelColor.opacity(0.15))
                    )
            }
            .buttonStyle(TactileButtonStyle())

            // Status dots: FX active, Color active, Key active
            HStack(spacing: 3) {
                statusDot("F", active: channel.isFrozen, color: .red)
                statusDot("X", active: channel.effectType != .none, color: channelColor)
                statusDot("C", active: !channel.colorCorrection.isIdentity, color: .orange)
                statusDot("K", active: channel.keySettings.isActive, color: .green)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .background(
            Rectangle()
                .fill(Color(red: 0.06, green: 0.06, blue: 0.07))
                .overlay(
                    Rectangle()
                        .stroke(
                            isSelectedForPreview ? Color.green.opacity(0.5) :
                            channelColor.opacity(channel.isActive ? 0.3 : 0.06),
                            lineWidth: isSelectedForPreview ? 1.5 : 0.5
                        )
                )
        )
        .sheet(isPresented: $showDetail) {
            MiniChannelDetailSheet(
                channel: channel,
                renderEngine: renderEngine,
                inputManager: inputManager,
                channelColor: channelColor
            )
        }
    }

    private func statusDot(_ label: String, active: Bool, color: Color) -> some View {
        Text(label)
            .font(.system(size: 6, weight: .heavy, design: .monospaced))
            .foregroundColor(active ? .white : .gray.opacity(0.3))
            .frame(width: 13, height: 13)
            .background(
                Rectangle()
                    .fill(active ? color.opacity(0.4) : Color.white.opacity(0.02))
            )
    }

    private var sourceIcon: String {
        guard let source = channel.source else { return "plus" }
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
}

/// Full detail sheet opened from mini channel view — all controls accessible
struct MiniChannelDetailSheet: View {
    let channel: Channel
    let renderEngine: RenderEngine
    let inputManager: InputManager
    let channelColor: Color

    @Environment(\.dismiss) var dismiss
    @State private var showSourcePicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    // Preview
                    PreviewView(
                        device: MetalContext.shared.device,
                        textureProvider: { renderEngine.channelPreviewTextures[channel.id] }
                    )
                    .aspectRatio(16/9, contentMode: .fit)
                    
                    .padding(.horizontal)

                    // Source
                    Button {
                        showSourcePicker = true
                    } label: {
                        HStack {
                            Image(systemName: "folder")
                            Text(channel.source?.displayName ?? "Select Source")
                                .fontWeight(.medium)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .background(Color.white.opacity(0.05))
                        
                    }
                    .padding(.horizontal)
                    .fullScreenCover(isPresented: $showSourcePicker) {
                        SourcePickerView(
                            channel: channel,
                            renderEngine: renderEngine,
                            inputManager: inputManager
                        )
                    }

                    // Transition settings
                    GroupBox("Transition") {
                        TransitionControlView(
                            channel: channel,
                            transitionEngine: renderEngine.transitionEngine,
                            accentColor: channelColor
                        )
                    }
                    .padding(.horizontal)

                    // Effects
                    GroupBox("Effects") {
                        EffectsControlView(channel: channel, accentColor: channelColor)
                    }
                    .padding(.horizontal)

                    // Color Correction
                    GroupBox("Color Correction") {
                        ColorCorrectionView(
                            title: "",
                            correction: Binding(
                                get: { channel.colorCorrection },
                                set: { channel.colorCorrection = $0 }
                            )
                        )
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle(channel.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
