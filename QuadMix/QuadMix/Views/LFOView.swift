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

                // Target
                VStack(alignment: .leading, spacing: 2) {
                    Text("TARGET")
                        .font(.system(size: 7, weight: .black, design: .monospaced))
                        .foregroundColor(.gray)
                    Picker("", selection: Binding(
                        get: { channel.lfo.target },
                        set: { channel.lfo.target = $0 }
                    )) {
                        ForEach(LFOTarget.allCases) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(R)
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
