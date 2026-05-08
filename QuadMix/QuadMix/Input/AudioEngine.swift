import AVFoundation
import Accelerate

/// Real-time audio capture + FFT analysis.
/// Splits the spectrum into bands that channels can subscribe to.
@Observable
final class AudioEngine {
    private var engine: AVAudioEngine?
    private var fftSetup: vDSP_DFT_Setup?
    private let fftSize = 1024

    // Pre-allocated work buffers — the audio render thread MUST NOT malloc
    // each callback (priority inversion + glitches). Reused every callback.
    // @ObservationIgnored because @Observable's macro doesn't allow `lazy`.
    @ObservationIgnored private var window: [Float] = []
    @ObservationIgnored private var windowed: [Float] = []
    @ObservationIgnored private var realIn: [Float] = []
    @ObservationIgnored private var imagIn: [Float] = []
    @ObservationIgnored private var realOut: [Float] = []
    @ObservationIgnored private var imagOut: [Float] = []
    @ObservationIgnored private var magnitudes: [Float] = []

    /// Raw spectrum magnitude (0-1) for 512 bins
    private(set) var spectrum: [Float] = []

    /// Pre-computed band levels (0-1), updated every audio buffer
    private(set) var subBass: Float = 0    // 20-60 Hz
    private(set) var bass: Float = 0       // 60-250 Hz
    private(set) var lowMid: Float = 0     // 250-500 Hz
    private(set) var mid: Float = 0        // 500-2000 Hz
    private(set) var highMid: Float = 0    // 2000-4000 Hz
    private(set) var high: Float = 0       // 4000-8000 Hz
    private(set) var brilliance: Float = 0 // 8000-20000 Hz

    /// Overall level (RMS)
    private(set) var level: Float = 0

    /// Consistent snapshot of all bands + spectrum, captured under a lock.
    /// Readers that need a single coherent set (e.g. AudioVisualizerSource
    /// composing LOW/MID/HIGH/FULL bands in one frame) should use this
    /// instead of reading seven properties sequentially — those reads can
    /// otherwise straddle a writer update from the audio thread, mixing
    /// frame-N's bass with frame-N+1's high.
    struct BandSnapshot {
        var subBass: Float = 0
        var bass: Float = 0
        var lowMid: Float = 0
        var mid: Float = 0
        var highMid: Float = 0
        var high: Float = 0
        var brilliance: Float = 0
        var level: Float = 0
        var spectrum: [Float] = []
    }
    @ObservationIgnored private let snapshotLock = NSLock()
    @ObservationIgnored private var _snapshot = BandSnapshot()

    func snapshot() -> BandSnapshot {
        snapshotLock.lock(); defer { snapshotLock.unlock() }
        return _snapshot
    }

    private(set) var isRunning = false

    /// Why the audio engine isn't producing data — surfaced to the UI so
    /// AudioReact / Visualizer panels can show "Mic permission needed"
    /// or "No input format" instead of silently outputting zeros.
    enum InputState {
        case idle               // not yet started
        case running            // capturing successfully
        case permissionDenied   // user said no
        case noInputFormat      // sampleRate=0 / no mic hardware on this Mac
        case startFailed        // engine.start() threw
    }
    private(set) var inputState: InputState = .idle

