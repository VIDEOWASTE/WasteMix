import AVFoundation
import CoreVideo

/// Singleton that owns one AVCaptureMultiCamSession (or a regular session as
/// fallback) and runs all enabled cameras concurrently. CameraSource instances
/// register here for a position; they all read frames from the same per-position
/// AVCaptureVideoDataOutput. This is what allows front + back cameras to be
/// active simultaneously on iPad Pro.
final class CameraHub: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let shared = CameraHub()

    /// True when the device + OS support concurrent multi-cam capture (iPad
    /// Pro and recent iPhones). Read by CameraSource for fallback decisions.
    let isMultiCamSupported: Bool

    let session: AVCaptureSession
    private let queue = DispatchQueue(label: "com.wastemix.camerahub")
    private let lock = NSLock()

    private var inputs: [AVCaptureDevice.Position: AVCaptureDeviceInput] = [:]
    private var outputs: [AVCaptureDevice.Position: AVCaptureVideoDataOutput] = [:]
    private var consumers: [AVCaptureDevice.Position: NSHashTable<CameraSource>] = [:]
    private var latestBuffers: [AVCaptureDevice.Position: CVPixelBuffer] = [:]

    override init() {
        if AVCaptureMultiCamSession.isMultiCamSupported {
            session = AVCaptureMultiCamSession()
            isMultiCamSupported = true
        } else {
            session = AVCaptureSession()
            isMultiCamSupported = false
        }
        super.init()

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleRuntimeError(_:)),
                       name: .AVCaptureSessionRuntimeError, object: session)
        nc.addObserver(self, selector: #selector(handleInterrupted(_:)),
                       name: .AVCaptureSessionWasInterrupted, object: session)
        // Without this, after a phone call / Control Center camera grab /
        // Stage Manager focus change, the session never resumes and cameras
        // stay black until the app is force-relaunched.
        nc.addObserver(self, selector: #selector(handleInterruptionEnded(_:)),
                       name: .AVCaptureSessionInterruptionEnded, object: session)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public API

    func register(_ source: CameraSource, position: AVCaptureDevice.Position) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.attachInputIfNeeded(position: position)

            if self.consumers[position] == nil {
                self.consumers[position] = NSHashTable<CameraSource>.weakObjects()
            }
            self.consumers[position]?.add(source)

            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func unregister(_ source: CameraSource, position: AVCaptureDevice.Position) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.consumers[position]?.remove(source)
            let positionConsumers = self.consumers[position]?.count ?? 0
            let totalConsumers = self.consumers.values.reduce(0) { $0 + $1.count }

            // On non-multi-cam devices (iPads with chips older than A12 — iPad
            // 6/7, iPad Pro 1st/2nd gen, iPad Air 2 etc.), a regular
            // AVCaptureSession only allows ONE camera input at a time. To
            // make camera switching work (CH1 front → CH1 back), we must
            // fully detach the old input when its consumers drop to zero.
            // Multi-cam can keep inputs attached for instant switching back.
            if !self.isMultiCamSupported && positionConsumers == 0 {
                self.detachInput(for: position)
            }

            if totalConsumers == 0 && self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    private func detachInput(for position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        if let input = inputs[position] {
            session.removeInput(input)
            inputs.removeValue(forKey: position)
        }
        if let output = outputs[position] {
            session.removeOutput(output)
            outputs.removeValue(forKey: position)
        }
        session.commitConfiguration()
    }

    func latestBuffer(for position: AVCaptureDevice.Position) -> CVPixelBuffer? {
        lock.lock(); defer { lock.unlock() }
        return latestBuffers[position]
    }

    /// Re-attach any per-position inputs that were detached during a previous
    /// background cycle (single-cam fallback path), then re-start the session.
    /// Called from `RenderEngine.resumeForForeground()`.
    func reattachAllConsumers() {
        queue.async { [weak self] in
            guard let self = self else { return }
            for (position, hashTable) in self.consumers where hashTable.count > 0 {
                if self.inputs[position] == nil {
                    self.attachInputIfNeeded(position: position)
                }
            }
            let total = self.consumers.values.reduce(0) { $0 + $1.count }
            if total > 0 && !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    // MARK: - Internal

    private func attachInputIfNeeded(position: AVCaptureDevice.Position) {
        if inputs[position] != nil { return }

        let allDeviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInUltraWideCamera,
            .builtInTelephotoCamera,
            .builtInDualCamera,
            .builtInTripleCamera,
            .builtInTrueDepthCamera,
            .external
        ]
        let discovered = AVCaptureDevice.DiscoverySession(
            deviceTypes: allDeviceTypes,
            mediaType: .video,
            position: position
        ).devices

        // Prefer a format that explicitly supports multi-cam if we're using it.
        guard let device = discovered.first ?? AVCaptureDevice.DiscoverySession(
            deviceTypes: allDeviceTypes, mediaType: .video, position: .unspecified
        ).devices.first(where: { $0.position == position }) else {
            NSLog("[CameraHub] no device for position=%d", position.rawValue)
            return
        }

        if isMultiCamSupported {
            if let multiCamFormat = device.formats.first(where: { $0.isMultiCamSupported }) {
                do {
                    try device.lockForConfiguration()
                    device.activeFormat = multiCamFormat
                    device.unlockForConfiguration()
                } catch {
                    NSLog("[CameraHub] format lock failed: %@", error.localizedDescription)
                }
            }
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            NSLog("[CameraHub] input err: %@", error.localizedDescription)
            return
        }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)

        session.beginConfiguration()
        if !isMultiCamSupported {
            if session.canSetSessionPreset(.hd1280x720) {
                session.sessionPreset = .hd1280x720
            }
        }
        guard session.canAddInput(input) else {
            NSLog("[CameraHub] canAddInput false for pos=%d", position.rawValue)
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        guard session.canAddOutput(output) else {
            NSLog("[CameraHub] canAddOutput false for pos=%d", position.rawValue)
            session.commitConfiguration()
            return
        }
        session.addOutput(output)

        if let conn = output.connection(with: .video) {
            // iPad front camera (TrueDepth) delivers landscape-iPad frames
            // upside-down by default. 180° brings it right-side-up.
            // Back camera is already correctly oriented at 0°.
            let angle: CGFloat = (position == .front) ? 180 : 0
            if conn.isVideoRotationAngleSupported(angle) {
                conn.videoRotationAngle = angle
            } else if conn.isVideoRotationAngleSupported(0) {
                conn.videoRotationAngle = 0
            }
        }
        session.commitConfiguration()

        inputs[position] = input
        outputs[position] = output
        NSLog("[CameraHub] attached %@ pos=%d type=%@", device.localizedName, position.rawValue, device.deviceType.rawValue)
    }

    // MARK: - Sample buffer delegate

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // Resolve which position this output belongs to.
        var position: AVCaptureDevice.Position = .unspecified
        for (pos, out) in outputs {
            if out === output { position = pos; break }
        }
        guard position != .unspecified else { return }

        lock.lock()
        latestBuffers[position] = pb
        lock.unlock()
    }

    // MARK: - Notifications

    @objc private func handleRuntimeError(_ note: Notification) {
        let err = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
        let code = err?.code ?? -1
        NSLog("[CameraHub] runtimeError code=%d desc=%@", code, err?.localizedDescription ?? "?")
    }
    @objc private func handleInterrupted(_ note: Notification) {
        let reason = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int) ?? -1
        NSLog("[CameraHub] interrupted reason=%d", reason)
    }
    @objc private func handleInterruptionEnded(_ note: Notification) {
        NSLog("[CameraHub] interruption ended; resuming session")
        queue.async { [weak self] in
            guard let self = self else { return }
            // Only restart if there's still at least one consumer.
            let total = self.consumers.values.reduce(0) { $0 + $1.count }
            if total > 0 && !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }
}
