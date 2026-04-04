import SwiftUI

/// Horizontal crossfader between two selected channels (like the Vixid T-bar)
struct CrossfaderView: View {
    let mixerState: MixerState
    @Binding var position: Float  // 0 = channel A, 1 = channel B
    @Binding var channelA: Int
    @Binding var channelB: Int

    var body: some View {
        VStack(spacing: 4) {
            // A/B channel selectors
            HStack(spacing: 0) {
                Text("A:")
                    .font(.system(size: 7, weight: .heavy, design: .monospaced))
                    .foregroundColor(.gray)
                channelPicker(selection: $channelA)
                Spacer()
                Text("B:")
                    .font(.system(size: 7, weight: .heavy, design: .monospaced))
                    .foregroundColor(.gray)
                channelPicker(selection: $channelB)
            }

            // The crossfader track
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 20)
                        .overlay(
                            Rectangle().stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )

                    // Center mark
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 1, height: 14)
                        .offset(x: geo.size.width / 2 - 0.5)

                    // Knob
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 28, height: 18)
                        .shadow(color: .white.opacity(0.2), radius: 3)
                        .offset(x: CGFloat(position) * (geo.size.width - 28))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let raw = Float(value.location.x / geo.size.width)
                            position = max(0, min(1, raw))
                            applyCrossfade()
                        }
                )
            }
            .frame(height: 20)
        }
    }

    private func channelPicker(selection: Binding<Int>) -> some View {
        Picker("", selection: selection) {
            ForEach(0..<4) { i in
                Text("\(i + 1)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tag(i)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 70)
        .scaleEffect(0.75)
    }

    private func applyCrossfade() {
        guard channelA < mixerState.channels.count,
              channelB < mixerState.channels.count,
              channelA != channelB else { return }
        mixerState.channels[channelA].faderLevel = 1.0 - position
        mixerState.channels[channelB].faderLevel = position
    }
}

/// Tap tempo BPM counter
struct TapTempoView: View {
    @Binding var bpm: Float
    @State private var tapTimes: [Date] = []
    private let accent = Color(red: 1.0, green: 0.15, blue: 0.15)

    var body: some View {
        VStack(spacing: 3) {
            // BPM display
            Text(bpm > 0 ? String(format: "%.0f", bpm) : "---")
                .font(.system(size: 16, weight: .heavy, design: .monospaced))
                .foregroundColor(accent)
                .frame(maxWidth: .infinity)

            Text("BPM")
                .font(.system(size: 7, weight: .heavy, design: .monospaced))
                .foregroundColor(accent.opacity(0.5))
                .tracking(1)

            // Tap button
            Button {
                recordTap()
                Haptics.tap()
            } label: {
                Text("TAP")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(accent.opacity(0.12))
                    .overlay(Rectangle().stroke(accent.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(TactileButtonStyle())
        }
    }

    private func recordTap() {
        let now = Date()

        // Reset if more than 2 seconds since last tap
        if let last = tapTimes.last, now.timeIntervalSince(last) > 2.0 {
            tapTimes.removeAll()
        }

        tapTimes.append(now)

        // Keep last 8 taps
        if tapTimes.count > 8 {
            tapTimes.removeFirst()
        }

        // Calculate BPM from average interval
        guard tapTimes.count >= 2 else { return }
        var totalInterval: TimeInterval = 0
        for i in 1..<tapTimes.count {
            totalInterval += tapTimes[i].timeIntervalSince(tapTimes[i - 1])
        }
        let avgInterval = totalInterval / Double(tapTimes.count - 1)
        if avgInterval > 0 {
            bpm = Float(60.0 / avgInterval)
        }
    }
}

/// Preset management view
struct PresetControlView: View {
    let mixerState: MixerState
    let presetManager: PresetManager
    let crossfaderPos: Float
    let bpm: Float

    @State private var showPresets = false
    @State private var presetName = ""

    var body: some View {
        VStack(spacing: 3) {
            // Save button
            Button {
                let name = "Preset \(presetManager.presets.count + 1)"
                let preset = presetManager.capture(from: mixerState, name: name, crossfaderPos: crossfaderPos, bpm: bpm)
                presetManager.save(preset: preset)
                Haptics.success()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 8))
                    Text("SAVE")
                        .font(.system(size: 7, weight: .heavy, design: .monospaced))
                }
                .foregroundColor(.yellow.opacity(0.8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    Rectangle()
                        .fill(Color.yellow.opacity(0.08))
                        .overlay(Rectangle().stroke(Color.yellow.opacity(0.15), lineWidth: 0.5))
                )
            }
            .buttonStyle(TactileButtonStyle())

            // Load button
            Button {
                showPresets.toggle()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 8))
                    Text("LOAD")
                        .font(.system(size: 7, weight: .heavy, design: .monospaced))
                }
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    Rectangle()
                        .fill(Color.white.opacity(0.03))
                        .overlay(Rectangle().stroke(Color.white.opacity(0.06), lineWidth: 0.5))
                )
            }
            .buttonStyle(TactileButtonStyle())
            .popover(isPresented: $showPresets) {
                PresetListView(mixerState: mixerState, presetManager: presetManager)
                    .frame(width: 250, height: 300)
            }

            // Preset count
            Text("\(presetManager.presets.count) saved")
                .font(.system(size: 7, design: .monospaced))
                .foregroundColor(.gray.opacity(0.4))
        }
    }
}

struct PresetListView: View {
    let mixerState: MixerState
    let presetManager: PresetManager

    var body: some View {
        NavigationStack {
            List {
                if presetManager.presets.isEmpty {
                    Text("No presets saved")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(presetManager.presets.enumerated()), id: \.element.id) { index, preset in
                        Button {
                            presetManager.apply(preset, to: mixerState)
                            Haptics.thud()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .font(.system(size: 13, weight: .medium))
                                Text(preset.createdAt, style: .relative)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete { indices in
                        for i in indices { presetManager.delete(at: i) }
                    }
                }
            }
            .navigationTitle("Presets")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
