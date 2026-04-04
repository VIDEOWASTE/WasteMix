import SwiftUI

/// Short labels for compact display
extension ChannelBlendMode {
    var shortLabel: String {
        switch self {
        case .normal: return "NORM"
        case .add: return "ADD"
        case .multiply: return "MULT"
        case .screen: return "SCRN"
        case .overlay: return "OVLY"
        case .difference: return "DIFF"
        case .exclusion: return "EXCL"
        case .hardLight: return "HLIT"
        case .softLight: return "SLIT"
        case .colorDodge: return "DODG"
        case .colorBurn: return "BURN"
        case .darken: return "DARK"
        case .lighten: return "LITE"
        case .subtract: return "SUB"
        case .average: return "AVG"
        case .xor: return "XOR"
        }
    }
}

/// Compact dropdown-style blend mode picker
struct BlendModePickerView: View {
    @Binding var selectedMode: ChannelBlendMode
    var accentColor: Color = .blue

    var body: some View {
        Menu {
            Section("Standard") {
                blendButton(.normal)
                blendButton(.add)
                blendButton(.multiply)
                blendButton(.screen)
                blendButton(.overlay)
            }
            Section("Contrast") {
                blendButton(.hardLight)
                blendButton(.softLight)
                blendButton(.colorDodge)
                blendButton(.colorBurn)
            }
            Section("Comparative") {
                blendButton(.difference)
                blendButton(.exclusion)
                blendButton(.darken)
                blendButton(.lighten)
            }
            Section("Special") {
                blendButton(.subtract)
                blendButton(.average)
                blendButton(.xor)
            }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 5, height: 5)
                Text(selectedMode.shortLabel)
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                Rectangle()
                    .fill(accentColor.opacity(0.15))
                    .overlay(
                        Rectangle()
                            .stroke(accentColor.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .menuStyle(.borderlessButton)
    }

    private func blendButton(_ mode: ChannelBlendMode) -> some View {
        Button {
            selectedMode = mode
            Haptics.thud()
        } label: {
            Label {
                Text(mode.displayName)
            } icon: {
                if mode == selectedMode {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
}

/// Shared button style with scale feedback for tactile feel
struct TactileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
