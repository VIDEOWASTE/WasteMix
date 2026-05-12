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
struct AudioReactSettings: Codable {
    var enabled: Bool = false
    var target: AudioReactTarget = .opacity

    /// Which frequency bands this channel reacts to (0-6), and their gain.
    /// Default to all-bands-full so toggling Audio React on immediately
    /// produces visible reactivity instead of looking broken.
    var bandGains: [Float] = [1, 1, 1, 1, 1, 1, 1]

    /// Smoothing: 0 = instant (jumpy), 1 = very smooth (slow response)
    var smoothing: Float = 0.3

    /// Minimum output value (floor)
    var floor: Float = 0.0

    /// Maximum output value (ceiling)
    var ceiling: Float = 1.0

    // `currentValue` was moved to `Channel.audioReactCurrent` for the same
    // observation-fan-out reason as the LFO's currentValue. Per-frame
    // updates to a sibling scalar on the Channel only invalidate views
    // that read that one scalar — not views bound to bandGains, smoothing,
    // floor, ceiling, etc.

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
    var effectIntensity: Float = 0.5  // = uniform.param1
    var effectParam2: Float = 0.0     // = uniform.param2
    /// Extra effect parameters 3-6 (uniform.param3 .. param6). Variable-
    /// width per effect; effects with only 1-2 knobs ignore these. Sized
    /// to 4 so all slots are always addressable from the shader.
    var effectExtraParams: [Float] = [0.5, 0.5, 0.5, 0.5]
    var isFrozen: Bool = false

    // LFO
    var lfo = LFOSettings()

    // Keying
    var keySettings = KeySettings()

    // PIP positioning
    var pipSettings = PIPSettings()

    // Source framing — rotation override + how the source aspect maps
    // into the 1920x1080 program canvas. Default to .auto rotation (camera
    // frames already track device orientation) and .fit (letterbox) so
    // portrait sources don't get stretched horizontally.
    var rotation: ChannelRotation = .auto
    // Default to .fill so a portrait camera (or any non-16:9 source) crops
    // to fill the program canvas instead of letterboxing — that's the
    // behavior most VJ rigs want by default.
    var fitMode: ChannelFitMode = .fill

    // Audio reactivity
    var audioReact = AudioReactSettings()

    // Audio visualizer params (only used when source is .audioVisualizer)
    var visualizerParams = VisualizerParams()

    /// Per-frame computed values, hoisted out of their owning structs so
    /// 60Hz writes don't invalidate every view bound to any field of
    /// `lfo` / `audioReact`. Reads still come from the same Channel
    /// observation root, but only views that read these specific scalars
    /// rebuild when they change.
    var lfoCurrent: Float = 0.5
    var audioReactCurrent: Float = 0

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
