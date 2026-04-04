import Foundation

enum EffectType: String, CaseIterable, Identifiable, Codable {
    case none
    case freeze
    case mirror
    case mirrorV
    case invert
    case mosaic
    case strobe
    case rgbSplit
    case posterize
    case blur
    case solarize
    case edges
    case datamosh
    case scanlines
    case kaleidoscope
    case halftone
    case feedback

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .freeze: return "Freeze"
        case .mirror: return "Mirror H"
        case .mirrorV: return "Mirror V"
        case .invert: return "Invert"
        case .mosaic: return "Mosaic"
        case .strobe: return "Strobe"
        case .rgbSplit: return "RGB Split"
        case .posterize: return "Posterize"
        case .blur: return "Blur"
        case .solarize: return "Solarize"
        case .edges: return "Edges"
        case .datamosh: return "Datamosh"
        case .scanlines: return "Scanlines"
        case .kaleidoscope: return "Kaleido"
        case .halftone: return "Halftone"
        case .feedback: return "Feedback"
        }
    }

    var icon: String {
        switch self {
        case .none: return "xmark"
        case .freeze: return "pause.circle"
        case .mirror: return "arrow.left.and.right"
        case .mirrorV: return "arrow.up.and.down"
        case .invert: return "circle.lefthalf.filled"
        case .mosaic: return "square.grid.3x3"
        case .strobe: return "bolt.fill"
        case .rgbSplit: return "camera.filters"
        case .posterize: return "paintbrush"
        case .blur: return "drop.halffull"
        case .solarize: return "sun.max.trianglebadge.exclamationmark"
        case .edges: return "square.dashed"
        case .datamosh: return "lines.measurement.horizontal"
        case .scanlines: return "line.3.horizontal"
        case .kaleidoscope: return "star.leadinghalf.filled"
        case .halftone: return "circle.dotted"
        case .feedback: return "arrow.2.squarepath"
        }
    }

    var metalFunctionName: String? {
        switch self {
        case .none, .freeze: return nil
        case .mirror: return "effect_mirror_h"
        case .mirrorV: return "effect_mirror_v"
        case .invert: return "effect_invert"
        case .mosaic: return "effect_mosaic"
        case .strobe: return "effect_strobe"
        case .rgbSplit: return "effect_rgb_split"
        case .posterize: return "effect_posterize"
        case .blur: return "effect_blur"
        case .solarize: return "effect_solarize"
        case .edges: return "effect_edges"
        case .datamosh: return "effect_datamosh"
        case .scanlines: return "effect_scanlines"
        case .kaleidoscope: return "effect_kaleidoscope"
        case .halftone: return "effect_halftone"
        case .feedback: return "effect_feedback"
        }
    }

    var isFeedback: Bool { self == .feedback }

    var param1Label: String {
        switch self {
        case .none, .freeze: return "Intensity"
        case .mirror, .mirrorV: return "Mirror Amount"
        case .invert: return "Invert Amount"
        case .mosaic: return "Block Size"
        case .strobe: return "Strobe Speed"
        case .rgbSplit: return "Split Offset"
        case .posterize: return "Crush Amount"
        case .blur: return "Blur Radius"
        case .solarize: return "Threshold"
        case .edges: return "Edge Strength"
        case .datamosh: return "Shift Amount"
        case .scanlines: return "Line Density"
        case .kaleidoscope: return "Segments"
        case .halftone: return "Dot Size"
        case .feedback: return "Trail Amount"
        }
    }

    var hasParam2: Bool {
        switch self {
        case .rgbSplit, .blur, .strobe, .datamosh, .scanlines, .solarize, .kaleidoscope, .feedback: return true
        default: return false
        }
    }

    var param2Label: String {
        switch self {
        case .rgbSplit: return "Vertical Split"
        case .blur: return "Direction Bias"
        case .strobe: return "Duty Cycle"
        case .datamosh: return "Block Height"
        case .scanlines: return "Brightness"
        case .solarize: return "Curve"
        case .kaleidoscope: return "Rotation"
        case .feedback: return "Zoom/Rotate"
        default: return ""
        }
    }

    var defaultParam2: Float {
        switch self {
        case .datamosh: return 0.4
        case .scanlines: return 0.5
        case .strobe: return 0.3
        case .kaleidoscope: return 0.0
        case .solarize: return 0.3
        case .feedback: return 0.3
        default: return 0.0
        }
    }

    var defaultIntensity: Float {
        switch self {
        case .mosaic: return 0.3
        case .strobe: return 0.4
        case .blur: return 0.5
        case .rgbSplit: return 0.3
        case .posterize: return 0.4
        case .mirror, .mirrorV: return 1.0
        case .invert: return 1.0
        case .solarize: return 0.5
        case .edges: return 0.5
        case .datamosh: return 0.6
        case .scanlines: return 0.5
        case .kaleidoscope: return 0.3
        case .halftone: return 0.4
        case .feedback: return 0.7
        default: return 0.5
        }
    }
}

enum KeyType: String, CaseIterable, Identifiable, Codable {
    case none
    case lumaKey
    case chromaKey

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .lumaKey: return "Luma Key"
        case .chromaKey: return "Chroma Key"
        }
    }
}

struct KeySettings: Codable {
    var type: KeyType = .none
    var threshold: Float = 0.3
    var softness: Float = 0.1
    var keyHue: Float = 120.0

    var isActive: Bool { type != .none }
}

struct PIPSettings: Codable {
    var scale: Float = 1.0
    var offsetX: Float = 0.0
    var offsetY: Float = 0.0

    var isDefault: Bool {
        abs(scale - 1.0) < 0.01 && abs(offsetX) < 0.01 && abs(offsetY) < 0.01
    }

    mutating func reset() {
        scale = 1.0
        offsetX = 0.0
        offsetY = 0.0
    }
}

struct EffectUniforms {
    var param1: Float
    var param2: Float
    var time: Float
    var padding: Float
}
