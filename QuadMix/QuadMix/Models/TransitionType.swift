import Foundation

enum TransitionType: String, CaseIterable, Identifiable, Codable {
    case mix
    case cut
    case dipToBlack
    case wipeLeft
    case wipeRight
    case wipeUp
    case wipeDown
    case wipeDiagTL
    case wipeDiagTR
    case wipeCircle
    case wipeDiamond
    case wipeBlinds
    case wipeStar

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mix: return "Mix"
        case .cut: return "Cut"
        case .dipToBlack: return "Dip to Black"
        case .wipeLeft: return "Wipe Left"
        case .wipeRight: return "Wipe Right"
        case .wipeUp: return "Wipe Up"
        case .wipeDown: return "Wipe Down"
        case .wipeDiagTL: return "Wipe Diag TL"
        case .wipeDiagTR: return "Wipe Diag TR"
        case .wipeCircle: return "Circle Wipe"
        case .wipeDiamond: return "Diamond Wipe"
        case .wipeBlinds: return "Blinds"
        case .wipeStar: return "Star Wipe"
        }
    }

    var icon: String {
        switch self {
        case .mix: return "arrow.left.arrow.right"
        case .cut: return "scissors"
        case .dipToBlack: return "moon.fill"
        case .wipeLeft: return "arrow.left"
        case .wipeRight: return "arrow.right"
        case .wipeUp: return "arrow.up"
        case .wipeDown: return "arrow.down"
        case .wipeDiagTL: return "arrow.up.left"
        case .wipeDiagTR: return "arrow.up.right"
        case .wipeCircle: return "circle"
        case .wipeDiamond: return "diamond"
        case .wipeBlinds: return "line.3.horizontal"
        case .wipeStar: return "star.fill"
        }
    }

    var isWipe: Bool {
        switch self {
        case .mix, .cut, .dipToBlack: return false
        default: return true
        }
    }

    /// Wipe direction/type passed to shader (0-10)
    var wipeDirection: Int {
        switch self {
        case .wipeLeft: return 0
        case .wipeRight: return 1
        case .wipeUp: return 2
        case .wipeDown: return 3
        case .wipeDiagTL: return 4
        case .wipeDiagTR: return 5
        case .wipeCircle: return 6
        case .wipeDiamond: return 7
        case .wipeBlinds: return 8
        case .wipeStar: return 9
        default: return 0
        }
    }
}

struct TransitionConfig: Codable {
    var type: TransitionType = .mix
    var duration: TimeInterval = 1.0
}
