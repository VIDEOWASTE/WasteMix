import SwiftUI

/// Short labels for transition types
extension TransitionType {
    var shortLabel: String {
        switch self {
        case .mix: return "MIX"
        case .cut: return "CUT"
        case .dipToBlack: return "DIP"
        case .wipeLeft: return "W\u{2190}"
        case .wipeRight: return "W\u{2192}"
        case .wipeUp: return "W\u{2191}"
        case .wipeDown: return "W\u{2193}"
        case .wipeDiagTL: return "W\u{2196}"
        case .wipeDiagTR: return "W\u{2197}"
        case .wipeCircle: return "W\u{25CB}"
        case .wipeDiamond: return "W\u{25C7}"
        case .wipeBlinds: return "W\u{2261}"
        case .wipeStar: return "W\u{2605}"
        }
    }
}

struct TransitionControlView: View {
    let channel: Channel
    let transitionEngine: TransitionEngine
    var accentColor: Color = .blue

    var body: some View {
        VStack(spacing: 5) {
            // Transition type dropdown
            transitionPicker

            // Duration + AUTO in a row
            HStack(spacing: 4) {
                durationStepper
                autoButton
            }

            // Progress bar during transition
            if channel.isTransitioning {
                progressBar
            }
        }
    }

    private var transitionPicker: some View {
        Menu {
            Section("Fades") {
                transButton(.mix)
                transButton(.cut)
                transButton(.dipToBlack)
            }
            Section("Wipes") {
                transButton(.wipeLeft)
                transButton(.wipeRight)
                transButton(.wipeUp)
                transButton(.wipeDown)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: channel.transitionConfig.type.icon)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(accentColor)
                Text(channel.transitionConfig.type.shortLabel)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        Rectangle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .menuStyle(.borderlessButton)
    }

    private func transButton(_ type: TransitionType) -> some View {
        Button {
            channel.transitionConfig.type = type
            Haptics.tap()
        } label: {
            Label {
                Text(type.displayName)
            } icon: {
                if type == channel.transitionConfig.type {
                    Image(systemName: "checkmark")
                } else {
                    Image(systemName: type.icon)
                }
            }
        }
    }

    private var durationStepper: some View {
        HStack(spacing: 2) {
            Button {
                channel.transitionConfig.duration = max(0.1, channel.transitionConfig.duration - 0.25)
                Haptics.tick()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundColor(.gray)
                    .frame(width: 18, height: 22)
                    .background(Color.white.opacity(0.06))
                    
            }
            .buttonStyle(TactileButtonStyle())

            Text(String(format: "%.1f", channel.transitionConfig.duration))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .frame(minWidth: 22)

            Button {
                channel.transitionConfig.duration = min(5.0, channel.transitionConfig.duration + 0.25)
                Haptics.tick()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundColor(.gray)
                    .frame(width: 18, height: 22)
                    .background(Color.white.opacity(0.06))
                    
            }
            .buttonStyle(TactileButtonStyle())
        }
    }

    private var autoButton: some View {
        Button {
            if channel.isTransitioning {
                transitionEngine.cancelTransition(for: channel)
                Haptics.warning()
            } else {
                let target: Float = channel.faderLevel > 0.5 ? 0.0 : 1.0
                transitionEngine.triggerTransition(channel: channel, targetLevel: target)
                Haptics.thud()
            }
        } label: {
            Text(channel.isTransitioning ? "STOP" : "AUTO")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    Rectangle()
                        .fill(channel.isTransitioning ? Color.orange.opacity(0.8) : accentColor.opacity(0.6))
                )
                .overlay(
                    Rectangle()
                        .stroke(channel.isTransitioning ? Color.orange : accentColor.opacity(0.6), lineWidth: 1)
                )
        }
        .buttonStyle(TactileButtonStyle())
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.08))
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: geo.size.width * CGFloat(channel.transitionProgress))
            }
        }
        .frame(height: 3)
    }
}
