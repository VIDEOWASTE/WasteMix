import SwiftUI

/// Per-channel audio reactivity EQ panel.
/// Each channel gets its own lane: pick which frequency bands drive it,
/// set gain per band, choose what it controls (opacity or FX intensity).
struct AudioReactView: View {
    let channel: Channel
    let audioEngine: AudioEngine
    var accentColor: Color = .blue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("Audio React — \(channel.displayName)")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { channel.audioReact.enabled },
                    set: { channel.audioReact.enabled = $0 }
                ))
                .labelsHidden()
                .tint(accentColor)
            }

            // Surface mic-input problems explicitly. Without this, audio
            // react silently produces zeros when permission is denied or
            // the host has no input — looks like an app bug.
            if let warning = micWarning {
                Text(warning)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.orange)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(4)
            }

            if channel.audioReact.enabled {
                // Target picker
                VStack(alignment: .leading, spacing: 3) {
                    Text("DRIVES").font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundColor(.gray)
                    Picker("Target", selection: Binding(
                        get: { channel.audioReact.target },
                        set: { channel.audioReact.target = $0 }
                    )) {
                        ForEach(AudioReactTarget.allCases) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // EQ bands — 7 vertical sliders
                VStack(alignment: .leading, spacing: 4) {
                    Text("FREQUENCY BANDS").font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundColor(.gray)

                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(0..<7) { band in
                            bandColumn(band)
                        }
                    }
                    .frame(height: 130)
                }

                // Live meter
                VStack(alignment: .leading, spacing: 3) {
                    Text("LIVE INPUT").font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundColor(.gray)

                    HStack(spacing: 2) {
                        ForEach(0..<7) { band in
                            let level = audioEngine.bandLevel(at: band)
                            let gain = channel.audioReact.bandGains[band]
                            VStack(spacing: 1) {
                                GeometryReader { geo in
                                    VStack(spacing: 0) {
                                        Spacer()
                                        Rectangle()
                                            .fill(gain > 0.01 ? accentColor : Color.gray)
                                            .frame(height: geo.size.height * CGFloat(level * gain))
                                    }
                                }
                                .frame(height: 30)

                                Text(AudioEngine.bandNames[band].prefix(3).uppercased())
                                    .font(.system(size: 5, weight: .bold, design: .monospaced))
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }

                    // Output value bar
                    HStack(spacing: 4) {
                        Text("OUT").font(.system(size: 7, weight: .heavy, design: .monospaced)).foregroundColor(.gray)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.white.opacity(0.8))
                                Rectangle().fill(accentColor)
                                    .frame(width: geo.size.width * CGFloat(channel.audioReactCurrent))
                            }
                        }
                        .frame(height: 8)
                        Text("\(Int(channel.audioReactCurrent * 100))%")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 30)
                    }
                }

                Divider()

                // Smoothing + range
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SMOOTH").font(.system(size: 7, weight: .heavy, design: .monospaced)).foregroundColor(.gray)
                        Slider(
                            value: Binding(get: { Double(channel.audioReact.smoothing) }, set: { channel.audioReact.smoothing = Float($0) }),
                            in: 0...0.95
                        ).tint(accentColor)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FLOOR").font(.system(size: 7, weight: .heavy, design: .monospaced)).foregroundColor(.gray)
                        Slider(
                            value: Binding(get: { Double(channel.audioReact.floor) }, set: { channel.audioReact.floor = Float($0) }),
                            in: 0...1
                        ).tint(accentColor)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CEIL").font(.system(size: 7, weight: .heavy, design: .monospaced)).foregroundColor(.gray)
                        Slider(
                            value: Binding(get: { Double(channel.audioReact.ceiling) }, set: { channel.audioReact.ceiling = Float($0) }),
                            in: 0...1
                        ).tint(accentColor)
                    }
                }

                // Quick presets — wrapped to two rows so they can be a real
                // size instead of fighting for inline space.
                VStack(alignment: .leading, spacing: 6) {
                    Text("PRESETS").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.gray)
                    HStack(spacing: 6) {
                        eqPresetBtn("KICK") { setGains([1, 0.8, 0, 0, 0, 0, 0]) }
                        eqPresetBtn("BASS") { setGains([0.5, 1, 0.5, 0, 0, 0, 0]) }
                        eqPresetBtn("VOCAL") { setGains([0, 0, 0.3, 1, 0.8, 0.3, 0]) }
                        eqPresetBtn("HATS") { setGains([0, 0, 0, 0, 0.3, 0.8, 1]) }
                    }
                    HStack(spacing: 6) {
                        eqPresetBtn("FULL") { setGains([1, 1, 1, 1, 1, 1, 1]) }
                        eqPresetBtn("OFF") { setGains([0, 0, 0, 0, 0, 0, 0]) }
                        Spacer()
                    }
                }
            }
        }
        .padding()
    }

    // MARK: - Band Column

    private func bandColumn(_ band: Int) -> some View {
        VStack(spacing: 2) {
            // Band name
            Text(AudioEngine.bandNames[band].prefix(3).uppercased())
                .font(.system(size: 6, weight: .heavy, design: .monospaced))
                .foregroundColor(.gray)

            // Vertical gain slider
            GeometryReader { geo in
                let gain = channel.audioReact.bandGains[band]
                ZStack(alignment: .bottom) {
                    // Track
                    Rectangle()
                        .fill(Color.white.opacity(0.8))

                    // Fill
                    Rectangle()
                        .fill(accentColor.opacity(0.5 + Double(gain) * 0.5))
                        .frame(height: geo.size.height * CGFloat(gain))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let val = 1.0 - Float(v.location.y / geo.size.height)
                            channel.audioReact.bandGains[band] = max(0, min(1, val))
                        }
                )
            }

            // Range label
            Text(AudioEngine.bandRanges[band])
                .font(.system(size: 4, weight: .medium, design: .monospaced))
                .foregroundColor(.gray)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            // Gain value
            Text("\(Int(channel.audioReact.bandGains[band] * 100))")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
    }

    private func eqPresetBtn(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundColor(accentColor)
                .frame(minWidth: 64)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Rectangle().fill(accentColor.opacity(0.15)))
                .overlay(Rectangle().stroke(accentColor.opacity(0.4), lineWidth: 0.5))
        }.buttonStyle(TactileButtonStyle())
    }

    private func setGains(_ gains: [Float]) {
        for i in 0..<min(7, gains.count) {
            channel.audioReact.bandGains[i] = gains[i]
        }
        Haptics.tap()
    }

    /// Human-readable warning for the input state — returns nil when audio
    /// is healthy. Phrasing differs slightly per-platform: iPad users open
    /// Settings, Mac users open System Settings ▸ Privacy & Security.
    private var micWarning: String? {
        switch audioEngine.inputState {
        case .running, .idle:
            return nil
        case .permissionDenied:
            #if targetEnvironment(macCatalyst)
            return "MIC ACCESS DENIED — System Settings ▸ Privacy & Security ▸ Microphone"
            #else
            return "MIC ACCESS DENIED — Settings ▸ WasteMix ▸ Microphone"
            #endif
        case .noInputFormat:
            return "NO AUDIO INPUT FOUND — connect a mic / interface"
        case .startFailed:
            return "AUDIO ENGINE FAILED TO START"
        }
    }
}
