import Foundation

/// Cases listed alphabetically by `displayName` so picker UIs that iterate
/// `allCases` render in alphabetical order without needing a custom sort.
/// `metalFunctionName` builds `blend_<rawValue>` — every case needs a matching
/// fragment shader of that name in `BlendModes.metal`.
enum ChannelBlendMode: String, CaseIterable, Identifiable, Codable {
    case add
    case and
    case average
    case color
    case colorBurn
    case colorDodge
    case darken
    case difference
    case divide
    case exclusion
    case glow
    case hardLight
    case hardMix
    case hue
    case lighten
    case linearBurn
    case linearLight
    case luminosity
    case multiply
    case negation
    case normal
    case or
    case overlay
    case phoenix
    case pinLight
    case reflect
    case saturation
    case screen
    case softLight
    case stamp
    case subtract
    case vividLight
    case xor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .add: return "Add"
        case .and: return "AND"
        case .average: return "Average"
        case .color: return "Color"
        case .colorBurn: return "Color Burn"
        case .colorDodge: return "Color Dodge"
        case .darken: return "Darken"
        case .difference: return "Difference"
        case .divide: return "Divide"
        case .exclusion: return "Exclusion"
        case .glow: return "Glow"
        case .hardLight: return "Hard Light"
        case .hardMix: return "Hard Mix"
        case .hue: return "Hue"
        case .lighten: return "Lighten"
        case .linearBurn: return "Linear Burn"
        case .linearLight: return "Linear Light"
        case .luminosity: return "Luminosity"
        case .multiply: return "Multiply"
        case .negation: return "Negation"
        case .normal: return "Normal"
        case .or: return "OR"
        case .overlay: return "Overlay"
        case .phoenix: return "Phoenix"
        case .pinLight: return "Pin Light"
        case .reflect: return "Reflect"
        case .saturation: return "Saturation"
        case .screen: return "Screen"
        case .softLight: return "Soft Light"
        case .stamp: return "Stamp"
        case .subtract: return "Subtract"
        case .vividLight: return "Vivid Light"
        case .xor: return "XOR"
        }
    }

    var metalFunctionName: String {
        "blend_\(rawValue)"
    }
}
