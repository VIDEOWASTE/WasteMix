import AVFoundation
import CoreVideo

final class CameraSource: NSObject, FrameProvider {
    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.quadmix.camera")
    private var _latestPixelBuffer: CVPixelBuffer?
    private let lock = NSLock()
    private(set) var isActive = false

    let position: AVCaptureDevice.Position

    init(position: AVCaptureDevice.Position) {
        self.position = position
        super.init()
    }

    var latestPixelBuffer: CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return _latestPixelBuffer
    }

    func start() {
        // Always request permission on main thread first, then configure on session queue
        Task { @MainActor in
            let granted = await Self.requestPermission()
            NSLog("[Camera] Permission granted: %d for position %d", granted ? 1 : 0, position.rawValue)
            guard granted else { return }

            sessionQueue.async { [weak self] in
                self?.configureAndStart()
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
            DispatchQueue.main.async {
                self?.isActive = false
            }
        }
    }

    private func configureAndStart() {
        // Remove existing inputs/outputs if reconfiguring
        for input in captureSession.inputs { captureSession.removeInput(input) }
        for output in captureSession.outputs { captureSession.removeOutput(output) }

        captureSession.beginConfiguration()

        // List all cameras
        let allDevices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices
        NSLog("[Camera] Found %d devices:", allDevices.count)
        for d in allDevices {
            NSLog("[Camera]   %@ pos=%d type=%@", d.localizedName, d.position.rawValue, d.deviceType.rawValue)
        }

        // Find best camera
        var device: AVCaptureDevice?

        // Try exact position match
        device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)

        // Try discovery with position
        if device == nil {
            device = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .external],
                mediaType: .video,
                position: position
            ).devices.first
        }

        // Fallback: any camera
        if device == nil {
            device = allDevices.first
        }

        guard let device else {
            NSLog("[Camera] ERROR: No camera found")
            captureSession.commitConfiguration()
            return
        }
        NSLog("[Camera] Using: %@", device.localizedName)

        // Create input
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            } else {
                NSLog("[Camera] ERROR: canAddInput returned false")
            }
        } catch {
            NSLog("[Camera] ERROR creating input: %@", error.localizedDescription)
            captureSession.commitConfiguration()
            return
        }

        // Set preset (fall back if not supported)
        if captureSession.canSetSessionPreset(.hd1920x1080) {
            captureSession.sessionPreset = .hd1920x1080
        } else if captureSession.canSetSessionPreset(.hd1280x720) {
            captureSession.sessionPreset = .hd1280x720
        } else {
            captureSession.sessionPreset = .high
        }

        // Output
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        } else {
            NSLog("[Camera] ERROR: canAddOutput returned false")
        }

        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(0) {
                connection.videoRotationAngle = 0
            }
        }

        captureSession.commitConfiguration()

        NSLog("[Camera] Starting session: inputs=%d outputs=%d", captureSession.inputs.count, captureSession.outputs.count)
        captureSession.startRunning()
        NSLog("[Camera] Session running: %d", captureSession.isRunning ? 1 : 0)

        DispatchQueue.main.async { [weak self] in
            self?.isActive = true
        }
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

extension CameraSource: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock()
        _latestPixelBuffer = pb
        lock.unlock()
    }
}
