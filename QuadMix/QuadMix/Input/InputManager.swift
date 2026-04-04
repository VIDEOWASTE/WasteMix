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

    func applySource(_ source: ContentSource, to channelIndex: Int, renderEngine: RenderEngine) {
        logger.error("applySource called: channel=\(channelIndex)")
        activeSources[channelIndex]?.stop()

        let provider: FrameProvider

        switch source {
        case .camera(let position):
            NSLog("[InputManager] Creating CameraSource position=%d", position.rawValue)
            provider = CameraSource(position: position)
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
        }

        activeSources[channelIndex] = provider
        renderEngine.setSource(provider, for: channelIndex)
    }

    func clearSource(for channelIndex: Int, renderEngine: RenderEngine) {
        activeSources[channelIndex]?.stop()
        activeSources.removeValue(forKey: channelIndex)
        renderEngine.setSource(nil, for: channelIndex)
    }

    private func checkCameraPermission() {
        Task {
            cameraPermissionGranted = await CameraSource.requestPermission()
        }
    }
}
