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
}
