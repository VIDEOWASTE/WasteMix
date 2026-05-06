import Foundation

@Observable
final class MixerState {
    var channels: [Channel] = (0..<4).map { Channel(id: $0) }
    var globalColorCorrection = ColorCorrection()
    var programResolution = CGSize(width: 1920, height: 1080)
    var frameRate: Int = 60
    /// Which channel is selected for the Preview monitor (0-3)
    var selectedPreviewChannel: Int = 0
    /// Global BPM from tap tempo
    var bpm: Float = 120

    /// Master output level (0-1). Multiplied with each channel's fader during
    /// composite, so the master LFO can pulse/breathe the whole program.
    var masterLevel: Float = 1.0
    /// Master section LFO — drives the selected master target when enabled.
    var masterLFO = LFOSettings()
    var masterLFOTarget: MasterLFOTarget = .crossfader

    /// Crossfader position 0..1. Lifted out of MixerView so the master LFO
    /// can sweep it automatically.
    var crossfaderPos: Float = 0.5
    var crossfaderA: Set<Int> = [0]
    var crossfaderB: Set<Int> = [1]

    init() {
        loadPersistedSettings()
    }

    // MARK: - Persistence

    private enum Key {
        static let bpm = "wm.bpm"
        static let crossfaderPos = "wm.crossfaderPos"
        static let crossfaderA = "wm.crossfaderA"
        static let crossfaderB = "wm.crossfaderB"
        static let masterLFOTarget = "wm.masterLFOTarget"
        static let selectedPreview = "wm.selectedPreview"
    }

    private func loadPersistedSettings() {
        let d = UserDefaults.standard
        // Validate every value before accepting — corrupt UserDefaults entries
        // (e.g. bpm = 100000) would otherwise propagate into the LFO compute
        // path and produce NaN/inf values.
        let savedBPM = d.float(forKey: Key.bpm)
        if savedBPM >= 30 && savedBPM <= 300 { bpm = savedBPM }

        if d.object(forKey: Key.crossfaderPos) != nil {
            let pos = d.float(forKey: Key.crossfaderPos)
            crossfaderPos = max(0, min(1, pos))
        }
        if let a = d.array(forKey: Key.crossfaderA) as? [Int] {
            crossfaderA = Set(a.filter { $0 >= 0 && $0 < channels.count })
        }
        if let b = d.array(forKey: Key.crossfaderB) as? [Int] {
            crossfaderB = Set(b.filter { $0 >= 0 && $0 < channels.count })
        }

        if let raw = d.string(forKey: Key.masterLFOTarget),
           let t = MasterLFOTarget(rawValue: raw) { masterLFOTarget = t }

        let preview = d.integer(forKey: Key.selectedPreview)
        if preview >= 0 && preview < channels.count { selectedPreviewChannel = preview }
    }

    /// Snapshot the user-configurable bits to UserDefaults. Called from the
    /// engine's pauseForBackground hook so state survives task-switching and
    /// app re-launch.
    func savePersistedSettings() {
        let d = UserDefaults.standard
        d.set(bpm, forKey: Key.bpm)
        d.set(crossfaderPos, forKey: Key.crossfaderPos)
        d.set(Array(crossfaderA), forKey: Key.crossfaderA)
        d.set(Array(crossfaderB), forKey: Key.crossfaderB)
        d.set(masterLFOTarget.rawValue, forKey: Key.masterLFOTarget)
        d.set(selectedPreviewChannel, forKey: Key.selectedPreview)
    }

    /// Apply the current crossfader position to the A/B groups' fader levels.
    /// Channels not in either group keep their manual fader value.
    func applyCrossfader() {
        let aLevel: Float = 1.0 - crossfaderPos
        let bLevel: Float = crossfaderPos
        for i in 0..<channels.count {
            let inA = crossfaderA.contains(i)
            let inB = crossfaderB.contains(i)
            if inA && inB {
                channels[i].faderLevel = max(aLevel, bLevel)
            } else if inA {
                channels[i].faderLevel = aLevel
            } else if inB {
                channels[i].faderLevel = bLevel
            }
        }
    }
}
