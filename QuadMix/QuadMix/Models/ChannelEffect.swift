import Foundation

enum EffectType: String, CaseIterable, Identifiable, Codable {
    case none
    case freeze
    case rotate
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
        case .rotate: return "Rotate"
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
        case .rotate: return "rotate.right.fill"
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
        case .rotate: return "effect_rotate"
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
        case .rotate: return "Angle"
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
    /// When false (default), pixels brighter than `threshold` survive and
    /// dark pixels are knocked out — i.e. "key out the blacks." When true,
    /// the inverse: dark pixels survive and brights become transparent
    /// — useful for keying out a white background or knocking out
    /// hot-spots / specular highlights.
    var invert: Bool = false

    var isActive: Bool { type != .none }

    private enum CodingKeys: String, CodingKey {
        case type, threshold, softness, keyHue, invert
    }

    // Backwards-compat decoder so presets saved before `invert` existed
    // still load (default to false, the prior behavior).
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(KeyType.self, forKey: .type) ?? .none
        threshold = try c.decodeIfPresent(Float.self, forKey: .threshold) ?? 0.3
        softness = try c.decodeIfPresent(Float.self, forKey: .softness) ?? 0.1
        keyHue = try c.decodeIfPresent(Float.self, forKey: .keyHue) ?? 120.0
        invert = try c.decodeIfPresent(Bool.self, forKey: .invert) ?? false
    }
}

/// Per-channel rotation override. `.auto` defers to whatever the source
/// produces (camera frames already track device orientation via
/// RotationCoordinator); the explicit angles let an operator fix a
/// sideways-mounted feed by hand.
enum ChannelRotation: Int, Codable, CaseIterable, Identifiable {
    case auto = -1
    case deg0 = 0
    case deg90 = 90
    case deg180 = 180
    case deg270 = 270

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .deg0: return "0°"
        case .deg90: return "90°"
        case .deg180: return "180°"
        case .deg270: return "270°"
        }
    }

    /// Radians applied at sample time. `.auto` resolves to 0 (the source has
    /// already been corrected upstream).
    var radians: Float {
        switch self {
        case .auto, .deg0: return 0
        case .deg90: return .pi / 2
        case .deg180: return .pi
        case .deg270: return 3 * .pi / 2
        }
    }
}

/// How a channel's source (which can be any aspect — portrait phone via
/// camera, square NDI, etc.) maps into the 1920x1080 program canvas.
enum ChannelFitMode: String, Codable, CaseIterable, Identifiable {
    case fit      // letterbox / pillarbox; preserve aspect, black bars on the short side
    case fill     // crop edges; preserve aspect, no bars
    case stretch  // ignore source aspect; distort to exactly fill the target

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fit: return "Fit"
        case .fill: return "Fill"
        case .stretch: return "Stretch"
        }
    }

    var shaderValue: Int32 {
        switch self {
        case .fit: return 0
        case .fill: return 1
        case .stretch: return 2
        }
    }
}

struct PIPSettings: Codable {
    var scale: Float = 1.0
    var offsetX: Float = 0.0
    var offsetY: Float = 0.0
    /// Rotation of the PIP rectangle on the canvas, in degrees. Positive
    /// values rotate counterclockwise (matches the conventional "tilt left"
    /// direction in VJ overlays).
    var rotation: Float = 0.0

    var isDefault: Bool {
        abs(scale - 1.0) < 0.01 && abs(offsetX) < 0.01 && abs(offsetY) < 0.01 && abs(rotation) < 0.5
    }

    mutating func reset() {
        scale = 1.0
        offsetX = 0.0
        offsetY = 0.0
        rotation = 0.0
    }

    private enum CodingKeys: String, CodingKey {
        case scale, offsetX, offsetY, rotation
    }

    init() {}

    // Older presets (before rotation existed) decode with rotation = 0.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scale = try c.decodeIfPresent(Float.self, forKey: .scale) ?? 1.0
        offsetX = try c.decodeIfPresent(Float.self, forKey: .offsetX) ?? 0.0
        offsetY = try c.decodeIfPresent(Float.self, forKey: .offsetY) ?? 0.0
        rotation = try c.decodeIfPresent(Float.self, forKey: .rotation) ?? 0.0
    }
}

struct EffectUniforms {
    var param1: Float
    var param2: Float
    var time: Float
    var padding: Float
}
