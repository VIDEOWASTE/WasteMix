import Foundation
import AVFoundation
import os.log

private let logger = Logger(subsystem: "com.wastemix.app", category: "input")

@Observable
final class InputManager {
    private var activeSources: [Int: FrameProvider] = [:]
    let ndiDiscovery = NDIDiscovery()
    private(set) var cameraPermissionGranted = false

    init() {
        ndiDiscovery.startDiscovery()
        checkCameraPermission()
    }

    var discoveredNDISources: [NDIDiscoveredSource] {
        ndiDiscovery.sources
    }

    func applySource(_ source: ContentSource, to channelIndex: Int, channel: Channel? = nil, renderEngine: RenderEngine) {
        logger.error("applySource called: channel=\(channelIndex)")
        activeSources[channelIndex]?.stop()

        let provider: FrameProvider

        switch source {
        case .camera(let position):
            NSLog("[InputManager] Creating CameraSource position=%d", position.rawValue)
            provider = CameraSource(position: position)
        case .externalCamera(let uniqueID, let displayName):
            NSLog("[InputManager] Creating ExternalCameraSource uniqueID=%@", uniqueID)
            provider = ExternalCameraSource(uniqueID: uniqueID, displayName: displayName)
        case .mediaFile(let url):
            provider = MediaPlayerSource(url: url)
        case .image(let url):
            provider = ImageSource(url: url)
        case .solidColor(let r, let g, let b):
            provider = ImageSource(color: (r, g, b))
        case .pattern(let type):
            provider = PatternGeneratorSource(pattern: type)
        case .ndi(let name, let address):
            provider = NDISource(sourceName: name, ipAddress: address)
        case .audioVisualizer(let style):
            // Channel ref lets the visualizer read live params (density,
            // hue, speed, etc.) — passed weakly inside the source.
            provider = AudioVisualizerSource(style: style, channel: channel, audioEngine: renderEngine.audioEngine)
        }

        activeSources[channelIndex] = provider
        renderEngine.setSource(provider, for: channelIndex)
    }

    func clearSource(for channelIndex: Int, renderEngine: RenderEngine) {
        activeSources[channelIndex]?.stop()
        activeSources.removeValue(forKey: channelIndex)
        renderEngine.setSource(nil, for: channelIndex)
    }

    /// Returns the live 5-channel envelope output for the active audio
    /// visualizer on this channel (post-GAIN, post-THRESHOLD, post-
    /// ATTACK/RELEASE — the actual value the visualizer is using each
    /// frame). Nil if the channel's source isn't an AudioVisualizerSource.
    /// Used by the source picker to drive the live band meters so the
    /// user can see their envelope tweaks taking effect.
    func liveVisualizerEnvelopes(for channelIndex: Int) -> [Float]? {
        return (activeSources[channelIndex] as? AudioVisualizerSource)?.liveEnvelopes
    }

    private func checkCameraPermission() {
        Task {
            cameraPermissionGranted = await CameraSource.requestPermission()
        }
    }
}
