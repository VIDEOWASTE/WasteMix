import Foundation

struct ChannelPreset: Codable {
    var faderLevel: Float
    var blendMode: ChannelBlendMode
    var colorCorrection: ColorCorrection
    var transitionConfig: TransitionConfig
    var effectType: EffectType
    var effectIntensity: Float
    var effectParam2: Float = 0
    var keySettings: KeySettings
    var pipSettings: PIPSettings
    var lfo: LFOSettings = LFOSettings()
    var audioReact: AudioReactSettings = AudioReactSettings()
    var visualizerParams: VisualizerParams = VisualizerParams()
    var rotation: ChannelRotation = .auto
    var fitMode: ChannelFitMode = .fit

    // Custom decoder so old presets (saved before effectParam2/lfo/audioReact/
    // visualizerParams existed) still load — missing fields fall back to
    // defaults instead of failing the whole JSON.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        faderLevel = try c.decode(Float.self, forKey: .faderLevel)
        blendMode = try c.decode(ChannelBlendMode.self, forKey: .blendMode)
        colorCorrection = try c.decode(ColorCorrection.self, forKey: .colorCorrection)
        transitionConfig = try c.decode(TransitionConfig.self, forKey: .transitionConfig)
        effectType = try c.decode(EffectType.self, forKey: .effectType)
        effectIntensity = try c.decode(Float.self, forKey: .effectIntensity)
        effectParam2 = try c.decodeIfPresent(Float.self, forKey: .effectParam2) ?? 0
        keySettings = try c.decode(KeySettings.self, forKey: .keySettings)
        pipSettings = try c.decode(PIPSettings.self, forKey: .pipSettings)
        lfo = try c.decodeIfPresent(LFOSettings.self, forKey: .lfo) ?? LFOSettings()
        audioReact = try c.decodeIfPresent(AudioReactSettings.self, forKey: .audioReact) ?? AudioReactSettings()
        visualizerParams = try c.decodeIfPresent(VisualizerParams.self, forKey: .visualizerParams) ?? VisualizerParams()
        rotation = try c.decodeIfPresent(ChannelRotation.self, forKey: .rotation) ?? .auto
        fitMode = try c.decodeIfPresent(ChannelFitMode.self, forKey: .fitMode) ?? .fill
    }

    init(faderLevel: Float, blendMode: ChannelBlendMode, colorCorrection: ColorCorrection,
         transitionConfig: TransitionConfig, effectType: EffectType, effectIntensity: Float,
         effectParam2: Float, keySettings: KeySettings, pipSettings: PIPSettings,
         lfo: LFOSettings, audioReact: AudioReactSettings, visualizerParams: VisualizerParams,
         rotation: ChannelRotation, fitMode: ChannelFitMode) {
        self.faderLevel = faderLevel
        self.blendMode = blendMode
        self.colorCorrection = colorCorrection
        self.transitionConfig = transitionConfig
        self.effectType = effectType
        self.effectIntensity = effectIntensity
        self.effectParam2 = effectParam2
        self.keySettings = keySettings
        self.pipSettings = pipSettings
        self.lfo = lfo
        self.audioReact = audioReact
        self.visualizerParams = visualizerParams
        self.rotation = rotation
        self.fitMode = fitMode
    }
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
                effectParam2: ch.effectParam2,
                keySettings: ch.keySettings,
                pipSettings: ch.pipSettings,
                lfo: ch.lfo,
                audioReact: ch.audioReact,
                visualizerParams: ch.visualizerParams,
                rotation: ch.rotation,
                fitMode: ch.fitMode
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
            ch.effectParam2 = cp.effectParam2
            ch.keySettings = cp.keySettings
            ch.pipSettings = cp.pipSettings
            ch.lfo = cp.lfo
            ch.audioReact = cp.audioReact
            ch.visualizerParams = cp.visualizerParams
            ch.rotation = cp.rotation
            ch.fitMode = cp.fitMode
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
