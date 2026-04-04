import SwiftUI

/// Per-channel effects, keying, PIP, and freeze controls
struct EffectsControlView: View {
    let channel: Channel
    var accentColor: Color = .blue

    @State private var showKeySettings = false
    @State private var showPIPSettings = false

    var body: some View {
        VStack(spacing: 4) {
            // Freeze button
            freezeButton

            // Effect picker
            effectPicker

            // Intensity slider (when effect active)
            if channel.effectType != .none && channel.effectType != .freeze {
                intensitySlider
            }

            // Key + PIP row
            HStack(spacing: 3) {
                keyButton
                pipButton
            }
        }
    }

    private var freezeButton: some View {
        Button {
            channel.isFrozen.toggle()
            Haptics.thud()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: channel.isFrozen ? "pause.circle.fill" : "pause.circle")
                    .font(.system(size: 10, weight: .bold))
                Text("FREEZE")
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
            }
            .foregroundColor(channel.isFrozen ? .white : .gray)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                Rectangle()
                    .fill(channel.isFrozen ? Color.red.opacity(0.4) : Color.white.opacity(0.8))
                    .overlay(
                        Rectangle()
                            .stroke(channel.isFrozen ? Color.red.opacity(0.6) : Color.white.opacity(0.8), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(TactileButtonStyle())
    }

    private var effectPicker: some View {
        Menu {
            ForEach(EffectType.allCases) { fx in
                Button {
                    channel.effectType = fx
                    Haptics.tap()
                } label: {
                    Label {
                        Text(fx.displayName)
                    } icon: {
                        if fx == channel.effectType {
                            Image(systemName: "checkmark")
                        } else {
                            Image(systemName: fx.icon)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: channel.effectType.icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(channel.effectType != .none ? accentColor : .gray)
                Text(channel.effectType != .none ? channel.effectType.displayName : "FX")
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundColor(channel.effectType != .none ? .white : .gray)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                Rectangle()
                    .fill(channel.effectType != .none ? accentColor.opacity(0.15) : Color.white.opacity(0.8))
                    .overlay(
                        Rectangle()
                            .stroke(Color.white.opacity(0.8), lineWidth: 0.5)
                    )
            )
        }
        .menuStyle(.borderlessButton)
    }

    private var intensitySlider: some View {
        HStack(spacing: 3) {
            Text("INT")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
            Slider(
                value: Binding(
                    get: { Double(channel.effectIntensity) },
                    set: { channel.effectIntensity = Float($0) }
                ),
                in: 0...1
            )
            .tint(accentColor)
            Text("\(Int(channel.effectIntensity * 100))")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 22)
        }
    }

    private var keyButton: some View {
        Button {
            showKeySettings.toggle()
            Haptics.tap()
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "key.fill")
                    .font(.system(size: 8))
                Text("KEY")
                    .font(.system(size: 7, weight: .heavy, design: .monospaced))
            }
            .foregroundColor(channel.keySettings.isActive ? .green : .gray)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(
                Rectangle()
                    .fill(channel.keySettings.isActive ? Color.green.opacity(0.15) : Color.white.opacity(0.8))
                    .overlay(
                        Rectangle()
                            .stroke(Color.white.opacity(0.8), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(TactileButtonStyle())
        .popover(isPresented: $showKeySettings) {
            KeySettingsView(channel: channel)
                .frame(width: 280)
        }
    }

    private var pipButton: some View {
        Button {
            showPIPSettings.toggle()
            Haptics.tap()
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "pip")
                    .font(.system(size: 8))
                Text("PIP")
                    .font(.system(size: 7, weight: .heavy, design: .monospaced))
            }
            .foregroundColor(!channel.pipSettings.isDefault ? .cyan : .gray)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(
                Rectangle()
                    .fill(!channel.pipSettings.isDefault ? Color.cyan.opacity(0.15) : Color.white.opacity(0.8))
                    .overlay(
                        Rectangle()
                            .stroke(Color.white.opacity(0.8), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(TactileButtonStyle())
        .popover(isPresented: $showPIPSettings) {
            PIPSettingsView(channel: channel)
                .frame(width: 280)
        }
    }
}

// MARK: - Key Settings

struct KeySettingsView: View {
    let channel: Channel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keying — \(channel.displayName)")
                .font(.headline)

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
                CorrectionSlider(label: "Threshold", value: Binding(
                    get: { channel.keySettings.threshold },
                    set: { channel.keySettings.threshold = $0 }
                ), range: 0...1, tint: .green)

                CorrectionSlider(label: "Softness", value: Binding(
                    get: { channel.keySettings.softness },
                    set: { channel.keySettings.softness = $0 }
                ), range: 0...0.5, tint: .green)

                if channel.keySettings.type == .chromaKey {
                    CorrectionSlider(label: "Key Hue", value: Binding(
                        get: { channel.keySettings.keyHue },
                        set: { channel.keySettings.keyHue = $0 }
                    ), range: 0...360, format: "%.0f", tint: .green)
                }
            }
        }
        .padding()
    }
}

// MARK: - PIP Settings

struct PIPSettingsView: View {
    let channel: Channel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("PIP — \(channel.displayName)")
                    .font(.headline)
                Spacer()
                Button("Reset") {
                    channel.pipSettings.reset()
                }
                .font(.caption)
            }

            CorrectionSlider(label: "Scale", value: Binding(
                get: { channel.pipSettings.scale },
                set: { channel.pipSettings.scale = $0 }
            ), range: 0.1...1, tint: .cyan)

            CorrectionSlider(label: "X Offset", value: Binding(
                get: { channel.pipSettings.offsetX },
                set: { channel.pipSettings.offsetX = $0 }
            ), range: -1...1, tint: .cyan)

            CorrectionSlider(label: "Y Offset", value: Binding(
                get: { channel.pipSettings.offsetY },
                set: { channel.pipSettings.offsetY = $0 }
            ), range: -1...1, tint: .cyan)
        }
        .padding()
    }
}
