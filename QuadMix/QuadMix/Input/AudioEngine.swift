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

    private(set) var isRunning = false

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
        guard !isRunning else { return }

        // Just start — permission is handled by the system dialog automatically
        // on Mac Catalyst when we access the input node
        startEngine()
    }

    private static var didConfigureAudioSession = false

    private func startEngine() {
        #if !targetEnvironment(macCatalyst)
        // Configure the shared audio session ONCE at first start. Re-running
        // setCategory after the AVCaptureSession has the camera active fires
        // an audio session interruption that takes the camera down — so do
        // it lazily and only once per process.
        if !Self.didConfigureAudioSession {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .mixWithOthers])
                try session.setActive(true)
                Self.didConfigureAudioSession = true
            } catch {
                NSLog("[AudioEngine] Audio session error: %@", error.localizedDescription)
            }
        }
        #endif

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
                NSLog("[AudioEngine] Started OK on retry")
            } catch {
                NSLog("[AudioEngine] Retry failed: %@", error.localizedDescription)
                isRunning = false
            }
        }
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isRunning = false
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

        // Apply Hann window into the pre-allocated `windowed` buffer.
        // Zero out tail of `windowed` if last buffer was longer than `count`.
        for j in 0..<count { windowed[j] = channelData[j] * window[j] }
        if count < fftSize {
            for j in count..<fftSize { windowed[j] = 0 }
        }

        // FFT — reuse pre-allocated buffers; clear imaginary inputs each call.
        for j in 0..<fftSize {
            realIn[j] = windowed[j]
            imagIn[j] = 0
        }

        vDSP_DFT_Execute(setup, &realIn, &imagIn, &realOut, &imagOut)

        // Magnitude into pre-allocated `magnitudes`.
        for i in 0..<halfFFT {
            magnitudes[i] = sqrtf(realOut[i] * realOut[i] + imagOut[i] * imagOut[i])
        }

        // Normalize
        var maxMag: Float = 0
        vDSP_maxv(magnitudes, 1, &maxMag, vDSP_Length(halfFFT))
        if maxMag > 0.001 {
            var scale = 1.0 / maxMag
            vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(halfFFT))
        }

        // Compute band levels
        let binWidth = sampleRate / Float(fftSize)

        func bandLevel(low: Float, high: Float) -> Float {
            let startBin = max(0, Int(low / binWidth))
            let endBin = min(halfFFT - 1, Int(high / binWidth))
            guard endBin > startBin else { return 0 }
            let slice = Array(magnitudes[startBin..<endBin])
            var mean: Float = 0
            vDSP_meanv(slice, 1, &mean, vDSP_Length(slice.count))
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