    init() {
        fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD)
        // Pre-allocate FFT work buffers
        window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        windowed = [Float](repeating: 0, count: fftSize)
        realIn = [Float](repeating: 0, count: fftSize)
        imagIn = [Float](repeating: 0, count: fftSize)
        realOut = [Float](repeating: 0, count: fftSize)
        imagOut = [Float](repeating: 0, count: fftSize)
        magnitudes = [Float](repeating: 0, count: fftSize / 2)
    }

    deinit {
        stop()
        if let setup = fftSetup { vDSP_DFT_DestroySetup(setup) }
    }

    func start() {
        NSLog("[AudioEngine] start() called, isRunning=%d", isRunning ? 1 : 0)
        guard !isRunning else { return }

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        NSLog("[AudioEngine] mic auth status = %d", micStatus.rawValue)
        switch micStatus {
        case .denied, .restricted:
            // User said no — surface to the UI; don't try to start, that
            // produces sampleRate=0 and the engine spins on silence.
            NSLog("[AudioEngine] Permission DENIED/RESTRICTED — bailing")
            inputState = .permissionDenied
            return
        case .authorized:
            NSLog("[AudioEngine] Authorized; calling startEngine")
            startEngine()
        case .notDetermined:
            // First launch: explicitly request access. On iOS,
            // AVAudioEngine.inputNode triggers the prompt on its own; on
            // macOS/Catalyst it doesn't, so the engine starts with no
            // input bound and `inputFormat` returns sampleRate=0
            // (CoreAudio AUIOBase Initialize error -50). Calling
            // requestAccess explicitly drives the TCC prompt and only
            // then do we touch the engine.
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if granted {
                        self.startEngine()
                    } else {
                        self.inputState = .permissionDenied
                    }
                }
            }
        @unknown default:
            startEngine()
        }
    }

    private static var didConfigureAudioSession = false

    private func startEngine() {
        // Configure the shared audio session ONCE at first start. Re-running
        // setCategory after the AVCaptureSession has the camera active fires
        // an audio session interruption that takes the camera down — so do
        // it lazily and only once per process.
        //
        // This used to be gated `#if !targetEnvironment(macCatalyst)` on the
        // theory that AVAudioSession is iOS-only. It isn't — Catalyst does
        // ship AVAudioSession, and without setCategory(.playAndRecord) the
        // engine starts up with no input route bound, producing
        // `inputFormat(forBus:0).sampleRate == 0` and a CoreAudio
        // `AUIOBase Initialize error=-50` (kAudio_ParamError). Calling
        // setCategory tells CoreAudio to wire the default input device
        // into the engine on Mac the same way it does on iPad.
        if !Self.didConfigureAudioSession {
            let session = AVAudioSession.sharedInstance()
            do {
                #if targetEnvironment(macCatalyst)
                // .defaultToSpeaker isn't valid on Mac, and .mixWithOthers
                // is the default behavior. Just .playAndRecord is enough
                // to wire up the input route.
                try session.setCategory(.playAndRecord)
                #else
                try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .mixWithOthers])
                #endif
                try session.setActive(true)
                Self.didConfigureAudioSession = true
            } catch {
                NSLog("[AudioEngine] Audio session error: %@", error.localizedDescription)
            }
        }

        engine = AVAudioEngine()
        guard let engine = engine else { return }

        let input = engine.inputNode

        // Try outputFormat first (standard), then inputFormat as fallback
        var format = input.outputFormat(forBus: 0)
        if format.sampleRate == 0 || format.channelCount == 0 {
            format = input.inputFormat(forBus: 0)
        }

        NSLog("[AudioEngine] Using format: sr=%.0f ch=%d", format.sampleRate, format.channelCount)

        guard format.sampleRate > 0 && format.channelCount > 0 else {
            NSLog("[AudioEngine] No valid audio input format available")
            inputState = .noInputFormat
            return
        }

        let halfFFT = fftSize / 2

        // Install tap with nil format to let the system choose
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize), format: nil) { [weak self] buffer, _ in
            guard let self = self else { return }
            let sr = Float(buffer.format.sampleRate)
            self.processBuffer(buffer, sampleRate: sr > 0 ? sr : Float(format.sampleRate), halfFFT: halfFFT)
        }

        do {
            try engine.start()
            isRunning = true
            inputState = .running
            NSLog("[AudioEngine] Started OK, sr=%.0f", format.sampleRate)
        } catch {
            NSLog("[AudioEngine] Start failed: %@", error.localizedDescription)
            // Try once more without the tap format constraint
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize), format: format) { [weak self] buffer, _ in
                guard let self = self else { return }
                self.processBuffer(buffer, sampleRate: Float(format.sampleRate), halfFFT: halfFFT)
            }
            do {
                try engine.start()
                isRunning = true
                inputState = .running
                NSLog("[AudioEngine] Started OK on retry")
            } catch {
                NSLog("[AudioEngine] Retry failed: %@", error.localizedDescription)
                isRunning = false
                inputState = .startFailed
            }
        }
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isRunning = false
        inputState = .idle
    }

    private func processBuffer(_ buffer: AVAudioPCMBuffer, sampleRate: Float, halfFFT: Int) {
        guard let channelData = buffer.floatChannelData?[0],
              let setup = fftSetup else { return }

        let frameCount = Int(buffer.frameLength)
        let count = min(frameCount, fftSize)

        // RMS level
        var rms: Float = 0
        vDSP_measqv(channelData, 1, &rms, vDSP_Length(count))
        rms = sqrtf(rms)

        // DC removal: subtract the buffer mean before windowing. Without
        // this, any DC offset in the mic signal produces a huge bin-0
        // magnitude that dominates the post-normalize spectrum and pegs
        // every low-frequency bar at 100%.
        var dcMean: Float = 0
        vDSP_meanv(channelData, 1, &dcMean, vDSP_Length(count))
        // Apply Hann window AND DC-correction in one pass.
        for j in 0..<count { windowed[j] = (channelData[j] - dcMean) * window[j] }
        if count < fftSize {
            for j in count..<fftSize { windowed[j] = 0 }
        }

        // FFT — reuse pre-allocated buffers; clear imaginary inputs each call.
        for j in 0..<fftSize {
            realIn[j] = windowed[j]
            imagIn[j] = 0
        }

        vDSP_DFT_Execute(setup, &realIn, &imagIn, &realOut, &imagOut)

        // Magnitude into pre-allocated `magnitudes` — Accelerate's
        // `vDSP_zvabs` (complex absolute value) is ~5–8x faster than the
        // Swift loop that was here.
        realOut.withUnsafeMutableBufferPointer { rBuf in
            imagOut.withUnsafeMutableBufferPointer { iBuf in
                var split = DSPSplitComplex(realp: rBuf.baseAddress!, imagp: iBuf.baseAddress!)
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(halfFFT))
            }
        }

        // Belt-and-suspenders: also zero the bottom two bins explicitly.
        // DC removal above kills bin 0; bin 1 still gets some spectral
        // leakage from any sub-43 Hz content the FFT can't resolve, and
        // including it in the normalize-by-max squashes the rest of the
        // spectrum.
        magnitudes[0] = 0
        if halfFFT > 1 { magnitudes[1] = 0 }

        // Normalize
        var maxMag: Float = 0
        vDSP_maxv(magnitudes, 1, &maxMag, vDSP_Length(halfFFT))
        if maxMag > 0.001 {
            var scale = 1.0 / maxMag
            vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(halfFFT))
        }

        // Compute band levels — pointer-offset `vDSP_meanv` so we don't
        // allocate seven temp Arrays per audio callback (the previous
        // `Array(magnitudes[start..<end])` slice was a malloc on the
        // realtime audio thread, which is a recipe for priority inversion
        // glitches under load).
        let binWidth = sampleRate / Float(fftSize)
        let halfFFTUpper = halfFFT - 1

        func bandLevel(low: Float, high: Float) -> Float {
            let startBin = max(0, Int(low / binWidth))
            let endBin = min(halfFFTUpper, Int(high / binWidth))
            guard endBin > startBin else { return 0 }
            var mean: Float = 0
            magnitudes.withUnsafeBufferPointer { buf in
                if let base = buf.baseAddress {
                    vDSP_meanv(base + startBin, 1, &mean, vDSP_Length(endBin - startBin))
                }
            }
            return mean
        }

        // Update on main thread
        let newLevel = min(rms * 5, 1.0) // scale up for visibility
        let newSubBass = bandLevel(low: 20, high: 60)
        let newBass = bandLevel(low: 60, high: 250)
        let newLowMid = bandLevel(low: 250, high: 500)
        let newMid = bandLevel(low: 500, high: 2000)
        let newHighMid = bandLevel(low: 2000, high: 4000)
        let newHigh = bandLevel(low: 4000, high: 8000)
        let newBrilliance = bandLevel(low: 8000, high: 20000)
        let newSpectrum = magnitudes

        // Atomic snapshot first — covers any reader that needs a coherent
        // set of bands+spectrum from one audio frame (no torn read).
        snapshotLock.lock()
        _snapshot = BandSnapshot(
            subBass: newSubBass, bass: newBass, lowMid: newLowMid,
            mid: newMid, highMid: newHighMid, high: newHigh,
            brilliance: newBrilliance, level: newLevel, spectrum: newSpectrum
        )
        snapshotLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.level = newLevel
            self.subBass = newSubBass
            self.bass = newBass
            self.lowMid = newLowMid
            self.mid = newMid
            self.highMid = newHighMid
            self.high = newHigh
            self.brilliance = newBrilliance
            self.spectrum = newSpectrum
        }
    }

    /// Get the level for a specific band by index (0-6)
    func bandLevel(at index: Int) -> Float {
        switch index {
        case 0: return subBass
        case 1: return bass
        case 2: return lowMid
        case 3: return mid
        case 4: return highMid
        case 5: return high
        case 6: return brilliance
        default: return level
        }
    }

    static let bandNames = ["Sub Bass", "Bass", "Low Mid", "Mid", "High Mid", "High", "Brilliance"]
    static let bandRanges = ["20-60Hz", "60-250Hz", "250-500Hz", "500-2kHz", "2-4kHz", "4-8kHz", "8-20kHz"]
}
