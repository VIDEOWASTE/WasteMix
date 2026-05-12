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
    case posterize
    case blur
    case solarize
    case edges
    case datamosh
    case scanlines
    case kaleidoscope
    case halftone
    case feedback
    // Chromatose-inspired distortion family
    case wave
    case tunnel
    case channels
    case displace
    case thermal

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
        case .posterize: return "Posterize"
        case .blur: return "Blur"
        case .solarize: return "Solarize"
        case .edges: return "Edges"
        case .datamosh: return "Datamosh"
        case .scanlines: return "Scanlines"
        case .kaleidoscope: return "Kaleido"
        case .halftone: return "Halftone"
        case .feedback: return "Feedback"
        case .wave: return "Wave"
        case .tunnel: return "Tunnel"
        case .channels: return "Channels"
        case .displace: return "Displace"
        case .thermal: return "Thermal"
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
        case .posterize: return "paintbrush"
        case .blur: return "drop.halffull"
        case .solarize: return "sun.max.trianglebadge.exclamationmark"
        case .edges: return "square.dashed"
        case .datamosh: return "lines.measurement.horizontal"
        case .scanlines: return "line.3.horizontal"
        case .kaleidoscope: return "star.leadinghalf.filled"
        case .halftone: return "circle.dotted"
        case .feedback: return "arrow.2.squarepath"
        case .wave: return "wave.3.right"
        case .tunnel: return "circle.circle"
        case .channels: return "rectangle.split.3x1"
        case .displace: return "waveform.path.ecg"
        case .thermal: return "thermometer.high"
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
        case .posterize: return "effect_posterize"
        case .blur: return "effect_blur"
        case .solarize: return "effect_solarize"
        case .edges: return "effect_edges"
        case .datamosh: return "effect_datamosh"
        case .scanlines: return "effect_scanlines"
        case .kaleidoscope: return "effect_kaleidoscope"
        case .halftone: return "effect_halftone"
        case .feedback: return "effect_feedback"
        case .wave: return "effect_wave"
        case .tunnel: return "effect_tunnel"
        case .channels: return "effect_channels"
        case .displace: return "effect_displace"
        case .thermal: return "effect_thermal"
        }
    }

    var isFeedback: Bool { self == .feedback }

    /// Per-effect parameter list. Slot 0 → channel.effectIntensity, slot 1 →
    /// channel.effectParam2, slots 2-5 → channel.effectExtraParams[0-3].
    /// Length 0 means no user knobs (e.g. Mirror without an amount).
    var paramSpecs: [EffectParamSpec] {
        switch self {
        case .none, .freeze: return []
        case .rotate:        return [.init("ANGLE", 0.0)]
        case .mirror:        return [.init("AMOUNT", 1.0)]
        case .mirrorV:       return [.init("AMOUNT", 1.0)]
        case .invert:        return [.init("AMOUNT", 1.0)]
        case .mosaic:        return [.init("BLOCK SIZE", 0.3)]
        case .strobe:        return [.init("SPEED", 0.4), .init("DUTY", 0.3)]
        case .posterize:     return [.init("CRUSH", 0.4)]
        case .blur:          return [.init("RADIUS", 0.5), .init("DIRECTION", 0.0)]
        case .solarize:      return [.init("THRESHOLD", 0.5), .init("CURVE", 0.3)]
        case .edges:         return [.init("STRENGTH", 0.5)]
        case .datamosh:      return [.init("SHIFT", 0.6), .init("BLOCK H", 0.4)]
        case .scanlines:     return [.init("DENSITY", 0.5), .init("BRIGHTNESS", 0.5)]
        case .kaleidoscope:  return [.init("SEGMENTS", 0.3), .init("ROTATION", 0.0)]
        case .halftone:      return [.init("DOT SIZE", 0.4)]
        // Upgraded Feedback — full 6-param Chromatose-style control.
        case .feedback: return [
            .init("TRAIL", 0.7),
            .init("ZOOM/ROT", 0.3),
            .init("MIN LUMA", 0.0),
            .init("SMOOTH", 0.3),
            .init("INPUT MIX", 0.5),
            .init("TINT", 0.0)
        ]
        // Wave — multi-wave UV displacement.
        case .wave: return [
            .init("AMPLITUDE", 0.3),
            .init("FREQUENCY", 0.3),
            .init("SPEED", 0.4),
            .init("ANGLE", 0.5),
            .init("SHAPE", 0.0),
            .init("2ND WAVE", 0.0)
        ]
        // Tunnel — polar warp with depth illusion.
        case .tunnel: return [
            .init("ZOOM", 0.3),
            .init("TWIST", 0.5),
            .init("REPEAT", 0.3),
            .init("CENTER X", 0.5),
            .init("CENTER Y", 0.5),
            .init("EDGE FADE", 0.2)
        ]
        // Channels — RGB displacement at arbitrary angle.
        case .channels: return [
            .init("DISTANCE", 0.3),
            .init("ANGLE", 0.0),
            .init("RED", 1.0),
            .init("GREEN", 1.0),
            .init("BLUE", 1.0),
            .init("SMEAR", 0.0)
        ]
        // Displace — value-noise UV displacement.
        case .displace: return [
            .init("AMOUNT", 0.3),
            .init("SCALE", 0.4),
            .init("SPEED", 0.3),
            .init("CHAN SEP", 0.0),
            .init("OCTAVES", 0.3),
            .init("DIRECTION", 0.5)
        ]
        // Thermal — FLIR-style false-color heat map. PALETTE crossfades
        // Iron → Rainbow → White-hot; CONTRAST shapes the heat curve;
        // NOISE adds sensor grain; SCAN overlays a thin display scanline.
        case .thermal: return [
            .init("INTENSITY", 1.0),
            .init("PALETTE", 0.0),
            .init("CONTRAST", 0.5),
            .init("NOISE", 0.15),
            .init("SCAN", 0.2)
        ]
        }
    }

    /// 4 default values to seed `effectExtraParams` with when this effect is
    /// freshly selected. Pads with 0.5 if the effect uses fewer than 4 extras.
    var defaultExtraParams: [Float] {
        let specs = paramSpecs
        return (0..<4).map { i in
            let slot = i + 2
            return slot < specs.count ? specs[slot].defaultValue : 0.5
        }
    }

    // Legacy accessors — kept for callers that only need the first two
    // params. New code should iterate `paramSpecs` directly.
    var param1Label: String { paramSpecs.first?.label ?? "INTENSITY" }
    var hasParam2: Bool { paramSpecs.count >= 2 }
    var param2Label: String { paramSpecs.count >= 2 ? paramSpecs[1].label : "" }
    var defaultParam2: Float { paramSpecs.count >= 2 ? paramSpecs[1].defaultValue : 0.0 }
    var defaultIntensity: Float { paramSpecs.first?.defaultValue ?? 0.5 }
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

/// One user-adjustable knob inside an effect. Effects expose 0-6 of these
/// via `EffectType.paramSpecs`; the FX panel renders one slider per spec.
struct EffectParamSpec {
    let label: String
    let defaultValue: Float

    init(_ label: String, _ defaultValue: Float) {
        self.label = label
        self.defaultValue = defaultValue
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

/// Generic per-effect uniform buffer. Six free parameter slots so each
/// effect can choose how many it surfaces (Wave/Tunnel/etc. need 4-6;
/// Mirror/Invert/etc. need only one). Keyed effects also stash their
/// invert flag in `param3`.
struct EffectUniforms {
    var param1: Float
    var param2: Float
    var param3: Float
    var param4: Float
    var param5: Float
    var param6: Float
    var time: Float
    var aspect: Float
}
