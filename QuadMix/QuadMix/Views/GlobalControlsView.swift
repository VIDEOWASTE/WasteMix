import SwiftUI

struct GlobalControlsView: View {
    let mixerState: MixerState
    @State private var showGlobalColor = false
    @State private var crossfaderPos: Float = 0.5
    @State private var crossfaderA: Int = 0
    @State private var crossfaderB: Int = 1
    @State private var bpm: Float = 120
    @State private var presetManager = PresetManager()

    var body: some View {
        VStack(spacing: 0) {
            masterHeader
            cellBorder
            crossfaderCell
            cellBorder
            tapTempoCell
            cellBorder
            globalColorCell
            cellBorder
            quickActionsCell
            cellBorder
            presetCell
            cellBorder
            outputInfoCell
        }
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
        .clipShape(Rectangle())
        .overlay(
            Rectangle()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var masterHeader: some View {
        Text("MASTER")
            .font(.system(size: 9, weight: .heavy, design: .monospaced))
            .foregroundColor(.white.opacity(0.6))
            .tracking(2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.03))
    }

    private var crossfaderCell: some View {
        CrossfaderView(
            mixerState: mixerState,
            position: $crossfaderPos,
            channelA: $crossfaderA,
            channelB: $crossfaderB
        )
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
    }

    private var tapTempoCell: some View {
        TapTempoView(bpm: $bpm)
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
    }

    private var globalColorCell: some View {
        let isActive = !mixerState.globalColorCorrection.isIdentity
        let tint: Color = .orange

        return Button {
            showGlobalColor.toggle()
            Haptics.tap()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isActive ? .white : tint)
                Text(isActive ? "COLOR ON" : "GLOBAL COLOR")
                    .font(.system(size: 7, weight: .heavy, design: .monospaced))
                    .foregroundColor(isActive ? .white : tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                if isActive {
                    Circle().fill(tint).frame(width: 5, height: 5)
                        .shadow(color: tint.opacity(0.6), radius: 3)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
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
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .popover(isPresented: $showGlobalColor) {
            ColorCorrectionView(
                title: "Global Color",
                correction: Binding(
                    get: { mixerState.globalColorCorrection },
                    set: { mixerState.globalColorCorrection = $0 }
                )
            )
            .frame(width: 320)
        }
    }

    private var quickActionsCell: some View {
        VStack(spacing: 3) {
            quickButton(icon: "moon.fill", label: "BLACK", fg: .red.opacity(0.8)) {
                for ch in mixerState.channels { ch.faderLevel = 0 }
                Haptics.bump()
            }
            quickButton(icon: "sun.max.fill", label: "FULL", fg: .yellow.opacity(0.8)) {
                for ch in mixerState.channels {
                    if ch.source != nil { ch.faderLevel = 1.0 }
                }
                Haptics.thud()
            }
            quickButton(icon: "arrow.counterclockwise", label: "RESET", fg: .gray.opacity(0.6)) {
                for ch in mixerState.channels {
                    ch.blendMode = .normal
                    ch.effectType = .none
                    ch.isFrozen = false
                    ch.keySettings = KeySettings()
                    ch.pipSettings = PIPSettings()
                }
                Haptics.thud()
            }
        }
        .padding(5)
    }

    private var presetCell: some View {
        PresetControlView(
            mixerState: mixerState,
            presetManager: presetManager,
            crossfaderPos: crossfaderPos,
            bpm: bpm
        )
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
    }

    private var outputInfoCell: some View {
        HStack(spacing: 3) {
            Circle().fill(Color.green.opacity(0.5)).frame(width: 4, height: 4)
            Text("\(Int(mixerState.programResolution.width))x\(Int(mixerState.programResolution.height))")
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundColor(.green.opacity(0.4))
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
    }

    private var cellBorder: some View {
        Rectangle().fill(Color.white.opacity(0.04)).frame(height: 0.5)
    }

    private func quickButton(icon: String, label: String, fg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9))
                Text(label).font(.system(size: 7, weight: .heavy, design: .monospaced))
            }
            .foregroundColor(fg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                Rectangle().fill(Color.white.opacity(0.03))
                    .overlay(Rectangle().stroke(Color.white.opacity(0.05), lineWidth: 0.5))
            )
        }
        .buttonStyle(TactileButtonStyle())
    }
}
