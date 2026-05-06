import SwiftUI

private let R = Color(red: 1.0, green: 0.15, blue: 0.15)

struct LFOView: View {
    let channel: Channel
    let bpm: Float

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("LFO")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(channel.lfo.isActive ? R : .gray)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { channel.lfo.enabled },
                    set: { channel.lfo.enabled = $0 }
                ))
                .labelsHidden()
                .tint(R)
            }

            if channel.lfo.enabled {
                // Shape selector
                HStack(spacing: 3) {
                    ForEach(LFOShape.allCases) { shape in
                        Button {
                            channel.lfo.shape = shape
                            Haptics.tap()
                        } label: {
                            VStack(spacing: 1) {
                                Image(systemName: shape.icon).font(.system(size: 9))
                                Text(shape.displayName).font(.system(size: 5, weight: .heavy, design: .monospaced))
                            }
                            .foregroundColor(channel.lfo.shape == shape ? .white : .gray)
                            .frame(maxWidth: .infinity).padding(.vertical, 4)
                            .background(channel.lfo.shape == shape ? R.opacity(0.25) : Color.white.opacity(0.05))
                            .overlay(
                                VStack { Rectangle().fill(channel.lfo.shape == shape ? R : Color.clear).frame(height: 2); Spacer() }
                            )
                        }
                        .buttonStyle(TactileButtonStyle())
                    }
                }

                // Target — flat button grid (iPad Menu pickers misbehave inside nested panels)
                VStack(alignment: .leading, spacing: 4) {
                    Text("TARGET")
                        .font(.system(size: 7, weight: .black, design: .monospaced))
                        .foregroundColor(.gray)
                    let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
                    LazyVGrid(columns: cols, spacing: 3) {
                        ForEach(LFOTarget.allCases) { t in
                            Button {
                                channel.lfo.target = t
                                Haptics.tap()
                            } label: {
                                Text(t.displayName)
                                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .foregroundColor(channel.lfo.target == t ? .white : .gray)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                                    .background(channel.lfo.target == t ? R.opacity(0.35) : Color.white.opacity(0.05))
                                    .overlay(
                                        Rectangle().stroke(channel.lfo.target == t ? R : Color.white.opacity(0.08), lineWidth: 0.5)
                                    )
                            }
                            .buttonStyle(TactileButtonStyle())
                        }
                    }
                }

                // Rate
                HStack(spacing: 4) {
                    Text("RATE")
                        .font(.system(size: 7, weight: .heavy, design: .monospaced))
                        .foregroundColor(.gray)
                        .frame(width: 30, alignment: .trailing)
                    Slider(
                        value: Binding(get: { Double(channel.lfo.rate) }, set: { channel.lfo.rate = Float($0) }),
                        in: 0.01...2.7
                    ).tint(R)
                    Text(String(format: "%.2fHz", channel.lfo.rate))
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 40)
                }

                // BPM sync
                HStack {
                    Toggle("BPM SYNC", isOn: Binding(
                        get: { channel.lfo.useBPM },
                        set: { channel.lfo.useBPM = $0 }
                    ))
                    .font(.system(size: 7, weight: .heavy, design: .monospaced))
                    .foregroundColor(.gray)
                    .tint(R)

                    if channel.lfo.useBPM {
                        Text("\(Int(bpm))bpm")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(R.opacity(0.6))
                    }
                }

                if channel.lfo.useBPM {
                    HStack(spacing: 4) {
                        Text("DIV")
                            .font(.system(size: 7, weight: .heavy, design: .monospaced))
                            .foregroundColor(.gray)
                            .frame(width: 30, alignment: .trailing)
                        Slider(
                            value: Binding(get: { Double(channel.lfo.bpmDivision) }, set: { channel.lfo.bpmDivision = Float($0) }),
                            in: 0.25...4.0, step: 0.25
                        ).tint(R)
                        Text(String(format: "%.2fx", channel.lfo.bpmDivision))
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 40)
                    }
                }

                // Depth
                HStack(spacing: 4) {
                    Text("DEPTH")
                        .font(.system(size: 7, weight: .heavy, design: .monospaced))
                        .foregroundColor(.gray)
                        .frame(width: 30, alignment: .trailing)
                    Slider(
                        value: Binding(get: { Double(channel.lfo.depth) }, set: { channel.lfo.depth = Float($0) }),
                        in: 0...1
                    ).tint(R)
                    Text("\(Int(channel.lfo.depth * 100))%")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 40)
                }

                // Min/Max range
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Text("MIN")
                            .font(.system(size: 7, weight: .heavy, design: .monospaced))
                            .foregroundColor(.gray)
                        Slider(
                            value: Binding(get: { Double(channel.lfo.min) }, set: { channel.lfo.min = Float($0) }),
                            in: 0...1
                        ).tint(R)
                    }
                    HStack(spacing: 4) {
                        Text("MAX")
                            .font(.system(size: 7, weight: .heavy, design: .monospaced))
                            .foregroundColor(.gray)
                        Slider(
                            value: Binding(get: { Double(channel.lfo.max) }, set: { channel.lfo.max = Float($0) }),
                            in: 0...1
                        ).tint(R)
                    }
                }

                // Live output meter
                HStack(spacing: 4) {
                    Text("OUT")
                        .font(.system(size: 7, weight: .heavy, design: .monospaced))
                        .foregroundColor(.gray)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.white.opacity(0.06))
                            Rectangle().fill(R)
                                .frame(width: geo.size.width * CGFloat(channel.lfo.currentValue))
                        }
                    }
                    .frame(height: 6)
                    Text("\(Int(channel.lfo.currentValue * 100))%")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 30)
                }
            }
        }
    }
}

