import AVFoundation
import CoreVideo

/// Singleton that owns one AVCaptureMultiCamSession (or a regular session as
/// fallback) and runs all enabled cameras concurrently. CameraSource instances
/// register here for a position; they all read frames from the same per-position
/// AVCaptureVideoDataOutput. This is what allows front + back cameras to be
/// active simultaneously on iPad Pro.
///
/// Also handles external / UVC capture cards (HDMI capture, USB webcams,
/// Studio Display camera, etc.) via a parallel uniqueID-keyed path. External
/// devices on iOS report `position == .unspecified`, so a position-only API
/// would never see them — we register them by `device.uniqueID` instead.
@Observable
final class CameraHub: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @ObservationIgnored static let shared = CameraHub()

    /// True when the device + OS support concurrent multi-cam capture (iPad
    /// Pro and recent iPhones). Read by CameraSource for fallback decisions.
    @ObservationIgnored let isMultiCamSupported: Bool

    @ObservationIgnored let session: AVCaptureSession
    @ObservationIgnored private let queue = DispatchQueue(label: "com.wastemix.camerahub")
    @ObservationIgnored private let lock = NSLock()

    @ObservationIgnored private var inputs: [AVCaptureDevice.Position: AVCaptureDeviceInput] = [:]
    @ObservationIgnored private var outputs: [AVCaptureDevice.Position: AVCaptureVideoDataOutput] = [:]
    @ObservationIgnored private var consumers: [AVCaptureDevice.Position: NSHashTable<CameraSource>] = [:]
    @ObservationIgnored private var latestBuffers: [AVCaptureDevice.Position: CVPixelBuffer] = [:]

    // External / UVC capture path — keyed by AVCaptureDevice.uniqueID so
    // multiple cards on the same USB-C hub can be addressed independently.
    // Mirrors the built-in-camera storage above but on a different key type.
    @ObservationIgnored private var externalInputs: [String: AVCaptureDeviceInput] = [:]
    @ObservationIgnored private var externalOutputs: [String: AVCaptureVideoDataOutput] = [:]
    @ObservationIgnored private var externalConsumers: [String: NSHashTable<ExternalCameraSource>] = [:]
    @ObservationIgnored private var externalLatestBuffers: [String: CVPixelBuffer] = [:]

    /// Currently-attached external / UVC capture devices, refreshed as
    /// devices are plugged or unplugged. Observed by the source picker so
    /// the UVC section updates live. Published on the main thread.
    private(set) var availableExternalDevices: [AVCaptureDevice] = []
    @ObservationIgnored private var externalDiscovery: AVCaptureDevice.DiscoverySession?
    @ObservationIgnored private var externalDiscoveryObs: NSKeyValueObservation?

    // Live rotation tracking. RotationCoordinator emits a horizon-level angle
    // that updates as the device rotates (landscape↔portrait), and we KVO it
    // to keep `connection.videoRotationAngle` in sync. Without this the camera
    // is locked to whatever orientation the device was in at attach time.
    @ObservationIgnored private var rotationCoordinators: [AVCaptureDevice.Position: Any] = [:]
    @ObservationIgnored private var rotationObservations: [AVCaptureDevice.Position: NSKeyValueObservation] = [:]


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

        startExternalDiscovery()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        externalDiscoveryObs?.invalidate()
    }

    // MARK: - External / UVC discovery

    /// Builds a DiscoverySession that watches only external devices and
    /// publishes its current `devices` list to `availableExternalDevices`
    /// via KVO. Updates fire on hot-plug (HDMI capture card connect /
    /// disconnect) without polling.
    private func startExternalDiscovery() {
        var types: [AVCaptureDevice.DeviceType] = [.external]
        if #available(iOS 17.0, macCatalyst 17.0, *) {
            types.append(.continuityCamera)
        }
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: .video, position: .unspecified
        )
        externalDiscovery = session
        let initial = session.devices
        DispatchQueue.main.async { [weak self] in
            self?.availableExternalDevices = initial
        }
        externalDiscoveryObs = session.observe(\.devices, options: [.new]) { [weak self] s, _ in
            let devs = s.devices
            DispatchQueue.main.async {
                self?.availableExternalDevices = devs
                self?.handleExternalDeviceListChange(devs)
            }
        }
    }

    /// Called when the OS reports the list of attached external devices
    /// changed. If an active external source's device just disappeared,
    /// detach it cleanly so the session doesn't stay wedged on a missing
    /// input. Built-in cameras are unaffected.
    private func handleExternalDeviceListChange(_ devices: [AVCaptureDevice]) {
        let attachedIDs = Set(devices.map { $0.uniqueID })
        queue.async { [weak self] in
            guard let self = self else { return }
            let knownIDs = Set(self.externalInputs.keys)
            for missing in knownIDs.subtracting(attachedIDs) {
                self.detachExternalInput(uniqueID: missing)
            }
        }
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
        rotationObservations[position]?.invalidate()
        rotationObservations.removeValue(forKey: position)
        rotationCoordinators.removeValue(forKey: position)
    }

    func latestBuffer(for position: AVCaptureDevice.Position) -> CVPixelBuffer? {
        lock.lock(); defer { lock.unlock() }
        return latestBuffers[position]
    }

    // MARK: - External / UVC public API

    func registerExternal(_ source: ExternalCameraSource, uniqueID: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.attachExternalInputIfNeeded(uniqueID: uniqueID)

            if self.externalConsumers[uniqueID] == nil {
                self.externalConsumers[uniqueID] = NSHashTable<ExternalCameraSource>.weakObjects()
            }
            self.externalConsumers[uniqueID]?.add(source)

            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func unregisterExternal(_ source: ExternalCameraSource, uniqueID: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.externalConsumers[uniqueID]?.remove(source)
            let stillUsed = (self.externalConsumers[uniqueID]?.count ?? 0) > 0

            // External devices must always detach on zero consumers — they
            // can be unplugged any moment, and an idle attached input would
            // wedge the session if the cable goes away. Multi-cam fast-path
            // benefit doesn't apply since the user can't switch "back" to a
            // disconnected card.
            if !stillUsed {
                self.detachExternalInput(uniqueID: uniqueID)
            }

            let totalBuiltIn = self.consumers.values.reduce(0) { $0 + $1.count }
            let totalExternal = self.externalConsumers.values.reduce(0) { $0 + $1.count }
            if totalBuiltIn + totalExternal == 0 && self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func latestBuffer(forUniqueID uniqueID: String) -> CVPixelBuffer? {
        lock.lock(); defer { lock.unlock() }
        return externalLatestBuffers[uniqueID]
    }

    private func attachExternalInputIfNeeded(uniqueID: String) {
        if externalInputs[uniqueID] != nil { return }

        // Look the device up fresh — discoveredDevices may have changed
        // since the user picked it (hot-plug). If the device disappeared,
        // we silently bail; the source stays inactive until reconnect.
        let device: AVCaptureDevice? = {
            var types: [AVCaptureDevice.DeviceType] = [.external]
            if #available(iOS 17.0, macCatalyst 17.0, *) {
                types.append(.continuityCamera)
            }
            return AVCaptureDevice.DiscoverySession(
                deviceTypes: types, mediaType: .video, position: .unspecified
            ).devices.first(where: { $0.uniqueID == uniqueID })
        }()
        guard let device = device else {
            NSLog("[CameraHub] external device not found uniqueID=%@", uniqueID)
            return
        }

        // Pick a multi-cam-compatible format when available so the external
        // input can run alongside a built-in camera on iPad Pro.
        if isMultiCamSupported,
           let format = device.formats.first(where: { $0.isMultiCamSupported }) {
            do {
                try device.lockForConfiguration()
                device.activeFormat = format
                device.unlockForConfiguration()
            } catch {
                NSLog("[CameraHub] ext format lock failed: %@", error.localizedDescription)
            }
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            NSLog("[CameraHub] ext input err: %@", error.localizedDescription)
            return
        }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)

        session.beginConfiguration()
        guard session.canAddInput(input) else {
            NSLog("[CameraHub] ext canAddInput false uniqueID=%@", uniqueID)
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        guard session.canAddOutput(output) else {
            NSLog("[CameraHub] ext canAddOutput false uniqueID=%@", uniqueID)
            session.removeInput(input)
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        session.commitConfiguration()

        externalInputs[uniqueID] = input
        externalOutputs[uniqueID] = output
        NSLog("[CameraHub] attached external %@ uniqueID=%@", device.localizedName, uniqueID)
    }

    private func detachExternalInput(uniqueID: String) {
        session.beginConfiguration()
        if let input = externalInputs[uniqueID] {
            session.removeInput(input)
            externalInputs.removeValue(forKey: uniqueID)
        }
        if let output = externalOutputs[uniqueID] {
            session.removeOutput(output)
            externalOutputs.removeValue(forKey: uniqueID)
        }
        session.commitConfiguration()
        lock.lock()
        externalLatestBuffers.removeValue(forKey: uniqueID)
        lock.unlock()
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
            for (uid, hashTable) in self.externalConsumers where hashTable.count > 0 {
                if self.externalInputs[uid] == nil {
                    self.attachExternalInputIfNeeded(uniqueID: uid)
                }
            }
            let total = self.consumers.values.reduce(0) { $0 + $1.count }
                      + self.externalConsumers.values.reduce(0) { $0 + $1.count }
            if total > 0 && !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    // MARK: - Internal

    private func attachInputIfNeeded(position: AVCaptureDevice.Position) {
        if inputs[position] != nil { return }

        var allDeviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInUltraWideCamera,
            .builtInTelephotoCamera,
            .builtInDualCamera,
            .builtInTripleCamera,
            .builtInTrueDepthCamera,
            .external
        ]
        // Continuity Camera (iPhone-as-webcam) on Catalyst / macOS. Type
        // is unavailable on iOS proper, so it's gated by availability.
        if #available(macCatalyst 17.0, iOS 17.0, *) {
            allDeviceTypes.append(.continuityCamera)
        }

        let discovered = AVCaptureDevice.DiscoverySession(
            deviceTypes: allDeviceTypes,
            mediaType: .video,
            position: position
        ).devices

        // On Mac Catalyst, almost all webcams (Studio Display, USB UVC,
        // Continuity Camera) report position `.unspecified` because the
        // front/back metaphor is iPad/iPhone-specific. Filtering by
        // position would reject every device. We instead grab the first
        // camera we can find — the user's "front vs back" channel choice
        // becomes a no-op on Mac, but at least the channel gets video.
        let device: AVCaptureDevice? = {
            if let d = discovered.first { return d }
            #if targetEnvironment(macCatalyst)
            // Mac fallback: take any camera, regardless of position.
            return AVCaptureDevice.DiscoverySession(
                deviceTypes: allDeviceTypes, mediaType: .video, position: .unspecified
            ).devices.first
            #else
            return AVCaptureDevice.DiscoverySession(
                deviceTypes: allDeviceTypes, mediaType: .video, position: .unspecified
            ).devices.first(where: { $0.position == position })
            #endif
        }()

        guard let device = device else {
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
            // Selfie-style mirroring on front cam — what users expect from
            // a VJ feed of themselves (raise your right hand → it appears
            // on screen-right). Back cam stays unmirrored.
            if position == .front, conn.isVideoMirroringSupported {
                conn.automaticallyAdjustsVideoMirroring = false
                conn.isVideoMirrored = true
            }

            installRotationTracking(for: device, position: position, connection: conn)
        }
        session.commitConfiguration()

        inputs[position] = input
        outputs[position] = output
        NSLog("[CameraHub] attached %@ pos=%d type=%@", device.localizedName, position.rawValue, device.deviceType.rawValue)
    }

    /// Wire `connection.videoRotationAngle` to the device's live horizon-level
    /// capture angle. The coordinator pushes new values via KVO whenever the
    /// device rotates (landscape↔portrait), so frames stay upright without
    /// re-attaching the input.
    ///
    /// On platforms / OS versions without `RotationCoordinator` (Catalyst
    /// pre-17, etc.) we fall back to a static 0° angle — the prior 180°
    /// iPad-TrueDepth hack is gone; the coordinator gives the correct value.
    private func installRotationTracking(for device: AVCaptureDevice,
                                         position: AVCaptureDevice.Position,
                                         connection: AVCaptureConnection) {
        let initial: CGFloat
        if #available(iOS 17.0, macCatalyst 17.0, macOS 14.0, *) {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
            initial = coordinator.videoRotationAngleForHorizonLevelCapture
            rotationCoordinators[position] = coordinator
            // KVO lets us follow device rotation without re-attaching inputs.
            // Capture `position` weakly via a closure; the observation is
            // retained in `rotationObservations` for lifetime.
            let obs = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { [weak self] _, change in
                guard let self = self, let angle = change.newValue else { return }
                self.queue.async { [weak self] in
                    guard let self = self,
                          let out = self.outputs[position],
                          let conn = out.connection(with: .video) else { return }
                    if conn.isVideoRotationAngleSupported(angle) {
                        conn.videoRotationAngle = angle
                    }
                }
            }
            rotationObservations[position] = obs
        } else {
            initial = 0
        }

        if connection.isVideoRotationAngleSupported(initial) {
            connection.videoRotationAngle = initial
        } else if connection.isVideoRotationAngleSupported(0) {
            connection.videoRotationAngle = 0
        }
        NSLog("[CameraHub] pos=%d type=%@ rotation=%.0f° mirrored=%d (coordinator-tracked)",
              position.rawValue, device.deviceType.rawValue, Double(initial),
              connection.isVideoMirrored ? 1 : 0)
    }

    // MARK: - Sample buffer delegate

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // Resolve which input this output belongs to. First check the
        // built-in (position-keyed) outputs, then the external (uniqueID-
        // keyed) outputs. Each AVCaptureVideoDataOutput is unique so the
        // first match wins.
        for (pos, out) in outputs where out === output {
            lock.lock()
            latestBuffers[pos] = pb
            lock.unlock()
            return
        }
        for (uid, out) in externalOutputs where out === output {
            lock.lock()
            externalLatestBuffers[uid] = pb
            lock.unlock()
            return
        }
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
                      + self.externalConsumers.values.reduce(0) { $0 + $1.count }
            if total > 0 && !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }
}
