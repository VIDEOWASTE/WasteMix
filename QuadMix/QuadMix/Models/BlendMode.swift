import Foundation

enum ChannelBlendMode: String, CaseIterable, Identifiable, Codable {
    // Standard
    case normal
    case add
    case multiply
    case screen
    case overlay
    // Contrast
    case hardLight
    case softLight
    case colorDodge
    case colorBurn
    // Comparative
    case difference
    case exclusion
    case darken
    case lighten
    // Vixid specials
    case subtract
    case average
    // Logic / math
    case and
    case or
    case xor
    case negation

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .add: return "Add"
        case .multiply: return "Multiply"
        case .screen: return "Screen"
        case .overlay: return "Overlay"
        case .hardLight: return "Hard Light"
        case .softLight: return "Soft Light"
        case .colorDodge: return "Color Dodge"
        case .colorBurn: return "Color Burn"
        case .difference: return "Difference"
        case .exclusion: return "Exclusion"
        case .darken: return "Darken"
        case .lighten: return "Lighten"
        case .subtract: return "Subtract"
        case .average: return "Average"
        case .and: return "AND"
        case .or: return "OR"
        case .xor: return "XOR"
        case .negation: return "Negation"
        }
    }

    var metalFunctionName: String {
        "blend_\(rawValue)"
    }
}
