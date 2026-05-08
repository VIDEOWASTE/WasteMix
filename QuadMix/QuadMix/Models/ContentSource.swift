import Foundation
import AVFoundation

enum PatternType: String, CaseIterable, Identifiable, Codable {
    case colorBars
    case gradient
    case checkerboard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .colorBars: return "Color Bars"
        case .gradient: return "Gradient"
        case .checkerboard: return "Checkerboard"
        }
    }
}

/// Visualizer styles for the audio-input source. Three "literal" styles
/// (bars, waveform, combined) and five WMP-inspired plasma variants, each
/// with its own animated abstract pattern that responds to bass / mid /
/// high band levels and transient peaks.
enum VisualizerStyle: String, CaseIterable, Identifiable, Codable {
    case random         // auto-cycles through every other style on a timer + bass kicks
    case waveform
    case plasma          // multi-layer Plenoptic: layered plasma + lens flares
    case orbs            // 3+ rotating radial-gradient orbs on black, audio-driven
    case geometry        // 3D rotating polyhedra (cube, tetra, octa) with bloom edges
    case wmpBars         // Classic Winamp-style rainbow bars with peak-hold caps
    case alchemy         // Alchemy-style translucent additive ribbons
    case polygons        // concentric rotating polygons (Battery-style)
    case tunnel          // zooming concentric rings — flying inward
    case particles       // swarm of dots emitted by audio energy
    case spiral          // logarithmic spiral arms
    case ribbons         // flowing sinusoidal stacked lines
    case lightning       // jagged bolts triggered by transients
    case mandala         // 8-fold symmetric kaleidoscope

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .random: return "Random Cycle"
        case .waveform: return "Waveform"
        case .plasma: return "Plenoptic"
        case .orbs: return "Orbs"
        case .geometry: return "Geometry (3D)"
        case .wmpBars: return "Classic Bars"
        case .alchemy: return "Alchemy"
        case .polygons: return "Battery"
        case .tunnel: return "Tunnel"
        case .particles: return "Particles"
        case .spiral: return "Spiral"
        case .ribbons: return "Ribbons"
        case .lightning: return "Lightning"
        case .mandala: return "Mandala"
        }
    }

    var icon: String {
        switch self {
        case .random: return "shuffle"
        case .waveform: return "waveform"
        case .plasma: return "drop.fill"
        case .orbs: return "circles.hexagongrid.fill"
        case .geometry: return "cube.fill"
        case .wmpBars: return "chart.bar.xaxis"
        case .alchemy: return "sparkles.tv.fill"
        case .polygons: return "circle.hexagongrid.fill"
        case .tunnel: return "circle.dashed"
        case .particles: return "sparkles"
        case .spiral: return "arrow.triangle.swap"
        case .ribbons: return "wave.3.right"
        case .lightning: return "bolt.fill"
        case .mandala: return "snowflake"
        }
    }

    /// True for the abstract animated variants. Used by the param section
    /// in the source picker to decide whether to show the tweak sliders —
    /// `waveform` is a literal data-driven plot and doesn't benefit from
    /// the same param controls.
    var isPlasmaVariant: Bool {
        switch self {
        case .random, .plasma, .orbs, .geometry, .wmpBars, .alchemy, .polygons,
             .tunnel, .particles, .spiral, .ribbons, .lightning, .mandala: return true
        case .waveform: return false
        }
    }
}

/// One of the 5 audio envelope channels (SUB / BASS / MID / HIGH / AIR).
/// Modeled on LZX Sensory Translator: each channel gets its own input
/// gain, asymmetric attack/release envelope follower, and gate threshold.
/// The output is a smoothed 0..1 control signal that drives every
/// audio-reactive aspect of the visualizer.
struct EnvelopeChannel: Codable, Equatable {
    /// Pre-envelope input gain (0–2). Boost a quiet band or attenuate
    /// a hot one before envelope shaping.
    var gain: Float = 1.0
    /// Attack time, 0–1 mapped to 5 ms (snappy) → 150 ms (smooth).
    /// Fast attacks catch the leading edge of transients; slow attacks
    /// produce a more legato, breathing motion.
    var attack: Float = 0.5
    /// Release time, 0–1 mapped to 30 ms (twitchy) → 1500 ms (sustained).
    /// Slow release gives a "musical hang" on each hit; fast release
    /// produces tight machine-gun motion.
    var release: Float = 0.5
    /// Input gate (0–1). Below this threshold the channel outputs zero.
    /// Useful for ignoring background noise on quiet bands.
    var threshold: Float = 0.0