/// Master-section LFO that drives `mixerState.masterLevel`. Same control set
/// as the per-channel LFO, minus the target picker — the master LFO only
/// modulates the master output multiplier.
struct MasterLFOView: View {
    @Bindable var mixerState: MixerState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MASTER LFO")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundColor(mixerState.masterLFO.isActive ? R : .gray)
                Spacer()
                Toggle("", isOn: $mixerState.masterLFO.enabled)
                    .labelsHidden().tint(R)
            }

            if mixerState.masterLFO.enabled {
                // Target — tells the LFO what to drive
                VStack(alignment: .leading, spacing: 4) {
                    Text("TARGET")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(.gray)
                    HStack(spacing: 4) {
                        ForEach(MasterLFOTarget.allCases) { t in
                            Button {
                                mixerState.masterLFOTarget = t
                                Haptics.tap()
                            } label: {
                                Text(t.displayName)
                                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                    .foregroundColor(mixerState.masterLFOTarget == t ? .white : .gray)
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background(mixerState.masterLFOTarget == t ? R.opacity(0.35) : Color.white.opacity(0.05))
                                    .overlay(Rectangle().stroke(mixerState.masterLFOTarget == t ? R : Color.white.opacity(0.08), lineWidth: 0.5))
                            }
                            .buttonStyle(TactileButtonStyle())
                        }
                    }
                }

                // Shape
                HStack(spacing: 4) {
                    ForEach(LFOShape.allCases) { shape in
                        Button {
                            mixerState.masterLFO.shape = shape
                            Haptics.tap()
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: shape.icon).font(.system(size: 12))
                                Text(shape.displayName).font(.system(size: 7, weight: .heavy, design: .monospaced))
                            }
                            .foregroundColor(mixerState.masterLFO.shape == shape ? .white : .gray)
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .background(mixerState.masterLFO.shape == shape ? R.opacity(0.3) : Color.white.opacity(0.05))
                            .overlay(VStack { Rectangle().fill(mixerState.masterLFO.shape == shape ? R : Color.clear).frame(height: 2); Spacer() })
                        }
                        .buttonStyle(TactileButtonStyle())
                    }
                }

                // Rate
                HStack(spacing: 6) {
                    Text("RATE").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.gray).frame(width: 40, alignment: .trailing)
                    Slider(value: $mixerState.masterLFO.rate, in: 0.01...2.7).tint(R)
                    Text(String(format: "%.2fHz", mixerState.masterLFO.rate))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8)).frame(width: 50)
                }

                // BPM sync
                HStack {
                    Toggle("BPM SYNC", isOn: $mixerState.masterLFO.useBPM)
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundColor(.gray).tint(R)
                    if mixerState.masterLFO.useBPM {
                        Spacer()
                        Text("\(Int(mixerState.bpm))bpm")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(R.opacity(0.7))
                    }
                }

                if mixerState.masterLFO.useBPM {
                    HStack(spacing: 6) {
                        Text("DIV").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.gray).frame(width: 40, alignment: .trailing)
                        Slider(value: $mixerState.masterLFO.bpmDivision, in: 0.25...4.0, step: 0.25).tint(R)
                        Text(String(format: "%.2fx", mixerState.masterLFO.bpmDivision))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8)).frame(width: 50)
                    }
                }

                // Depth
                HStack(spacing: 6) {
                    Text("DEPTH").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.gray).frame(width: 40, alignment: .trailing)
                    Slider(value: $mixerState.masterLFO.depth, in: 0...1).tint(R)
                    Text("\(Int(mixerState.masterLFO.depth * 100))%")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8)).frame(width: 50)
                }

                // Min / Max range
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Text("MIN").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.gray)
                        Slider(value: $mixerState.masterLFO.min, in: 0...1).tint(R)
                    }
                    HStack(spacing: 4) {
                        Text("MAX").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.gray)
                        Slider(value: $mixerState.masterLFO.max, in: 0...1).tint(R)
                    }
                }

                // Live output meter
                HStack(spacing: 6) {
                    Text("OUT").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.gray)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.white.opacity(0.06))
                            Rectangle().fill(R).frame(width: geo.size.width * CGFloat(mixerState.masterLFO.currentValue))
                        }
                    }
                    .frame(height: 8)
                    Text("\(Int(mixerState.masterLFO.currentValue * 100))%")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8)).frame(width: 36)
                }
            }
        }
    }
}
