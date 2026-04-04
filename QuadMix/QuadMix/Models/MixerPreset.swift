import Foundation

struct ChannelPreset: Codable {
    var faderLevel: Float
    var blendMode: ChannelBlendMode
    var colorCorrection: ColorCorrection
    var transitionConfig: TransitionConfig
    var effectType: EffectType
    var effectIntensity: Float
    var keySettings: KeySettings
    var pipSettings: PIPSettings
}

struct MixerPreset: Codable, Identifiable {
    var id = UUID()
    var name: String
    var channels: [ChannelPreset]
    var globalColorCorrection: ColorCorrection
    var crossfaderPosition: Float
    var bpm: Float
    var createdAt: Date = Date()
}

@Observable
final class PresetManager {
    private(set) var presets: [MixerPreset] = []
    private let savePath: URL

    init() {
        savePath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("wastemix_presets.json")
        load()
    }

    func save(preset: MixerPreset) {
        presets.append(preset)
        persist()
    }

    func delete(at index: Int) {
        guard index < presets.count else { return }
        presets.remove(at: index)
        persist()
    }

    func capture(from mixerState: MixerState, name: String, crossfaderPos: Float, bpm: Float) -> MixerPreset {
        let channelPresets = mixerState.channels.map { ch in
            ChannelPreset(
                faderLevel: ch.faderLevel,
                blendMode: ch.blendMode,
                colorCorrection: ch.colorCorrection,
                transitionConfig: ch.transitionConfig,
                effectType: ch.effectType,
                effectIntensity: ch.effectIntensity,
                keySettings: ch.keySettings,
                pipSettings: ch.pipSettings
            )
        }
        return MixerPreset(
            name: name,
            channels: channelPresets,
            globalColorCorrection: mixerState.globalColorCorrection,
            crossfaderPosition: crossfaderPos,
            bpm: bpm
        )
    }

    func apply(_ preset: MixerPreset, to mixerState: MixerState) {
        for (i, cp) in preset.channels.enumerated() where i < mixerState.channels.count {
            let ch = mixerState.channels[i]
            ch.faderLevel = cp.faderLevel
            ch.blendMode = cp.blendMode
            ch.colorCorrection = cp.colorCorrection
            ch.transitionConfig = cp.transitionConfig
            ch.effectType = cp.effectType
            ch.effectIntensity = cp.effectIntensity
            ch.keySettings = cp.keySettings
            ch.pipSettings = cp.pipSettings
        }
        mixerState.globalColorCorrection = preset.globalColorCorrection
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(presets) {
            try? data.write(to: savePath)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: savePath),
              let loaded = try? JSONDecoder().decode([MixerPreset].self, from: data) else { return }
        presets = loaded
    }
}
