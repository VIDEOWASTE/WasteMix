import AVFoundation
import CoreVideo

/// Frame provider for external / UVC capture devices (HDMI capture cards,
/// USB webcams, Continuity Camera, Studio Display camera, etc.). Pulls
/// frames from CameraHub's shared multi-cam session, keyed by the device's
/// `uniqueID` rather than front/back position — UVC devices report
/// `.unspecified` so they can't share the position-based code path.
final class ExternalCameraSource: NSObject, FrameProvider {
    let uniqueID: String
    let displayName: String
    private(set) var isActive = false

    init(uniqueID: String, displayName: String) {
        self.uniqueID = uniqueID
        self.displayName = displayName
        super.init()
    }

    var latestPixelBuffer: CVPixelBuffer? {
        CameraHub.shared.latestBuffer(forUniqueID: uniqueID)
    }

    func start() {
        Task { @MainActor in
            let granted = await CameraSource.requestPermission()
            NSLog("[ExternalCamera] permission=%d uniqueID=%@", granted ? 1 : 0, uniqueID)
            guard granted else { return }
            CameraHub.shared.registerExternal(self, uniqueID: uniqueID)
            isActive = true
        }
    }

    func stop() {
        CameraHub.shared.unregisterExternal(self, uniqueID: uniqueID)
        isActive = false
    }
}
