import AVFoundation
import CoreVideo

/// Thin consumer that pulls frames from CameraHub's shared multi-cam session.
/// Multiple CameraSource instances for different positions can stream
/// concurrently on iPad Pro.
final class CameraSource: NSObject, FrameProvider {
    let position: AVCaptureDevice.Position
    private(set) var isActive = false

    init(position: AVCaptureDevice.Position) {
        self.position = position
        super.init()
    }

    var latestPixelBuffer: CVPixelBuffer? {
        CameraHub.shared.latestBuffer(for: position)
    }

    func start() {
        Task { @MainActor in
            let granted = await Self.requestPermission()
            NSLog("[Camera] Permission granted: %d for position %d", granted ? 1 : 0, position.rawValue)
            guard granted else { return }
            CameraHub.shared.register(self, position: self.position)
            self.isActive = true
        }
    }

    func stop() {
        CameraHub.shared.unregister(self, position: self.position)
        isActive = false
    }

    static func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized { return true }
        if status == .notDetermined {
            return await AVCaptureDevice.requestAccess(for: .video)
        }
        return false
    }
}