    init(gain: Float = 1.0, attack: Float = 0.5, release: Float = 0.5, threshold: Float = 0.0) {
        self.gain = gain
        self.attack = attack
        self.release = release
        self.threshold = threshold
    }
}

/// User-tweakable parameters for the audio visualizer. Visual knobs
/// (density / speed / hue / intensity) plus a 5-channel audio envelope
/// system for shaping how each frequency band drives the visuals.
struct VisualizerParams: Codable, Equatable {
    /// Object count multiplier (0-1). Polygons/particles/ribbons.
    var density: Float = 0.5
    /// Animation rate multiplier (0-1, mapped to 0.2x-3x).
    var speed: Float = 0.5
    /// Base hue shift (0-1) added to time-cycling colors.
    var hue: Float = 0.0
    /// Brightness / saturation / glow intensity (0-1).
    var intensity: Float = 0.7
    /// How much the BASS envelope drives continuous scale/pulse (0–1).
    /// Multiplier on top of the post-envelope BASS channel value.
    var bassResponse: Float = 0.7
    /// Bass-kick detection sensitivity (0–1). 0 = strict (ratio 1.9×
    /// over slow average; only the hardest kicks register), 1 = lenient
    /// (ratio 1.1×; nearly any bass bump fires). Drives discrete-event
    /// reactions: particle bounces, lightning bolt spawns, polygon
    /// flashes.
    var kickSensitivity: Float = 0.5
    /// Force multiplier applied when a kick fires (0–2). 0 = no kick
    /// reaction even when detected; 1 = default; 2 = exaggerated.
    var kickStrength: Float = 0.6
    /// Multiplier on mid-frequency-driven sway / sideways oscillation
    /// (0–2). 0 = no sway, 1 = default, 2 = wild.
    var swayAmount: Float = 0.5
    /// Global smoothing macro (0–1). Scales every envelope's attack and
    /// release time at once, preserving the per-band relative speeds.
    /// 0 = ×0.33 (fast/twitchy), 0.5 = ×1.0 (use the per-band values
    /// as-is), 1.0 = ×3.0 (slow/dreamy). Exponential mapping so each
    /// step doubles or halves the perceived response time.
    var smoothing: Float = 0.5
    /// Which one of the 4 envelope bands drives this visualizer's audio
    /// reactivity. 0=LOW, 1=MID, 2=HIGH, 3=FULL. Single-band routing —
    /// the selected band's envelope output feeds every audio-reactive
    /// aspect (scale, sway, brightness, kicks, etc.) of the active
    /// visualizer. Tapping a band tab in the source picker writes here.
    var reactiveBand: Int = 0
    /// 4 audio envelope channels, indexed as
    /// [0]=LOW, [1]=MID, [2]=HIGH, [3]=FULL.
    /// Defaults are tuned per-band: LOW slow for weighty bass, HIGH
    /// snappy for hi-hats/transients, FULL medium (sees the overall RMS
    /// energy of the mix).
    var envelopes: [EnvelopeChannel] = VisualizerParams.defaultEnvelopes()

    static func defaultEnvelopes() -> [EnvelopeChannel] {
        [
            EnvelopeChannel(gain: 1.0, attack: 0.50, release: 0.55, threshold: 0),  // LOW
            EnvelopeChannel(gain: 1.0, attack: 0.30, release: 0.40, threshold: 0),  // MID
            EnvelopeChannel(gain: 1.0, attack: 0.15, release: 0.30, threshold: 0),  // HIGH
            EnvelopeChannel(gain: 1.0, attack: 0.30, release: 0.40, threshold: 0)   // FULL
        ]
    }

    init() {}

    enum CodingKeys: String, CodingKey {
        case density, speed, hue, intensity
        case bassResponse, kickSensitivity, kickStrength, swayAmount
        case smoothing, reactiveBand
        case envelopes
    }

