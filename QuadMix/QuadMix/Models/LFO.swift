import Foundation

enum LFOShape: String, CaseIterable, Identifiable, Codable {
    case sine
    case triangle
    case square
    case sawtooth
    case random

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sine: return "Sine"
        case .triangle: return "Triangle"
        case .square: return "Square"
        case .sawtooth: return "Saw"
        case .random: return "Random"
        }
    }

    var icon: String {
        switch self {
        case .sine: return "waveform.path"
        case .triangle: return "triangle"
        case .square: return "square.fill"
        case .sawtooth: return "chart.line.uptrend.xyaxis"
        case .random: return "dice"
        }
    }
}

enum LFOTarget: String, CaseIterable, Identifiable, Codable {
    case none
    case opacity
    case fxIntensity
    case fxParam2
    case pipScale
    case pipX
    case pipY

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "Off"
        case .opacity: return "Opacity"
        case .fxIntensity: return "FX Intensity"
        case .fxParam2: return "FX Param 2"
        case .pipScale: return "PIP Scale"
        case .pipX: return "PIP X"
        case .pipY: return "PIP Y"
        }
    }
}

struct LFOSettings {
    var enabled: Bool = false
    var shape: LFOShape = .sine
    var target: LFOTarget = .opacity
    var rate: Float = 0.5       // Hz (0.01 to 2.7)
    var depth: Float = 0.5      // 0-1 how much it modulates
    var min: Float = 0.0        // output floor
    var max: Float = 1.0        // output ceiling
    var useBPM: Bool = false    // sync to tap tempo BPM
    var bpmDivision: Float = 1.0 // 0.25 = quarter, 1 = whole, 2 = double

    /// Current LFO output value (0-1), updated each frame
    var currentValue: Float = 0.5

    var isActive: Bool { enabled && target != .none }

    /// Compute LFO value for a given time.
    /// Uses Double precision internally to avoid float32 precision loss at high uptimes.
    func compute(time: Float, bpm: Float) -> Float {
        let freq: Double
        if useBPM && bpm > 0 {
            freq = Double(bpm) / 60.0 * Double(bpmDivision)
        } else {
            freq = Double(rate)
        }

        // Use Double for the multiply+fmod to keep precision at large time values
        let phase = Float(fmod(Double(time) * freq, 1.0))
        var raw: Float

        switch shape {
        case .sine:
            raw = (sin(phase * .pi * 2.0) + 1.0) * 0.5
        case .triangle:
            raw = phase < 0.5 ? phase * 2.0 : 2.0 - phase * 2.0
        case .square:
            raw = phase < 0.5 ? 1.0 : 0.0
        case .sawtooth:
            raw = phase
        case .random:
            let seed = Float(floor(Double(time) * freq))
            raw = fmodf(sin(seed * 12.9898) * 43758.5453, 1.0)
            if raw < 0 { raw += 1.0 }
        }

        // Apply depth: 0 depth = no modulation (stays at center), 1 = full swing
        let center: Float = 0.5
        raw = center + (raw - center) * depth

        // Map to min-max range
        return self.min + raw * (self.max - self.min)
    }
}
