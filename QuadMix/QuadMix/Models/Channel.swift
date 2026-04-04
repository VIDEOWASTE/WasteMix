import Foundation
import SwiftUI

/// What the audio reactivity drives on this channel
enum AudioReactTarget: String, CaseIterable, Identifiable, Codable {
    case opacity    // drives fader level
    case effectIntensity  // drives FX intensity
    case none       // disabled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .opacity: return "Opacity"
        case .effectIntensity: return "FX Intensity"
        case .none: return "Off"
        }
    }
}

/// Per-channel audio EQ / reactivity settings
struct AudioReactSettings {
    var enabled: Bool = false
    var target: AudioReactTarget = .opacity

    /// Which frequency bands this channel reacts to (0-6), and their gain
    var bandGains: [Float] = [0, 0, 0, 0, 0, 0, 0]  // 7 bands, 0 = off, 1 = full

    /// Smoothing: 0 = instant (jumpy), 1 = very smooth (slow response)
    var smoothing: Float = 0.3

    /// Minimum output value (floor)
    var floor: Float = 0.0

    /// Maximum output value (ceiling)
    var ceiling: Float = 1.0

    /// The current computed reactive value (0-1), updated each frame
    var currentValue: Float = 0

    var isActive: Bool { enabled && target != .none && bandGains.contains(where: { $0 > 0.01 }) }
}

@Observable
final class Channel: Identifiable {
    let id: Int
    var source: ContentSource?
    var faderLevel: Float = 0.0
    var blendMode: ChannelBlendMode = .normal
    var colorCorrection = ColorCorrection()
    var transitionConfig = TransitionConfig()
    var isTransitioning: Bool = false
    var transitionProgress: Float = 0.0

    // Effects
    var effectType: EffectType = .none
    var effectIntensity: Float = 0.5
    var effectParam2: Float = 0.0
    var isFrozen: Bool = false

    // LFO
    var lfo = LFOSettings()

    // Keying
    var keySettings = KeySettings()

    // PIP positioning
    var pipSettings = PIPSettings()

    // Audio reactivity
    var audioReact = AudioReactSettings()

    init(id: Int) {
        self.id = id
    }

    var displayName: String {
        "CH \(id + 1)"
    }

    var hasSource: Bool {
        source != nil
    }

    var isActive: Bool {
        faderLevel > 0.001 && source != nil
    }
}