    /// Custom decoder uses `decodeIfPresent` for every field so loading
    /// a preset from a previous build (which won't have the envelopes
    /// array) doesn't fail — falls back to the per-band defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        density = try c.decodeIfPresent(Float.self, forKey: .density) ?? 0.5
        speed = try c.decodeIfPresent(Float.self, forKey: .speed) ?? 0.5
        hue = try c.decodeIfPresent(Float.self, forKey: .hue) ?? 0.0
        intensity = try c.decodeIfPresent(Float.self, forKey: .intensity) ?? 0.7
        bassResponse = try c.decodeIfPresent(Float.self, forKey: .bassResponse) ?? 0.7
        kickSensitivity = try c.decodeIfPresent(Float.self, forKey: .kickSensitivity) ?? 0.5
        kickStrength = try c.decodeIfPresent(Float.self, forKey: .kickStrength) ?? 0.6
        swayAmount = try c.decodeIfPresent(Float.self, forKey: .swayAmount) ?? 0.5
        smoothing = try c.decodeIfPresent(Float.self, forKey: .smoothing) ?? 0.5
        reactiveBand = try c.decodeIfPresent(Int.self, forKey: .reactiveBand) ?? 0
        var envs = try c.decodeIfPresent([EnvelopeChannel].self, forKey: .envelopes)
            ?? Self.defaultEnvelopes()
        // Tolerate fewer/more saved channels (e.g. presets from when this
        // was 5-band). Pad/trim to exactly 4.
        if envs.count < 4 {
            envs.append(contentsOf: Array(repeating: EnvelopeChannel(), count: 4 - envs.count))
        } else if envs.count > 4 {
            envs = Array(envs.prefix(4))
        }
        envelopes = envs
    }
}

/// Static index helpers so every consumer agrees on which channel is which.
/// Three frequency bands plus a FULL macro that follows the overall RMS
/// energy. LOW/MID/HIGH each cover roughly an octave-decade slice of the
/// audible spectrum; FULL is the whole-mix envelope (good for "pump on
/// every beat" reactivity that ignores frequency).
enum EnvelopeBand: Int, CaseIterable {
    case low = 0, mid = 1, high = 2, full = 3

    var name: String {
        switch self {
        case .low: return "LOW"
        case .mid: return "MID"
        case .high: return "HIGH"
        case .full: return "FULL"
        }
    }

    var freqLabel: String {
        switch self {
        case .low: return "20–250 Hz"
        case .mid: return "250 Hz–2 kHz"
        case .high: return "2–20 kHz"
        case .full: return "All bands (RMS)"
        }
    }
}

enum ContentSource: Identifiable {
    case camera(position: AVCaptureDevice.Position)
    case mediaFile(url: URL)
    case image(url: URL)
    case solidColor(red: Float, green: Float, blue: Float)
    case pattern(PatternType)
    case ndi(sourceName: String, ipAddress: String)
    case audioVisualizer(VisualizerStyle)

    var id: String {
        switch self {
        case .camera(let pos):
            return "camera_\(pos.rawValue)"
        case .mediaFile(let url):
            return "media_\(url.lastPathComponent)"
        case .image(let url):
            return "image_\(url.lastPathComponent)"
        case .solidColor(let r, let g, let b):
            return "color_\(r)_\(g)_\(b)"
        case .pattern(let type):
            return "pattern_\(type.rawValue)"
        case .ndi(let name, _):
            return "ndi_\(name)"
        case .audioVisualizer(let style):
            return "audiovis_\(style.rawValue)"
        }
    }

    var displayName: String {
        switch self {
        case .camera(let pos):
            return pos == .front ? "Front Camera" : "Back Camera"
        case .mediaFile(let url):
            return url.lastPathComponent
        case .image(let url):
            return url.lastPathComponent
        case .solidColor:
            return "Solid Color"
        case .pattern(let type):
            return type.displayName
        case .ndi(let name, _):
            return "NDI: \(name)"
        case .audioVisualizer(let style):
            return "Audio: \(style.displayName)"
        }
    }
}
