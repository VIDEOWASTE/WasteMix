import CoreVideo
import CoreGraphics
import QuartzCore
import UIKit

/// Renders the live audio input (mic) as a video source — FFT histogram,
/// oscilloscope waveform, both stacked, or one of five WMP-style plasma
/// variants. Pulls data from the shared `AudioEngine` and tweakable
/// per-channel `VisualizerParams`. Triple-buffered so the GPU consumer
/// (PVW preview MTKView, compositor) never reads a half-drawn frame —
/// `latestPixelBuffer` always returns the most recently completed buffer
/// while we draw into the next slot in the ring.
final class AudioVisualizerSource: FrameProvider {
    private let style: VisualizerStyle
    private let audioEngine: AudioEngine
    private weak var channel: Channel?
    private let width = 1280
    private let height = 720

    // 3-buffer ring. `publishedIndex` points at the most recently
    // completed buffer; we draw into a different slot. Reading
    // `latestPixelBuffer` is lock-free (just reads an atomic-ish int).
    private var ring: [CVPixelBuffer] = []
    private var publishedIndex: Int = 0
    private var drawIndex: Int = 1
    private var displayLink: CADisplayLink?
    private(set) var isActive = false

    private var startTime: CFTimeInterval = 0
    private var lastFrameTime: CFTimeInterval = 0

    // Default envelope time constants for the per-FFT-bin Bars smoother
    // (`followBar`). Distinct from the user-controllable per-channel
    // envelopes — these only shape jitter on individual FFT bins.
    private static let attackTime: Float = 0.040    // seconds (1/e)
    private static let releaseTime: Float = 0.220

    // 4-channel envelope outputs. Each channel pulls from a frequency
    // band of AudioEngine (LOW = 20-250 Hz, MID = 250 Hz-2 kHz, HIGH =
    // 2-20 kHz) plus a FULL channel that follows overall RMS energy.
    // Per-channel GAIN, ATTACK, RELEASE and THRESHOLD shape each one's
    // response (see VisualizerParams.envelopes).
    private var envelopes: [Float] = [0, 0, 0, 0]

    // Active band index — set each frame from `params.reactiveBand`.
    // Single-band routing: the selected band's envelope drives EVERY
    // audio-reactive aspect of the active visualizer.
    private var activeBand: Int = 0

    // The selected band's envelope. Single-band routing means every
    // visualizer reads from this one signal — older draw code referenced
    // separate `activeLevel / activeLevel / activeLevel` views over the same
    // envelope, but they were aliases of one value so they were
    // collapsed to `activeLevel`.
    private var activeLevel: Float { envelopes[activeBand] }

    // Slow moving average of the ACTIVE band's envelope — drives kick
    // and transient detection. Single-band routing means the band the
    // user picks (LOW/MID/HIGH/FULL) is also what counts as a "kick"
    // or "transient" for every visualizer. Pick LOW → kicks fire on
    // bass hits; pick HIGH → kicks fire on hi-hat spikes.
    private var activeBandAvg: Float = 0
    private var transientPulse: Float = 0

    // Particle pool for the .particles style. Allocated once at start so
    // we don't malloc on the render thread.
    private struct Particle {
        var x: Float = 0
        var y: Float = 0
        var prevX: Float = 0   // previous position for motion trail
        var prevY: Float = 0
        var vx: Float = 0
        var vy: Float = 0
        var life: Float = 0   // 0..1, fades to 0
        var hue: Float = 0
        var size: Float = 0
        var phase: Float = 0  // per-particle sway phase
    }
    private var particles: [Particle] = []
    private var lastEmitTime: Float = 0

    // Pre-allocated low-res scratch buffer for the demoscene plasma effect.
    // 160x90 is enough resolution to look smooth when CG bilinear-upscales
    // it to 1280x720, and keeps the per-pixel cost cheap on the CPU.
    private let plasmaW = 160
    private let plasmaH = 90
    private var plasmaPixels: [UInt8] = []

    // Per-bar smoothing for the FFT Bars style. Same asymmetric envelope
    // as the band levels — without this, individual bars flicker on noisy
    // FFT bins each frame; with it, each bar reads as a stable level that
    // bounces musically.
    private var smoothedBars: [Float] = Array(repeating: 0, count: 64)

    // WMP Classic Bars state — separate levels and peak-hold caps. Peaks
    // snap up on rise, fall slowly at a constant pixel-per-second rate
    // (the iconic Winamp/WMP behavior).
    private var wmpBarLevels: [Float] = Array(repeating: 0, count: 48)
    private var wmpBarPeaks: [Float] = Array(repeating: 0, count: 48)

    // Per-sample smoothing state for the Waveform variant — without it
    // the wave bobbed/jittered every frame because each spectrum bin was
    // sampled raw. With per-sample envelope smoothing the wave glides
    // smoothly between values.
    private var waveformSamples: [Float] = Array(repeating: 0, count: 96)

    // Lightning bolts in flight — generated on transient, decays per frame.
    private struct Bolt {
        var points: [CGPoint] = []
        var life: Float = 0
        var hue: Float = 0
    }
    private var bolts: [Bolt] = []

    // Random-cycle state. When `style == .random`, render() resolves to
    // `currentRandomStyle`, which auto-changes every ~18 seconds OR
    // earlier on a strong bass kick (if at least 8 seconds have passed)
    // so transitions feel musical instead of arbitrary.
    private var currentRandomStyle: VisualizerStyle = .plasma
    private var lastStyleSwitch: CFTimeInterval = 0
    private static let randomCycleSeconds: CFTimeInterval = 18.0
    private static let randomMinHoldSeconds: CFTimeInterval = 8.0

    // Per-orb rotation direction (+1 / -1) for the WMP: Orbs variant.
    // Bass kicks flip a random orb's direction so the dance-floor feel
    // stays unpredictable instead of locked into one direction forever.
    private var orbDirections: [Float] = [1, -1, 1, -1, 1, -1]
    private var lastOrbFlipTime: Float = -1

    // 3D solids state for the Geometry variant. Each solid has its own
    // shape type, hue, orbit phase, rotation axes + rates, and base size.
    // Initialized lazily in drawGeometry on first call.
    private struct Solid3D {
        var shapeIdx: Int       // 0 = cube, 1 = tetrahedron, 2 = octahedron
        var hue: Float
        var orbitPhase: Float
        var orbitFreq: Float
        var orbitRadiusN: Float // 0..1 fraction of frame half-min-dim
        var orbitElev: Float    // y/x ellipse factor
        var rotX: Float, rotY: Float, rotZ: Float
        var rotSpeedX: Float, rotSpeedY: Float, rotSpeedZ: Float
        var sizeN: Float        // 0..1 fraction of base size
    }
    private var solids: [Solid3D] = []
    private var lastSolidShapeChange: Float = -1

    init(style: VisualizerStyle, channel: Channel?, audioEngine: AudioEngine) {
        self.style = style
        self.channel = channel
        self.audioEngine = audioEngine

        // 3-buffer ring — IOSurface-backed so the texture cache can wrap
        // them as Metal textures cheaply.
        let attrs: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        var bufs: [CVPixelBuffer] = []
        for _ in 0..<3 {
            var pb: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)
            if let pb = pb { bufs.append(pb) }
        }
        self.ring = bufs

        // Pre-allocate particle pool (max 200, density param scales actual
        // emission so unused slots stay at life=0).
        self.particles = Array(repeating: Particle(), count: 200)
        // Pre-allocate plasma scratch (BGRA 8-bit per channel).
        self.plasmaPixels = [UInt8](repeating: 0, count: plasmaW * plasmaH * 4)
    }

    deinit { stop() }

    var latestPixelBuffer: CVPixelBuffer? {
        guard !ring.isEmpty else { return nil }
        return ring[publishedIndex]
    }

    func start() {
        guard !isActive else { return }
        audioEngine.start()
        isActive = true
        startTime = CACurrentMediaTime()
        lastFrameTime = startTime
        let proxy = DisplayLinkProxy(self)
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick))
        // Run at the device's full refresh rate (60Hz on most iPads, 120Hz
        // on ProMotion) — the per-frame cost of every variant is well
        // under the budget and doubling the frame rate halves perceived
        // jitter on motion. dt-based decay means the envelope shape is
        // identical regardless of refresh rate.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        isActive = false
        displayLink?.invalidate()
        displayLink = nil
    }

    /// Cached default for the silent-channel path. Allocating a new
    /// `VisualizerParams()` per frame called `defaultEnvelopes()` four
    /// times per call — wasteful when no channel is bound.
    private static let defaultParams = VisualizerParams()

    private func currentParams() -> VisualizerParams {
        return channel?.visualizerParams ?? Self.defaultParams
    }

    /// Asymmetric attack/release envelope follower. Frame-rate-independent
    /// (uses real `dt`); fast attack catches the leading edge of a hit,
    /// slower release lets the value coast smoothly back toward zero.
    @inline(__always)
    private func followEnvelope(current: Float, target: Float, dt: Float) -> Float {
        let tau = target > current ? Self.attackTime : Self.releaseTime
        let alpha = 1 - exp(-dt / tau)
        return current + (target - current) * alpha
    }

    /// Per-bar attack/release follower using the same constants as the
    /// band-level envelopes so all visualizers feel consistent.
    @inline(__always)
    private func followBar(current: Float, target: Float, dt: Float) -> Float {
        return followEnvelope(current: current, target: target, dt: dt)
    }

    /// Update the 5-channel envelope system. Each channel pulls its
    /// frequency band from AudioEngine, applies user gain + threshold
    /// gate, then runs through an asymmetric attack/release follower
    /// with per-channel time constants. Result lives in `envelopes[i]`
    /// and is read by every audio-reactive draw method.
    private func updateEnvelopes(dt: Float, params: VisualizerParams) {
        // Pull a single coherent snapshot under the audio engine's lock so
        // the four bands below all come from the same audio frame — the
        // older code read seven properties sequentially, letting an audio
        // callback in between mix frame-N's bass with frame-N+1's high.
        let s = audioEngine.snapshot()
        // Raw band inputs from AudioEngine, mapped to the 4 channels.
        // LOW combines subBass + bass; MID combines lowMid/mid/highMid;
        // HIGH combines high + brilliance; FULL is overall RMS level.
        let raw: [Float] = [
            (s.subBass + s.bass) * 0.5,                      // 0 LOW
            (s.lowMid + s.mid + s.highMid) / 3.0,            // 1 MID
            (s.high + s.brilliance) * 0.5,                   // 2 HIGH
            s.level                                           // 3 FULL
        ]
        // Defensive: VisualizerParams should always have 4 envelopes,
        // but if a malformed preset slipped in, fall back gracefully.
        let envCfg = params.envelopes.count == 4
            ? params.envelopes
            : VisualizerParams.defaultEnvelopes()
        // Global smoothing macro — exponential mapping (0 → ×0.33, 0.5 →
        // ×1.0, 1.0 → ×3.0) so each step roughly halves or doubles the
        // perceived response time.
        let smoothingMul: Float = pow(3, params.smoothing * 2 - 1)
        for i in 0..<4 {
            let cfg = envCfg[i]
            let scaled = raw[i] * cfg.gain
            let gated = scaled > cfg.threshold ? scaled : 0
            let attackTau: Float = (0.005 + cfg.attack * 0.145) * smoothingMul
            let releaseTau: Float = (0.030 + cfg.release * 1.470) * smoothingMul
            let tau = gated > envelopes[i] ? attackTau : releaseTau
            let alpha = 1 - exp(-dt / max(tau, 0.001))
            envelopes[i] = envelopes[i] + (gated - envelopes[i]) * alpha
        }
    }

    /// Public read-only accessor for the live envelope outputs — the UI
    /// uses this to render the 5 little input meters in the audio panel.
    /// Returns a snapshot copy so SwiftUI observation works cleanly.
    var liveEnvelopes: [Float] { envelopes }

    /// For a given FFT bin index, return which envelope band it belongs
    /// to (LOW=0, MID=1, HIGH=2). FULL (3) is intentionally not returned
    /// here — it has no frequency range. Used by the per-bin variants
    /// (FFT Bars + WMP Bars) so each bar's height gets multiplied by its
    /// band's GAIN and gated by its THRESHOLD.
    @inline(__always)
    private func envelopeBandForBin(_ bin: Int) -> Int {
        // FFT size 1024 @ 44.1kHz → bin width ≈ 43 Hz.
        let freq = Float(bin) * 43.0
        if freq < 250 { return 0 }     // LOW
        if freq < 2000 { return 1 }    // MID
        return 2                       // HIGH
    }

    /// Apply the envelope-band's GAIN + THRESHOLD to a raw FFT magnitude
    /// for one bin. Used by FFT Bars + WMP Bars to honor the per-channel
    /// audio reactivity params. When FULL is the active reactive band,
    /// FULL's gain is also multiplied in as a master post-band scale —
    /// gives the user a "global makeup gain" they can dial via FULL.
    @inline(__always)
    private func applyBandEnvelope(magnitude: Float, bin: Int, params: VisualizerParams) -> Float {
        let bandIdx = envelopeBandForBin(bin)
        guard params.envelopes.count >= 4 else { return magnitude }
        let cfg = params.envelopes[bandIdx]
        let scaled = magnitude * cfg.gain
        let gated = scaled > cfg.threshold ? scaled : 0
        // FULL gain acts as a global multiplier on top of per-bin band
        // shaping — so users can dial FULL's GAIN to attenuate or boost
        // every bin without rebalancing the LOW/MID/HIGH gains.
        let fullGain = params.envelopes[3].gain
        return gated * fullGain
    }

    /// Stroke a CGPath with a 4-pass additive bloom — wide+faint outer
    /// halo, then increasingly tight & bright passes, ending with a
    /// crisp core stroke. This is THE thing that gave classic WMP /
    /// Winamp visualizers their characteristic "neon glow on black"
    /// look. Every shape-based plasma variant now uses this.
    private func strokeWithGlow(ctx: CGContext, path: CGPath,
                                color: UIColor, baseWidth: CGFloat,
                                intensity: CGFloat = 1.0) {
        let prevBlend = CGBlendMode.normal // we restore explicitly
        ctx.setBlendMode(.plusLighter)
        // 4 passes, each tighter & brighter than the last.
        let passes: [(mul: CGFloat, alpha: CGFloat)] = [
            (5.0, 0.10),   // outer halo
            (2.8, 0.20),
            (1.6, 0.40),
            (0.85, 1.0)    // crisp core
        ]
        for pass in passes {
            let a = min(1.0, pass.alpha * intensity)
            ctx.setStrokeColor(color.withAlphaComponent(a).cgColor)
            ctx.setLineWidth(baseWidth * pass.mul)
            ctx.addPath(path)
            ctx.strokePath()
        }
        ctx.setBlendMode(prevBlend)
    }

    /// Fill an ellipse with the same 4-pass additive bloom — used for
    /// peak caps, particles, glow points, etc.
    private func fillCircleWithGlow(ctx: CGContext, center: CGPoint,
                                    radius: CGFloat, color: UIColor,
                                    intensity: CGFloat = 1.0) {
        ctx.setBlendMode(.plusLighter)
        let passes: [(mul: CGFloat, alpha: CGFloat)] = [
            (4.5, 0.10),
            (2.6, 0.22),
            (1.5, 0.45),
            (1.0, 1.0)
        ]
        for pass in passes {
            let a = min(1.0, pass.alpha * intensity)
            ctx.setFillColor(color.withAlphaComponent(a).cgColor)
            let r = radius * pass.mul
            ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r,
                                       width: r * 2, height: r * 2))
        }
        ctx.setBlendMode(.normal)
    }

    // MARK: - Kick detection
    //
    // Used to be inlined verbatim in 5+ draw methods. The threshold ratio
    // shrinks as the user dials kickSensitivity up, so a setting of 1.0
    // makes the visualizer react to gentler peaks.
    private func detectKick(params: VisualizerParams) -> Bool {
        let kickRatio: Float = 1.9 - params.kickSensitivity * 0.8
        return activeLevel > activeBandAvg * kickRatio && activeLevel > 0.005
    }

    fileprivate func render() {
        guard !ring.isEmpty else { return }

        // Real frame-time delta — every per-frame decay below is computed
        // from this so envelope shapes / particle lifespan / transient
        // hang times stay identical whether we're running at 30, 60, or
        // 120Hz.
        let now = CACurrentMediaTime()
        let dtRaw = Float(now - lastFrameTime)
        // Clamp to avoid huge dt spikes after a hitch / backgrounding.
        let dt = max(0.001, min(0.1, dtRaw))
        lastFrameTime = now

        // Pull current params first — needed for envelope shaping below.
        let params = currentParams()

        // Update the user-selected reactive band — drives activeLevel /
        // Mid / High, which is what every audio-reactive draw method
        // reads. Clamp to a valid index so a malformed preset can't
        // crash us.
        activeBand = max(0, min(4, params.reactiveBand))

        // Update the 5-channel LZX-style envelope system. Each channel
        // pulls a specific frequency band, applies user gain + threshold
        // gate, then runs through an asymmetric attack/release envelope
        // follower with per-channel time constants. The output is a
        // smoothed 0..1 control signal stored in `envelopes[i]`. All the
        // existing draw code reads `activeLevel / activeLevel / activeLevel`
        // which are now computed views over this array.
        updateEnvelopes(dt: dt, params: params)

        // Single-band routing: kick + transient detection both fire from
        // the ACTIVE band's envelope. Whatever band the user selected
        // is what counts as a "beat" for every visualizer — pick LOW
        // and Lightning bolts fire on bass kicks; pick HIGH and they
        // fire on hi-hat hits; pick FULL and they fire on overall
        // energy spikes. Was previously hardcoded against raw bass/high
        // regardless of selection (Lightning specifically didn't react
        // to the band tab at all).
        let activeLevel = envelopes[activeBand]
        let avgAlpha: Float = 1 - exp(-dt / 1.5)
        activeBandAvg = activeBandAvg + (activeLevel - activeBandAvg) * avgAlpha
        // Transient: active band spikes 1.3× above its slow average.
        // Tiny absolute floor keeps silence + noise from triggering.
        if activeLevel > activeBandAvg * 1.3 && activeLevel > 0.003 {
            transientPulse = 1.0
        }
        transientPulse *= exp(-dt / 0.18)

        let elapsed = Float(now - startTime)
        // Effective "speed" multiplier — params.speed is 0..1 mapped to 0.2x..3x.
        let speedMul: Float = 0.2 + params.speed * 2.8
        let scaledTime = elapsed * speedMul

        let pb = ring[drawIndex]
        CVPixelBufferLockBaseAddress(pb, [])
        defer {
            CVPixelBufferUnlockBaseAddress(pb, [])
            // Publish: the just-drawn buffer is now the freshest. Reads in
            // `latestPixelBuffer` see this update on the next access.
            publishedIndex = drawIndex
            drawIndex = (drawIndex + 1) % ring.count
            // Skip the slot the consumer is most likely currently reading
            // — the previously-published buffer. With 3 slots this works
            // out to always drawing into the slot that was published two
            // frames ago, giving the consumer a full frame of safety.
            if drawIndex == publishedIndex {
                drawIndex = (drawIndex + 1) % ring.count
            }
        }

        guard let base = CVPixelBufferGetBaseAddress(pb) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
        let cs = CGColorSpaceCreateDeviceRGB()
        let bi = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(
            data: base, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: cs, bitmapInfo: bi
        ) else { return }

        // Top-left origin to match CVPixelBuffer / video memory convention.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        // Clear to black
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Resolve `.random` to a concrete style — auto-cycles on a timer
        // and snaps to a new style on a strong bass kick (if it's been
        // at least the min-hold time since the last swap).
        let resolvedStyle: VisualizerStyle
        if style == .random {
            let timeSinceSwitch = now - lastStyleSwitch
            let isBassKick = activeLevel > activeBandAvg * 1.6 && activeLevel > 0.01
            let shouldSwitch = lastStyleSwitch == 0
                || timeSinceSwitch > Self.randomCycleSeconds
                || (isBassKick && timeSinceSwitch > Self.randomMinHoldSeconds)
            if shouldSwitch {
                let candidates = VisualizerStyle.allCases.filter {
                    $0 != .random && $0 != currentRandomStyle
                }
                currentRandomStyle = candidates.randomElement() ?? .plasma
                lastStyleSwitch = now
            }
            resolvedStyle = currentRandomStyle
        } else {
            resolvedStyle = style
        }

        switch resolvedStyle {
        case .random:
            // Already resolved above; can't reach here.
            drawPlasmaFlow(ctx: ctx, time: scaledTime, params: params)
        case .waveform:
            drawWaveform(ctx: ctx, params: params, dt: dt)
        case .plasma:
            drawPlasmaFlow(ctx: ctx, time: scaledTime, params: params)
        case .orbs:
            drawOrbs(ctx: ctx, time: scaledTime, params: params)
        case .geometry:
            drawGeometry(ctx: ctx, time: scaledTime, params: params, dt: dt)
        case .wmpBars:
            drawWMPBars(ctx: ctx, params: params, dt: dt)
        case .alchemy:
            drawAlchemy(ctx: ctx, time: scaledTime, params: params)
        case .polygons:
            drawPolygons(ctx: ctx, time: scaledTime, params: params)
        case .tunnel:
            drawTunnel(ctx: ctx, time: scaledTime, params: params)
        case .particles:
            drawParticles(ctx: ctx, time: scaledTime, params: params, dt: dt)
        case .spiral:
            drawSpiral(ctx: ctx, time: scaledTime, params: params)
        case .ribbons:
            drawRibbons(ctx: ctx, time: scaledTime, params: params)
        case .lightning:
            drawLightning(ctx: ctx, time: scaledTime, params: params, dt: dt)
        case .mandala:
            drawMandala(ctx: ctx, time: scaledTime, params: params)
        }
    }

    // MARK: - Literal styles

    private func drawWaveform(ctx: CGContext, params: VisualizerParams, dt: Float,
                              yCenter: CGFloat? = nil, amp: CGFloat? = nil) {
        let spectrum = audioEngine.spectrum
        guard spectrum.count > 8 else { return }
        let cy = yCenter ?? CGFloat(height) * 0.5
        // Bumped from 0.42 → 0.46 so peaks reach closer to the frame
        // edges (the "depth" the user wanted).
        let a = amp ?? CGFloat(height) * 0.46
        let hue = Double(params.hue.truncatingRemainder(dividingBy: 1.0))
        let baseHue = hue.isNaN ? 0.5 : 0.5 + hue * 0.5
        let intensity = Double(params.intensity) + 0.3
        let lineColor = UIColor(hue: baseHue, saturation: 0.9, brightness: min(1, 0.7 + intensity * 0.3), alpha: 1)
        let fillColor = UIColor(hue: baseHue, saturation: 0.9, brightness: min(1, 0.6 + intensity * 0.3), alpha: 0.30)

        // Pure black background so the glow reads cleanly.
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Static horizontal centerline so the wave has a clear baseline.
        let centerline = UIColor(white: 1, alpha: 0.18).cgColor
        ctx.setStrokeColor(centerline)
        ctx.setLineWidth(1)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 0, y: cy))
        ctx.addLine(to: CGPoint(x: CGFloat(width), y: cy))
        ctx.strokePath()

        // Full audible spectrum across the wave's width, log-spaced so
        // bass occupies the left third (most musical content lives
        // there). Per-bin GAIN + THRESHOLD applied via the same helper
        // the FFT bars use — so dialing LOW gain down attenuates the
        // bass portion of the wave; HIGH gain down attenuates the right
        // side; FULL gain acts as a master makeup gain across the whole
        // wave. Same per-band behavior as the bars.
        let halfFFT = max(8, spectrum.count / 4)
        let minBin: Float = 2
        let maxBin = Float(halfFFT)
        let logRatio = maxBin / minBin
        let samples = waveformSamples.count
        for i in 0..<samples {
            let f = Float(i) / Float(samples - 1)
            // Log-spaced bin index — gives bass plenty of horizontal real
            // estate while keeping the high frequencies present.
            let binFloat = minBin * pow(logRatio, f)
            let binA = max(0, min(halfFFT - 1, Int(binFloat)))
            let binB = max(0, min(halfFFT - 1, binA + 1))
            let frac = binFloat - Float(binA)
            // Per-bin band gain + threshold applied to each side of the
            // lerp so the band boundaries shape the wave smoothly.
            let mA = applyBandEnvelope(magnitude: spectrum[binA], bin: binA, params: params)
            let mB = applyBandEnvelope(magnitude: spectrum[binB], bin: binB, params: params)
            let mixed = mA * (1 - frac) + mB * frac
            waveformSamples[i] = followBar(current: waveformSamples[i], target: mixed, dt: dt)
        }

        // Build a closed path that traces the upper edge left-to-right
        // (cy − magnitude) and the lower edge right-to-left (cy + magnitude),
        // using quad-curves between sample points for a smooth shape.
        // DENSITY is repurposed here as a sharpness/contrast knob — it
        // expands dynamics around a typical-music baseline so peaks
        // push higher and quiet sections collapse harder. 0 = linear
        // (gentle), 1 = extreme contrast (peaks fully saturated, valleys
        // pinned to zero).
        let sharpness = params.density
        let baseline: Float = 0.15
        let dynScale: Float = 1 + sharpness * 4
        var topPts: [CGPoint] = []
        var botPts: [CGPoint] = []
        for i in 0..<samples {
            let frac = CGFloat(i) / CGFloat(samples - 1)
            let x = frac * CGFloat(width)
            let dev = waveformSamples[i] - baseline
            let expanded = max(0, baseline + dev * dynScale)
            let mag = CGFloat(min(1, expanded * 4)) * a
            topPts.append(CGPoint(x: x, y: cy - mag))
            botPts.append(CGPoint(x: x, y: cy + mag))
        }

        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: cy))
        // Top edge — quad-curve through midpoints for smoothness.
        path.addLine(to: topPts[0])
        for i in 1..<(topPts.count - 1) {
            let m = CGPoint(x: (topPts[i].x + topPts[i + 1].x) / 2,
                            y: (topPts[i].y + topPts[i + 1].y) / 2)
            path.addQuadCurve(to: m, control: topPts[i])
        }
        path.addLine(to: topPts.last!)
        path.addLine(to: CGPoint(x: CGFloat(width), y: cy))
        // Bottom edge, right-to-left.
        path.addLine(to: botPts.last!)
        for i in (1..<(botPts.count - 1)).reversed() {
            let m = CGPoint(x: (botPts[i - 1].x + botPts[i].x) / 2,
                            y: (botPts[i - 1].y + botPts[i].y) / 2)
            path.addQuadCurve(to: m, control: botPts[i])
        }
        path.addLine(to: botPts[0])
        path.closeSubpath()

        // Fill body with translucent color
        ctx.setFillColor(fillColor.cgColor)
        ctx.addPath(path)
        ctx.fillPath()

        // Stroke outline with the standard 4-pass bloom helper for that
        // neon-on-black glow.
        let pulse = CGFloat(min(1, activeLevel * 2 + 0.4))
        strokeWithGlow(ctx: ctx, path: path, color: lineColor,
                       baseWidth: 1.5 + pulse * 1.0)
    }

    // MARK: - Plasma: Polygons (Battery)

    private func drawPolygons(ctx: CGContext, time t: Float, params: VisualizerParams) {
        let cx = CGFloat(width) * 0.5
        let cy = CGFloat(height) * 0.5
        // Apply the same kick-detection envelope to brighten + scale on
        // each beat. kickFlash decays alongside transientPulse so the
        // pulse visibly rises and falls instead of a constant boost.
        let isKick = detectKick(params: params)
        let kickGain: CGFloat = isKick
            ? CGFloat(0.4 + params.kickStrength * 0.8)
            : CGFloat(transientPulse) * CGFloat(0.2 + params.kickStrength * 0.3)
        let bass = CGFloat(activeLevel) * CGFloat(params.bassResponse * 2) + kickGain * 0.3
        let mid = CGFloat(activeLevel)
        let high = CGFloat(activeLevel) + kickGain * 0.2

        // Pure black background — true WMP/Winamp look. The bloom glow
        // needs a black canvas to read as glow; even 5% grey from a hue
        // tint dulls it.
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Density: 3-10 rings
        let rings = max(3, Int(3 + params.density * 7))
        for ring in 0..<rings {
            let sides = max(3, 8 - ring)
            let baseR: CGFloat = CGFloat(60 + ring * 55)
            let bassPulse: CGFloat = 1 + bass * 1.6
            let waveArg: Float = t * 1.4 + Float(ring)
            let wave: CGFloat = 1 + 0.15 * CGFloat(sin(waveArg))
            let radius: CGFloat = baseR * bassPulse * wave
            let rot: CGFloat = CGFloat(t) * (0.18 + CGFloat(ring) * 0.08) + bass * CGFloat.pi * 0.3
            let hue = ((Double(t) * 0.07) + Double(ring) * 0.16 + Double(params.hue)).truncatingRemainder(dividingBy: 1.0)
            // Push saturation + brightness near max — we want neon, not muted.
            let bright = min(1.0, (0.65 + Double(high) * 0.35 + Double(mid) * 0.15) * Double(params.intensity + 0.3))
            let color = UIColor(hue: hue, saturation: 0.95, brightness: bright, alpha: 1)
            // Build the polygon path once, then draw with bloom passes.
            let path = CGMutablePath()
            for s in 0..<sides {
                let a: CGFloat = rot + CGFloat(s) / CGFloat(sides) * 2 * CGFloat.pi
                let x = cx + cos(a) * radius
                let y = cy + sin(a) * radius
                if s == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            path.closeSubpath()
            strokeWithGlow(ctx: ctx, path: path, color: color,
                           baseWidth: 2 + bass * 4 + CGFloat(ring) * 0.4)
        }

        // Center pulse with full bloom on bass — looks like a glowing core
        if bass > 0.02 {
            let cr = 8 + bass * 40
            fillCircleWithGlow(ctx: ctx,
                               center: CGPoint(x: cx, y: cy),
                               radius: cr,
                               color: UIColor(white: 1, alpha: 1),
                               intensity: min(1.0, CGFloat(bass) * 2.0))
        }

        // Transient ray bursts — drawn with bloom too
        if transientPulse > 0.05 {
            let rays = 12
            let rOuter: CGFloat = 220 + bass * 200
            let rInner: CGFloat = 40
            let rayPath = CGMutablePath()
            for i in 0..<rays {
                let a: CGFloat = CGFloat(i) / CGFloat(rays) * 2 * CGFloat.pi + CGFloat(t)
                rayPath.move(to: CGPoint(x: cx + cos(a) * rInner, y: cy + sin(a) * rInner))
                rayPath.addLine(to: CGPoint(x: cx + cos(a) * rOuter, y: cy + sin(a) * rOuter))
            }
            strokeWithGlow(ctx: ctx, path: rayPath,
                           color: UIColor(white: 1, alpha: 1),
                           baseWidth: 1.2 + bass * 2,
                           intensity: CGFloat(transientPulse))
        }
    }

    // MARK: - Plasma: Tunnel

    /// Polygonal 3D tunnel — you fly straight down a wireframe tube made
    /// of N polygon rings stacked along the Z axis. Each ring scrolls
    /// toward the camera over time and wraps to the back when it crosses
    /// the near plane, giving an endless-corridor feel. Adjacent rings are
    /// connected by longitudinal lines (one per polygon edge) so the
    /// tube reads as a wireframe surface rather than independent rings.
    /// Audio reactivity:
    ///   • SUB/BASS envelope → tunnel scroll speed + ring scale pulse
    ///   • MID envelope → corkscrew twist rate
    ///   • HIGH/AIR + transients → ring brightness flash
    ///   • DENSITY param → polygon side count (4 = square corridor → 12 = nearly round)
    private func drawTunnel(ctx: CGContext, time t: Float, params: VisualizerParams) {
        let cx = CGFloat(width) * 0.5
        let cy = CGFloat(height) * 0.5
        let bass = Float(activeLevel) * Float(params.bassResponse * 2)
        let mid = Float(activeLevel)
        let high = Float(activeLevel)
        let intensity = Float(params.intensity) + 0.3

        // Pure black + a soft motion-blur trail — gives the "moving
        // through space" feel without smearing rings together.
        ctx.setFillColor(UIColor(white: 0, alpha: 0.18).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // 4–12 polygon sides, controlled by DENSITY. 4 → square corridor,
        // 6 → hex tube, 12 → near-round tunnel.
        let sides = max(4, min(12, Int(4 + params.density * 8)))
        let ringCount = 18
        let zNear: Float = 0.6
        let zFar: Float = 16.0
        let zRange = zFar - zNear
        let baseRadius = Float(min(width, height)) * 0.55

        // Audio-driven travel — no idle baseline. When the active band's
        // envelope is at 0 (silence or all gains zeroed), the tunnel
        // freezes in place. activeLevel scales linearly into scroll rate.
        // `t` here is `scaledTime` which already includes the global
        // SPEED param multiplier — multiplying activeLevel into it gives
        // a clean stop-at-silence behavior.
        let activeLevel = envelopes[activeBand]
        let travelSpeed: Float = activeLevel * 3.5
        let scroll = (t * travelSpeed).truncatingRemainder(dividingBy: zRange / Float(ringCount))

        // Corkscrew twist — purely audio-driven now (was: 0.10 +
        // mid * 0.4). Stops twisting at silence.
        let twistRate: Float = mid * 0.55
        let twistPerRing: Float = 0.18

        // Ring radius pulse on bass — slight scale modulation
        let radiusPulse: Float = 1 + bass * 0.18

        // Build all rings' projected polygon points. Storing each ring's
        // vertex array lets us draw the longitudinal lines between rings
        // afterward without recomputing.
        var rings: [(points: [CGPoint], depthFrac: Float)] = []
        rings.reserveCapacity(ringCount)
        for ring in 0..<ringCount {
            let baseZ = zNear + (Float(ring) / Float(ringCount)) * zRange
            var z = baseZ - scroll
            // Wrap so rings cycle from far → near continuously.
            while z < zNear { z += zRange }
            // Perspective scale: closer = larger on screen
            let perspScale: Float = 1.0 / max(0.0001, z) * 0.9
            let ringRadius = baseRadius * perspScale * radiusPulse
            // Twist this ring's polygon — accumulating a constant twist
            // per ring + a global time-driven rotation gives the
            // corkscrew motion.
            let twist = t * twistRate + Float(ring) * twistPerRing
            // Build polygon vertices
            var pts: [CGPoint] = []
            pts.reserveCapacity(sides)
            for s in 0..<sides {
                let a = Float(s) / Float(sides) * 2 * .pi + twist
                let x = cos(a) * ringRadius
                let y = sin(a) * ringRadius
                pts.append(CGPoint(x: cx + CGFloat(x), y: cy + CGFloat(y)))
            }
            // depthFrac: 0 = closest, 1 = farthest. Used for color/alpha.
            let depthFrac = (z - zNear) / zRange
            rings.append((pts, depthFrac))
        }

        // Sort rings by depth (farthest first) so closer rings draw on top.
        let sortedRings = rings.sorted { $0.depthFrac > $1.depthFrac }

        // Render each polygon ring as a closed wireframe loop with bloom.
        // Brightness fades with depth so the back of the tunnel reads
        // as a vanishing point.
        for ring in sortedRings {
            let alpha = (1.0 - Double(ring.depthFrac)) * 0.95
            let hue = ((Double(t) * 0.06) + Double(ring.depthFrac) * 0.4 + Double(params.hue))
                .truncatingRemainder(dividingBy: 1.0)
            let bright = 0.7 + Double(high) * 0.3 + Double(transientPulse) * 0.2
            let color = UIColor(hue: hue, saturation: 0.95,
                                brightness: min(1, bright * Double(intensity)),
                                alpha: 1)
            let path = CGMutablePath()
            path.move(to: ring.points[0])
            for p in ring.points.dropFirst() { path.addLine(to: p) }
            path.closeSubpath()
            strokeWithGlow(ctx: ctx, path: path, color: color,
                           baseWidth: CGFloat(1.5 + bass * 2.5),
                           intensity: CGFloat(alpha))
        }

        // Longitudinal lines connecting corresponding vertices across
        // adjacent rings — these are the "edges" of the tunnel tube.
        // Without them you just see independent floating polygons; WITH
        // them the tunnel reads as a continuous wireframe surface.
        ctx.setBlendMode(.plusLighter)
        ctx.setLineCap(.round)
        for s in 0..<sides {
            let path = CGMutablePath()
            // Iterate by ORIGINAL ring order (near to far) so the line
            // joins are coherent. Skip rings that wrapped recently to
            // avoid jagged jumps.
            for (i, ring) in rings.enumerated() {
                if i == 0 { path.move(to: ring.points[s]) }
                else { path.addLine(to: ring.points[s]) }
            }
            // Color is mostly white with a tint, lower alpha
            let hue = ((Double(t) * 0.04) + Double(s) * 0.04 + Double(params.hue))
                .truncatingRemainder(dividingBy: 1.0)
            let bright = 0.85 + Double(high) * 0.15
            let color = UIColor(hue: hue, saturation: 0.6,
                                brightness: min(1, bright),
                                alpha: 0.55 * Double(intensity)).cgColor
            ctx.setStrokeColor(color)
            ctx.setLineWidth(CGFloat(1.0 + bass * 1.5))
            ctx.addPath(path)
            ctx.strokePath()
        }
        ctx.setBlendMode(.normal)

        // Vanishing-point glow at center — sells the depth and gives a
        // bright focal point when the tunnel is shallow / quiet.
        let cr: CGFloat = CGFloat(20 + bass * 60)
        fillCircleWithGlow(ctx: ctx, center: CGPoint(x: cx, y: cy),
                           radius: cr,
                           color: UIColor(white: 1, alpha: 1),
                           intensity: CGFloat(0.35 + bass * 0.4))
    }

    // MARK: - Plasma: Particles

    private func drawParticles(ctx: CGContext, time t: Float, params: VisualizerParams, dt: Float) {
        let bassResp = params.bassResponse * 2
        let frameW = Float(width)
        let frameH = Float(height)

        // Pure black + a light frame trail wash so the falling rain
        // streaks look like they're persisting briefly instead of
        // popping in and out.
        ctx.setFillColor(UIColor(white: 0, alpha: 0.20).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Continuous downpour — emission rate scales with audio energy
        // and bursts on bass kicks / hi-hat transients. Particles spawn
        // at the top edge with a random x, drift slightly sideways, and
        // fall under gravity.
        let combinedEnergy = (activeLevel + activeLevel + activeLevel) / 3
        // Param-driven kick threshold. kickSensitivity 0..1 maps linearly
        // to ratio 1.9× (strict, only big kicks) → 1.1× (lenient, almost
        // any bass bump). Same formula used by every other variant so
        // tweaking the slider feels consistent across all visualizers.
        let isBassKick = detectKick(params: params)
        let baseEmit = max(0, combinedEnergy - 0.005) * 90 * (0.5 + params.density)
        let kickEmit: Float = isBassKick ? 18 + 36 * params.density : 0
        let transientEmit: Float = transientPulse > 0.3 ? 10 + 24 * params.density : 0
        let baseline: Float = 1.0 // steady trickle so the rain is always there
        let totalEmit = Int(baseEmit + kickEmit + transientEmit + baseline)

        if totalEmit > 0 && t - lastEmitTime > 0.015 {
            lastEmitTime = t
            var emitted = 0
            for i in particles.indices where emitted < totalEmit {
                if particles[i].life <= 0.01 {
                    let spawnX = Float.random(in: -20...frameW + 20)
                    let spawnY: Float = -20 // just above the top edge
                    let vx = Float.random(in: -40...40)
                    // Vertical speed scales with bass — heavier hits =
                    // faster downpour.
                    let vy = Float.random(in: 110...260) * (1 + activeLevel * bassResp * 0.6)
                    particles[i].x = spawnX
                    particles[i].y = spawnY
                    particles[i].prevX = spawnX
                    particles[i].prevY = spawnY
                    particles[i].vx = vx
                    particles[i].vy = vy
                    particles[i].life = 1.0
                    particles[i].hue = Float.random(in: 0...1) + params.hue
                    particles[i].size = 2.5 + Float.random(in: 0...4)
                    particles[i].phase = Float.random(in: 0...(.pi * 2))
                    emitted += 1
                }
            }
        }

        // Gravity (pixels/sec²) — a stable falling motion regardless of
        // frame rate. Particles accelerate as they fall so the trails get
        // longer toward the bottom of the frame, the classic look.
        let gravity: Float = 380

        // Audio reactivity for in-flight particles:
        // 1. BASS KICK BOUNCE — on every detected kick (activeLevel > 1.4×
        //    its slow moving average), every live particle's vertical
        //    velocity flips upward at half magnitude, like raindrops being
        //    smacked back up by the bass.
        let kickedThisFrame = isBassKick
        // 2. SWAY — continuous sinusoidal horizontal acceleration driven
        //    by mid-band energy. Each particle has its own phase so they
        //    don't all swing in lockstep. swayAmount param scales the
        //    overall force (0=calm, 1=default, 2=wild).
        let swayMul: Float = 0.3 + params.swayAmount * 1.4
        let swayAmp: Float = (80 + activeLevel * 380) * swayMul
        let swayFreq: Float = 1.6 + activeLevel * 3.0

        // Render each live particle as a glowing line trail from its
        // previous position to the new one, capped by a small bright
        // head circle. Both pieces use the bloom helper so the rain
        // reads as soft glowing streaks instead of harsh pixels.
        ctx.setBlendMode(.plusLighter)
        ctx.setLineCap(.round)
        for i in particles.indices {
            if particles[i].life <= 0.01 { continue }

            // BASS KICK — punch all live particles upward. Strength is
            // user-tunable via params.kickStrength so the snap can be
            // dialed from "barely there" to "all particles get launched."
            if kickedThisFrame {
                let kickMul: Float = 0.4 + params.kickStrength * 0.4 // 0.4..1.2
                let kickBoost: Float = 40 + params.kickStrength * 80   // 40..200
                particles[i].vy = -abs(particles[i].vy) * kickMul - kickBoost
                particles[i].vx += Float.random(in: -50...50) * activeLevel * bassResp * (0.5 + params.kickStrength)
            }

            // SWAY — sinusoidal lateral acceleration on top of any other
            // motion the particle has.
            let swayAcc = sin(t * swayFreq + particles[i].phase) * swayAmp
            particles[i].vx += swayAcc * dt

            // Stash previous position for trail, then advance.
            particles[i].prevX = particles[i].x
            particles[i].prevY = particles[i].y
            particles[i].vx *= 0.995    // tiny horizontal damping
            particles[i].vy += gravity * dt
            particles[i].x += particles[i].vx * dt
            particles[i].y += particles[i].vy * dt

            // Off-screen kill — particles fall off the bottom edge and
            // out the sides; new ones spawn at the top each frame so the
            // downpour feels continuous.
            if particles[i].y > frameH + 30 || particles[i].x < -50 || particles[i].x > frameW + 50 {
                particles[i].life = 0
                continue
            }
            // Lifetime decay — long enough to span a full screen drop
            // even at slow gravity.
            particles[i].life -= dt * 0.18
            if particles[i].life <= 0 { continue }

            let lifeAlpha = Double(min(1.0, particles[i].life))
            let alpha = lifeAlpha * Double(params.intensity + 0.3)
            let hueRaw = Double(particles[i].hue.truncatingRemainder(dividingBy: 1.0))
            let hue = hueRaw < 0 ? hueRaw + 1 : hueRaw
            let color = UIColor(hue: hue, saturation: 0.85, brightness: 1.0, alpha: 1)

            // Streak: draw the path from prev to current with bloom.
            let p0 = CGPoint(x: CGFloat(particles[i].prevX), y: CGFloat(particles[i].prevY))
            let p1 = CGPoint(x: CGFloat(particles[i].x), y: CGFloat(particles[i].y))
            let path = CGMutablePath()
            path.move(to: p0)
            path.addLine(to: p1)
            // Inline bloom (since we're already in plusLighter mode).
            let halos: [(mul: CGFloat, alpha: CGFloat)] = [
                (5.0, 0.10), (2.6, 0.20), (1.4, 0.40), (0.85, 1.0)
            ]
            for halo in halos {
                ctx.setStrokeColor(color.withAlphaComponent(halo.alpha * alpha).cgColor)
                ctx.setLineWidth(CGFloat(particles[i].size) * halo.mul)
                ctx.addPath(path)
                ctx.strokePath()
            }
            // Bright head dot at the leading edge — gives each streak
            // a clear "raindrop" tip.
            let headR = CGFloat(particles[i].size) * 0.9
            ctx.setFillColor(color.withAlphaComponent(alpha).cgColor)
            ctx.fillEllipse(in: CGRect(x: p1.x - headR, y: p1.y - headR,
                                       width: headR * 2, height: headR * 2))
        }
        ctx.setBlendMode(.normal)
    }

    // MARK: - WMP: Plenoptic (multi-layer plasma + lens flares)

    private func drawPlasmaFlow(ctx: CGContext, time t: Float, params: VisualizerParams) {
        // Plenoptic-inspired: two sinusoidal layers (one slow & broad,
        // one fast & detailed) added together for richer color flow,
        // plus radial lens flares wandering across the canvas, plus a
        // bass-driven brightness pulse. Gives the layered "psychedelic
        // depth" feel WMP's Plenoptic visualizer was known for.
        let bass = activeLevel * params.bassResponse * 2
        let intensity = Float(params.intensity) + 0.3
        let huePhase = Float(params.hue)
        let zoom: Float = 3.5 + Float(params.density) * 4.5
        let speed = 1.0 + bass * 1.3
        let tt = t * speed

        plasmaPixels.withUnsafeMutableBufferPointer { buf in
            for y in 0..<plasmaH {
                let fy: Float = Float(y) / Float(plasmaH)
                for x in 0..<plasmaW {
                    let fx: Float = Float(x) / Float(plasmaW)
                    let dx: Float = fx - 0.5
                    let dy: Float = fy - 0.5
                    let d: Float = sqrt(dx * dx + dy * dy)
                    // BROAD layer — slow, low-frequency color background
                    let b1: Float = sin(fx * zoom * 0.4 + tt * 0.6)
                    let b2: Float = sin((fx + fy) * zoom * 0.3 + tt * 0.7)
                    let b3: Float = sin(d * zoom * 0.6 + tt * 0.4)
                    let broad: Float = (b1 + b2 + b3) / 3.0
                    // DETAIL layer — faster, higher-frequency texture
                    let dArg1: Float = fx * zoom * 1.2 + tt * 1.4
                    let dArg2: Float = (fx * 0.7 + fy * 0.9) * zoom * 1.1 + tt * 1.7
                    let dArg3: Float = d * zoom * 2.0 + tt * 1.1
                    let det1: Float = sin(dArg1)
                    let det2: Float = sin(dArg2)
                    let det3: Float = sin(dArg3)
                    let detail: Float = (det1 + det2 + det3) / 3.0
                    // Mix: broad provides hue, detail modulates value
                    let v: Float = broad * 0.65 + detail * 0.35
                    let hueRaw: Float = (v * 0.5 + 0.5 + huePhase + tt * 0.04).truncatingRemainder(dividingBy: 1.0)
                    let hue: Float = hueRaw < 0 ? hueRaw + 1 : hueRaw
                    let detailMod: Float = 0.55 + 0.45 * detail
                    let valBase: Float = detailMod + bass * 0.25
                    let val: Float = min(1.0, max(0.05, intensity * valBase))
                    let sat: Float = 0.85 + bass * 0.15
                    let (r, g, b) = hsvToRGB(h: hue, s: min(1, sat), v: val)
                    let off = (y * plasmaW + x) * 4
                    buf[off + 0] = b
                    buf[off + 1] = g
                    buf[off + 2] = r
                    buf[off + 3] = 255
                }
            }
        }

        let cs = CGColorSpaceCreateDeviceRGB()
        let bi = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        // Hand CG a CFData (which owns its own copy of the pixels) instead
        // of a raw pointer into the Swift array — that earlier pattern
        // worked because the draw is synchronous within the closure, but
        // it relied on ordering guarantees the CG docs don't make
        // explicit. ~57KB copy per frame at 160×90 BGRA, well below the
        // noise floor for a CADisplayLink tick.
        let plasmaData: CFData = plasmaPixels.withUnsafeBufferPointer {
            CFDataCreate(nil, $0.baseAddress, $0.count)
        }
        if let provider = CGDataProvider(data: plasmaData),
           let img = CGImage(width: plasmaW, height: plasmaH,
                             bitsPerComponent: 8, bitsPerPixel: 32,
                             bytesPerRow: plasmaW * 4,
                             space: cs, bitmapInfo: CGBitmapInfo(rawValue: bi),
                             provider: provider, decode: nil,
                             shouldInterpolate: true,
                             intent: .defaultIntent) {
            ctx.interpolationQuality = .high
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        // Lens flares — 3 wandering radial gradient highlights with
        // additive blending. Gives that "depth + lighting" feel that
        // Plenoptic had over a flat plasma.
        ctx.setBlendMode(.plusLighter)
        for i in 0..<3 {
            let phase = Float(i) * 2.094 // 2π/3
            let cxNorm: Float = 0.5 + 0.42 * sin(t * 0.13 + phase)
            let cyNorm: Float = 0.5 + 0.32 * cos(t * 0.17 + phase * 1.3)
            let cx = CGFloat(cxNorm) * CGFloat(width)
            let cy = CGFloat(cyNorm) * CGFloat(height)
            let r: CGFloat = 80 + CGFloat(bass) * 240
            let hue = ((Double(t) * 0.05) + Double(i) * 0.33 + Double(huePhase)).truncatingRemainder(dividingBy: 1.0)
            let inner = UIColor(hue: hue, saturation: 0.55, brightness: 1.0,
                                alpha: 0.55 * Double(intensity)).cgColor
            let outer = UIColor(hue: hue, saturation: 1.0, brightness: 1.0, alpha: 0.0).cgColor
            let gradient = CGGradient(colorsSpace: cs,
                                      colors: [inner, outer] as CFArray,
                                      locations: [0, 1])!
            ctx.drawRadialGradient(gradient,
                                   startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                                   endCenter: CGPoint(x: cx, y: cy), endRadius: r,
                                   options: [])
        }
        ctx.setBlendMode(.normal)
    }

    // MARK: - WMP: Orbs

    /// Three-to-seven glowing radial-gradient orbs orbiting the center of
    /// the frame against pure black — the same rendering technique as the
    /// Plenoptic lens flares but pulled out as a clean standalone variant.
    /// Audio choreography:
    ///   • SUB/BASS envelope → orb radius pulse
    ///   • MID envelope → orbital speed
    ///   • HIGH/AIR envelope + transients → brightness flash
    ///   • Bass kick → randomly flip one orb's rotation direction
    ///   • DENSITY param → orb count (2..7)
    private func drawOrbs(ctx: CGContext, time t: Float, params: VisualizerParams) {
        let cx = CGFloat(width) * 0.5
        let cy = CGFloat(height) * 0.5
        let bass = CGFloat(activeLevel) * CGFloat(params.bassResponse * 2)
        let mid = Float(activeLevel)
        let high = Float(activeLevel)
        let intensity = Float(params.intensity) + 0.3

        // Light frame trail — leaves a soft motion ghost behind each
        // orb without becoming smeary.
        ctx.setFillColor(UIColor(white: 0, alpha: 0.14).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let orbCount = max(2, Int(2 + params.density * 5)) // 2..7

        // Make sure we have a direction slot per orb (default alternating
        // signs so the initial layout doesn't have everything spinning
        // the same way).
        while orbDirections.count < orbCount {
            orbDirections.append(orbDirections.count.isMultiple(of: 2) ? 1 : -1)
        }

        // Bass-kick flip — same param-driven detection as everywhere else.
        let isBassKick = detectKick(params: params)
        if isBassKick && (t - lastOrbFlipTime) > 0.18 {
            // Flip 1-2 random orbs each kick — keeps motion lively
            // without spinning every orb at once on a sustained bassline.
            let flips = 1 + (params.kickStrength > 0.7 ? 1 : 0)
            for _ in 0..<flips {
                let idx = Int.random(in: 0..<orbCount)
                orbDirections[idx] *= -1
            }
            lastOrbFlipTime = t
        }

        // MID envelope drives orbital speed — a percussive mid/snare
        // doubles the spin rate momentarily.
        let speedMul: Float = 1.0 + mid * 1.4

        let baseRadius: Float = Float(min(width, height)) * 0.30

        ctx.setBlendMode(.plusLighter)
        let cs = CGColorSpaceCreateDeviceRGB()

        for i in 0..<orbCount {
            let dir = orbDirections[i]
            // Distinct orbital frequency per orb (small offsets so they
            // dephase over time and form changing constellations).
            let orbFreq: Float = 0.16 + Float(i) * 0.045
            let phase = t * orbFreq * speedMul * dir + Float(i) * 1.05
            // Slightly elliptical, slightly different per orb.
            let rxNorm: Float = 1 + Float(i) * 0.06
            let ryNorm: Float = 0.7 + Float(i) * 0.04
            let rx = baseRadius * rxNorm
            let ry = baseRadius * ryNorm
            let ox = cx + CGFloat(cos(phase)) * CGFloat(rx)
            let oy = cy + CGFloat(sin(phase * 1.3)) * CGFloat(ry)

            // Orb size pulses with bass + a tiny built-in wobble so even
            // on silent input the orbs aren't perfectly static.
            let wobble = CGFloat(0.1 * sin(t * 1.7 + Float(i) * 0.9))
            let r: CGFloat = (60 + bass * 200) * (1 + wobble)

            // Hue cycles slowly + per-orb offset + user hue shift.
            let hue = ((Double(t) * 0.04) + Double(i) * 0.20 + Double(params.hue))
                .truncatingRemainder(dividingBy: 1.0)
            // Brightness flashes on high transients.
            let bright = Double(intensity) * (0.85 + Double(high) * 0.30 + Double(transientPulse) * 0.25)
            let alpha = min(1.0, bright * 0.65)

            // Three-stop radial gradient: hot pinpoint center →
            // saturated mid → transparent edge. Reads as a glowing orb
            // rather than a flat circle.
            let inner = UIColor(hue: hue, saturation: 0.55, brightness: 1.0,
                                alpha: alpha).cgColor
            let middle = UIColor(hue: hue, saturation: 1.0, brightness: 1.0,
                                 alpha: alpha * 0.45).cgColor
            let outer = UIColor(hue: hue, saturation: 1.0, brightness: 1.0,
                                alpha: 0).cgColor
            guard let gradient = CGGradient(colorsSpace: cs,
                                            colors: [inner, middle, outer] as CFArray,
                                            locations: [0, 0.4, 1])
            else { continue }
            ctx.drawRadialGradient(gradient,
                                   startCenter: CGPoint(x: ox, y: oy), startRadius: 0,
                                   endCenter: CGPoint(x: ox, y: oy), endRadius: r,
                                   options: [])

            // Hot near-white pinpoint at the orb's exact center for that
            // "starcore" feel — looks like a tiny sun inside the glow.
            let dotR: CGFloat = 4 + bass * 8
            ctx.setFillColor(UIColor(hue: hue, saturation: 0.20, brightness: 1.0,
                                     alpha: alpha).cgColor)
            ctx.fillEllipse(in: CGRect(x: ox - dotR, y: oy - dotR,
                                       width: dotR * 2, height: dotR * 2))
        }
        ctx.setBlendMode(.normal)
    }

    // MARK: - Geometry (3D rotating polyhedra)

    /// Vertex sets for the supported wireframe solids. All vertices are
    /// in roughly [-1, 1] cube space; the renderer scales them by the
    /// per-solid size before perspective projection.
    private static let cubeVerts: [SIMD3<Float>] = [
        SIMD3(-1, -1, -1), SIMD3( 1, -1, -1), SIMD3( 1,  1, -1), SIMD3(-1,  1, -1),
        SIMD3(-1, -1,  1), SIMD3( 1, -1,  1), SIMD3( 1,  1,  1), SIMD3(-1,  1,  1)
    ]
    private static let cubeEdges: [(Int, Int)] = [
        (0,1),(1,2),(2,3),(3,0),
        (4,5),(5,6),(6,7),(7,4),
        (0,4),(1,5),(2,6),(3,7)
    ]
    private static let tetraVerts: [SIMD3<Float>] = [
        SIMD3( 1,  1,  1), SIMD3( 1, -1, -1), SIMD3(-1,  1, -1), SIMD3(-1, -1,  1)
    ]
    private static let tetraEdges: [(Int, Int)] = [
        (0,1),(0,2),(0,3),(1,2),(1,3),(2,3)
    ]
    private static let octaVerts: [SIMD3<Float>] = [
        SIMD3( 1, 0, 0), SIMD3(-1, 0, 0),
        SIMD3( 0, 1, 0), SIMD3( 0,-1, 0),
        SIMD3( 0, 0, 1), SIMD3( 0, 0,-1)
    ]
    private static let octaEdges: [(Int, Int)] = [
        (0,2),(0,3),(0,4),(0,5),
        (1,2),(1,3),(1,4),(1,5),
        (2,4),(2,5),(3,4),(3,5)
    ]

    /// Square pyramid — apex on top, square base. Distinctive 4-sided
    /// silhouette that reads instantly different from the cube.
    private static let pyramidVerts: [SIMD3<Float>] = [
        SIMD3( 0,  1.4,  0),  // 0: apex
        SIMD3(-1, -0.6, -1),  // 1: base
        SIMD3( 1, -0.6, -1),  // 2: base
        SIMD3( 1, -0.6,  1),  // 3: base
        SIMD3(-1, -0.6,  1)   // 4: base
    ]
    private static let pyramidEdges: [(Int, Int)] = [
        (0,1),(0,2),(0,3),(0,4),    // apex → base corners
        (1,2),(2,3),(3,4),(4,1)     // square base
    ]

    /// Icosahedron — 20 triangular faces, 12 vertices, 30 edges. The
    /// "soccer ball" feel; reads as a near-sphere wireframe at a glance.
    /// Vertices use the golden ratio φ. The 1/φ scale factor below
    /// (`/iphi`) keeps the icosa from being noticeably larger than the
    /// other shapes.
    private static let icosaVerts: [SIMD3<Float>] = {
        let phi: Float = (1 + sqrt(5.0)) / 2.0
        let s: Float = 1.0 / phi  // scale so the unit cube fits roughly
        return [
            SIMD3(0,  s,  s * phi), SIMD3(0, -s,  s * phi),
            SIMD3(0,  s, -s * phi), SIMD3(0, -s, -s * phi),
            SIMD3( s,  s * phi, 0), SIMD3(-s,  s * phi, 0),
            SIMD3( s, -s * phi, 0), SIMD3(-s, -s * phi, 0),
            SIMD3( s * phi, 0,  s), SIMD3(-s * phi, 0,  s),
            SIMD3( s * phi, 0, -s), SIMD3(-s * phi, 0, -s)
        ]
    }()
    private static let icosaEdges: [(Int, Int)] = [
        (0,1),(0,4),(0,5),(0,8),(0,9),
        (1,6),(1,7),(1,8),(1,9),
        (2,3),(2,4),(2,5),(2,10),(2,11),
        (3,6),(3,7),(3,10),(3,11),
        (4,5),(4,8),(4,10),
        (5,9),(5,11),
        (6,7),(6,8),(6,10),
        (7,9),(7,11),
        (8,10),
        (9,11)
    ]

    private static let shapeCount = 5  // cube, tetra, octa, pyramid, icosa

    private static func vertsFor(_ shape: Int) -> [SIMD3<Float>] {
        switch shape {
        case 0: return cubeVerts
        case 1: return tetraVerts
        case 2: return octaVerts
        case 3: return pyramidVerts
        case 4: return icosaVerts
        default: return cubeVerts
        }
    }
    private static func edgesFor(_ shape: Int) -> [(Int, Int)] {
        switch shape {
        case 0: return cubeEdges
        case 1: return tetraEdges
        case 2: return octaEdges
        case 3: return pyramidEdges
        case 4: return icosaEdges
        default: return cubeEdges
        }
    }

    /// Apply XYZ rotation to a 3D vector. Standard Euler XYZ order.
    @inline(__always)
    private func rotate3D(_ v: SIMD3<Float>, x: Float, y: Float, z: Float) -> SIMD3<Float> {
        var p = v
        let cx = cos(x), sx = sin(x)
        p = SIMD3(p.x, p.y * cx - p.z * sx, p.y * sx + p.z * cx)
        let cy = cos(y), sy = sin(y)
        p = SIMD3(p.x * cy + p.z * sy, p.y, -p.x * sy + p.z * cy)
        let cz = cos(z), sz = sin(z)
        p = SIMD3(p.x * cz - p.y * sz, p.x * sz + p.y * cz, p.z)
        return p
    }

    /// Perspective project a rotated vertex to screen coords. `viewer`
    /// is the synthetic camera distance — bigger = less perspective
    /// (more orthographic), smaller = more dramatic depth foreshortening.
    @inline(__always)
    private func project3D(_ v: SIMD3<Float>, center: CGPoint, size: Float,
                            viewer: Float = 3.5) -> CGPoint {
        let scale = viewer / max(0.001, viewer + v.z)
        return CGPoint(x: center.x + CGFloat(v.x * scale * size),
                       y: center.y + CGFloat(v.y * scale * size))
    }

    /// Make a randomized solid with sensible defaults.
    private func makeSolid(index i: Int, params: VisualizerParams) -> Solid3D {
        Solid3D(
            shapeIdx: Int.random(in: 0..<Self.shapeCount),
            hue: Float.random(in: 0...1),
            orbitPhase: Float(i) * 1.2,
            orbitFreq: 0.18 + Float.random(in: 0...0.12),
            orbitRadiusN: 0.18 + Float.random(in: 0...0.18),
            orbitElev: 0.6 + Float.random(in: 0...0.4),
            rotX: Float.random(in: 0...(.pi * 2)),
            rotY: Float.random(in: 0...(.pi * 2)),
            rotZ: Float.random(in: 0...(.pi * 2)),
            rotSpeedX: 0.4 + Float.random(in: 0...0.6),
            rotSpeedY: 0.4 + Float.random(in: 0...0.6),
            rotSpeedZ: 0.2 + Float.random(in: 0...0.4),
            sizeN: 0.7 + Float.random(in: 0...0.3)
        )
    }

    /// Render N rotating 3D solids (cube / tetrahedron / octahedron),
    /// projected to 2D with perspective and stroked with the standard
    /// 4-pass bloom helper. Audio-reactive:
    ///   • SUB/BASS envelope → solid scale pulse
    ///   • MID envelope → rotation rate
    ///   • HIGH/AIR envelope + transients → vertex sparkle brightness
    ///   • Bass kick → randomly morphs one solid's shape (cube → tetra → octa)
    ///   • DENSITY param → solid count (1..4)
    private func drawGeometry(ctx: CGContext, time t: Float, params: VisualizerParams, dt: Float) {
        let cx = CGFloat(width) * 0.5
        let cy = CGFloat(height) * 0.5
        let bass = Float(activeLevel) * Float(params.bassResponse * 2)
        let mid = Float(activeLevel)
        let high = Float(activeLevel)

        // Pure black + mild frame trail for that "floating in space" feel.
        ctx.setFillColor(UIColor(white: 0, alpha: 0.16).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let solidCount = max(1, min(6, Int(1 + params.density * 5))) // 1..6
        // Seed/grow solids array as needed.
        while solids.count < solidCount {
            solids.append(makeSolid(index: solids.count, params: params))
        }

        // Bass kick → morph one solid's shape so the geometry visibly
        // transforms on heavy hits. Cycles through all 5 shape types
        // (cube → tetra → octa → pyramid → icosa → repeat).
        let isBassKick = detectKick(params: params)
        if isBassKick && (t - lastSolidShapeChange) > 0.4 {
            let idx = Int.random(in: 0..<solidCount)
            solids[idx].shapeIdx = (solids[idx].shapeIdx + 1) % Self.shapeCount
            lastSolidShapeChange = t
        }

        let rotMul: Float = 1.0 + mid * 1.6   // mid drives rotation rate
        let baseSize = Float(min(width, height)) * 0.16
        let frameRadius = Float(min(width, height)) * 0.5

        // INTENSITY repurposed as spread — controls how far apart the
        // solids orbit from the center. Range goes from "everything
        // huddled in the middle" (×0.2) all the way to shapes orbiting
        // off-screen and crossing back (×6.2 at max), giving an extreme
        // cosmic-scale feel at the high end.
        let spreadMul: Float = 0.2 + params.intensity * 6.0

        for i in 0..<solidCount {
            var s = solids[i]
            // Update Euler angles
            s.rotX += s.rotSpeedX * rotMul * dt
            s.rotY += s.rotSpeedY * rotMul * dt
            s.rotZ += s.rotSpeedZ * rotMul * dt * 0.5
            s.orbitPhase += s.orbitFreq * (1 + mid * 0.6) * dt

            // Orbit position — multiplied by spreadMul so INTENSITY param
            // pushes shapes farther from / closer to the center.
            let radius = frameRadius * s.orbitRadiusN * spreadMul
            let ox = cx + CGFloat(cos(s.orbitPhase)) * CGFloat(radius)
            let oy = cy + CGFloat(sin(s.orbitPhase * 1.3)) * CGFloat(radius * s.orbitElev)
            let center = CGPoint(x: ox, y: oy)

            // Bass-driven scale pulse
            let size = baseSize * s.sizeN * (1.0 + bass * 0.6) * (1.0 + 0.08 * sin(t * 1.4 + Float(i)))

            // Rotate + project all vertices
            let verts = Self.vertsFor(s.shapeIdx)
            let edges = Self.edgesFor(s.shapeIdx)
            let projected: [CGPoint] = verts.map { v in
                let r = rotate3D(v, x: s.rotX, y: s.rotY, z: s.rotZ)
                return project3D(r, center: center, size: size)
            }

            // Color cycles slowly — per-solid hue offset + global hue param
            let hue = ((Double(t) * 0.05) + Double(s.hue) + Double(params.hue))
                .truncatingRemainder(dividingBy: 1.0)
            // Brightness decoupled from intensity (which now controls
            // spread). Fixed sensible baseline plus audio-driven boosts.
            let bright = 0.75 + Double(high) * 0.25 + Double(transientPulse) * 0.20
            let color = UIColor(hue: hue, saturation: 0.9, brightness: min(1, bright), alpha: 1)

            // Edge wireframe path
            let path = CGMutablePath()
            for edge in edges {
                path.move(to: projected[edge.0])
                path.addLine(to: projected[edge.1])
            }
            strokeWithGlow(ctx: ctx, path: path, color: color,
                           baseWidth: CGFloat(1.5 + bass * 2.5))

            // Vertex sparkle dots — bright pinpoints at each corner
            for p in projected {
                fillCircleWithGlow(ctx: ctx, center: p,
                                   radius: CGFloat(2.5 + bass * 4.0),
                                   color: color,
                                   intensity: 0.9)
            }

            solids[i] = s
        }
    }

    // MARK: - WMP: Classic Bars

    /// Winamp/WMP-style spectrum bars: 48 vertical rainbow columns with
    /// peak-hold caps that snap up on rise and fall slowly. Bars use
    /// log-spaced FFT bins so bass gets proper presence; per-bar
    /// asymmetric envelope so individual bars don't flicker.
    private func drawWMPBars(ctx: CGContext, params: VisualizerParams, dt: Float) {
        let spectrum = audioEngine.spectrum
        guard !spectrum.isEmpty else { return }
        let bars = wmpBarLevels.count
        // Skip DC bin (zeroed in AudioEngine) + bin 1 (windowing leakage
        // from sub-43 Hz content the FFT can't resolve). Both used to
        // peg every low-frequency bar at 100% after the spectrum
        // normalization step.
        let minBin: Float = 2
        let maxBin = Float(max(8, spectrum.count / 4))
        let ratio = maxBin / minBin

        // Layout: bars sit in the bottom 70% of the frame with 8pt margin
        // on each side and 2pt gaps between columns.
        let margin: CGFloat = 8
        let gap: CGFloat = 2
        let totalGapW = gap * CGFloat(bars - 1)
        let availableW = CGFloat(width) - margin * 2 - totalGapW
        let barW = availableW / CGFloat(bars)
        let baseY = CGFloat(height) * 0.95
        let fieldH = CGFloat(height) * 0.72

        // Peak-hold fall rate (units per second)
        let peakFall: Float = 0.50

        // Update levels + peaks. Each FFT bin gets multiplied by the
        // GAIN of the envelope band it belongs to and gated by that
        // band's THRESHOLD — same wiring as FFT Bars so the per-channel
        // audio params actually drive these bars instead of being
        // bypassed by direct spectrum access.
        for i in 0..<bars {
            let f0: Float = Float(i) / Float(bars)
            let f1: Float = Float(i + 1) / Float(bars)
            let bin0 = minBin * pow(ratio, f0)
            let bin1 = minBin * pow(ratio, f1)
            let binStart = max(Int(minBin), Int(bin0))
            let binEnd = max(binStart + 1, min(Int(maxBin), Int(bin1.rounded(.up))))
            var rawMag: Float = 0
            for b in binStart..<binEnd {
                let shaped = applyBandEnvelope(magnitude: spectrum[b], bin: b, params: params)
                rawMag = max(rawMag, shaped)
            }
            wmpBarLevels[i] = followBar(current: wmpBarLevels[i], target: rawMag, dt: dt)
            if wmpBarLevels[i] > wmpBarPeaks[i] {
                wmpBarPeaks[i] = wmpBarLevels[i]
            } else {
                wmpBarPeaks[i] = max(0, wmpBarPeaks[i] - peakFall * dt)
            }
        }

        let intensity = Double(params.intensity) + 0.3
        let hueShift = Double(params.hue)

        // Pure black background — bloom + saturated bars need it.
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Two passes: bars first, then peak caps with bloom on top so
        // the caps glow over the top edge of each bar.
        let cs = CGColorSpaceCreateDeviceRGB()
        for i in 0..<bars {
            let mag = wmpBarLevels[i]
            let barH = CGFloat(min(1, mag * 3.5)) * fieldH
            if barH < 1 { continue }
            let x = margin + CGFloat(i) * (barW + gap)
            let y = baseY - barH

            let frac = Double(i) / Double(bars - 1)
            let hue = (hueShift + frac * 0.85).truncatingRemainder(dividingBy: 1.0)
            // Vertical gradient per bar: saturated neon at the bottom
            // fading to a brighter near-white tip — gives bars that
            // glowing-LED look from WMP/Winamp instead of flat solid
            // rectangles.
            let bottom = UIColor(hue: hue, saturation: 1.0,
                                 brightness: min(1.0, intensity * 0.85), alpha: 1).cgColor
            let top = UIColor(hue: hue, saturation: 0.55,
                              brightness: min(1.0, intensity * 1.15), alpha: 1).cgColor
            guard let gradient = CGGradient(colorsSpace: cs,
                                            colors: [bottom, top] as CFArray,
                                            locations: [0, 1])
            else { continue }
            ctx.saveGState()
            ctx.clip(to: CGRect(x: x, y: y, width: barW, height: barH))
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: 0, y: baseY),
                                   end: CGPoint(x: 0, y: y),
                                   options: [])
            ctx.restoreGState()

            // Floor reflection — same gradient, flipped, lower alpha.
            // Adds the polished-glass look characteristic of WMP9-11.
            let reflH = barH * 0.5
            let reflBottom = UIColor(hue: hue, saturation: 1.0,
                                     brightness: min(1.0, intensity * 0.85), alpha: 0).cgColor
            let reflTop = UIColor(hue: hue, saturation: 1.0,
                                  brightness: min(1.0, intensity * 0.85), alpha: 0.32).cgColor
            if let reflGrad = CGGradient(colorsSpace: cs,
                                         colors: [reflBottom, reflTop] as CFArray,
                                         locations: [0, 1]) {
                ctx.saveGState()
                ctx.clip(to: CGRect(x: x, y: baseY + 2, width: barW, height: reflH))
                ctx.drawLinearGradient(reflGrad,
                                       start: CGPoint(x: 0, y: baseY + 2 + reflH),
                                       end: CGPoint(x: 0, y: baseY + 2),
                                       options: [])
                ctx.restoreGState()
            }
        }

        // Peak-hold caps — drawn last with bloom so they glow over the
        // bars beneath them. Iconic falling white blocks from WMP.
        for i in 0..<bars {
            let mag = wmpBarLevels[i]
            let peak = wmpBarPeaks[i]
            let barH = CGFloat(min(1, mag * 3.5)) * fieldH
            let peakPos = CGFloat(min(1, peak * 3.5)) * fieldH
            if peakPos < barH + 4 { continue }
            let x = margin + CGFloat(i) * (barW + gap)
            let capY = baseY - peakPos
            let frac = Double(i) / Double(bars - 1)
            let hue = (hueShift + frac * 0.85).truncatingRemainder(dividingBy: 1.0)
            // Cap is mostly white with a hint of the bar's hue.
            let capColor = UIColor(hue: hue, saturation: 0.10,
                                   brightness: 1.0, alpha: 1)
            // Soft halo via additive passes
            ctx.setBlendMode(.plusLighter)
            let halos: [(mul: CGFloat, alpha: CGFloat)] = [
                (3.0, 0.22), (1.8, 0.45), (1.0, 1.0)
            ]
            for halo in halos {
                ctx.setFillColor(capColor.withAlphaComponent(halo.alpha).cgColor)
                let h: CGFloat = 3
                let pad = (h * halo.mul - h) / 2
                ctx.fill(CGRect(x: x - pad, y: capY - pad,
                                width: barW + pad * 2, height: h + pad * 2))
            }
            ctx.setBlendMode(.normal)
        }
    }

    // MARK: - WMP: Alchemy (translucent additive ribbons)

    /// WMP Alchemy-inspired: 4-10 long parametric curves drawn with
    /// translucent strokes in additive blend mode. Where ribbons overlap
    /// the colors brighten, giving the watercolor / aurora-borealis feel
    /// Alchemy was known for. Bass drives line width + amplitude; mid
    /// drives the curve frequencies; high adds a brightness shimmer.
    private func drawAlchemy(ctx: CGContext, time t: Float, params: VisualizerParams) {
        let bass = CGFloat(activeLevel) * CGFloat(params.bassResponse * 2)
        let mid = Float(activeLevel)
        let high = Float(activeLevel)
        let count = max(4, Int(4 + params.density * 8))
        let H = CGFloat(height)
        let W = CGFloat(width)
        let cx = W * 0.5
        let cy = H * 0.5

        // Soft black wash so previous frames slowly fade — gives a
        // motion-trail look without a true feedback buffer. CG can't read
        // back the framebuffer cheaply, so we just dim the whole canvas
        // each frame with a translucent black rect.
        ctx.setFillColor(UIColor(white: 0, alpha: 0.18).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        ctx.setBlendMode(.plusLighter)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let intensity = Float(params.intensity) + 0.3

        for i in 0..<count {
            let phase: Float = t * (0.35 + Float(i) * 0.06) + Float(i) * .pi * 0.27
            let curveA: Float = 1.5 + Float(i) * 0.32 + mid * 1.5
            let curveB: Float = 1.1 + Float(i) * 0.21 + mid * 1.1
            let hue = ((Double(t) * 0.04) + Double(i) * 0.13 + Double(params.hue)).truncatingRemainder(dividingBy: 1.0)
            let bright = 0.65 + Double(high) * 0.35
            // Lower alpha because additive blending stacks them; multiple
            // ribbons overlapping should saturate to bright white only at
            // the convergences.
            let alpha = 0.30 * Double(intensity)
            let color = UIColor(hue: hue, saturation: 0.95,
                                brightness: min(1, bright), alpha: alpha).cgColor
            ctx.setStrokeColor(color)
            ctx.setLineWidth(7 + bass * 14)

            ctx.beginPath()
            let segments = 96
            for s in 0..<segments {
                let frac: Float = Float(s) / Float(segments - 1)
                // Lissajous-style parametric curve, each ribbon different.
                let x1: Float = sin(frac * curveA * 2 * .pi + phase)
                let y1: Float = sin(frac * curveB * 2 * .pi + phase * 1.3 + 0.5)
                // Center-heavy radius — peaks at frac=0.5 so ribbons feel
                // like they fall in from off-screen and back out.
                let radEnvelope: Float = sin(frac * .pi)
                let radius: Float = 0.32 + 0.22 * radEnvelope
                // Bass adds a second, slower wobble across the path.
                let bassWob: Float = Float(bass) * 0.4 * sin(frac * .pi * 2 + phase * 0.5)
                let x = cx + CGFloat(x1) * W * CGFloat(radius)
                let y = cy + CGFloat(y1 + bassWob) * H * CGFloat(radius)
                if s == 0 { ctx.move(to: CGPoint(x: x, y: y)) }
                else { ctx.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.strokePath()
        }
        ctx.setBlendMode(.normal)
    }

    // MARK: - Plasma: Lightning

    private func drawLightning(ctx: CGContext, time t: Float, params: VisualizerParams, dt: Float) {
        // Spawn a new bolt on bass kick OR hi-hat transient. Same
        // param-driven kick threshold as everywhere else so the
        // sensitivity slider behaves consistently across visualizers.
        let isBassKick = detectKick(params: params)
        let isTransient = transientPulse > 0.4
        if (isTransient || isBassKick) && bolts.count < Int(2 + params.density * 6) {
            spawnBolt(params: params)
        }

        // Frame-trail wash so bolt afterglow lingers briefly — gives that
        // "lightning leaves an imprint" feel of plasma-style displays.
        ctx.setFillColor(UIColor(white: 0, alpha: 0.25).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        // Decay + render with full bloom passes
        var i = 0
        while i < bolts.count {
            bolts[i].life -= dt * 1.4 // ~0.7s lifespan, frame-rate-independent
            if bolts[i].life <= 0 { bolts.remove(at: i); continue }
            let life = CGFloat(bolts[i].life)
            let hue: Double = Double(bolts[i].hue)
            let bassW: CGFloat = CGFloat(activeLevel)
            // Build the bolt path once, then bloom + bright core.
            let path = boltPath(bolts[i])
            let haloColor = UIColor(hue: hue, saturation: 0.55, brightness: 1.0, alpha: 1)
            // Halo width scales with kickStrength so the slider visibly
            // changes how dramatic each bolt looks.
            let kickW: CGFloat = 0.6 + CGFloat(params.kickStrength) * 0.8
            strokeWithGlow(ctx: ctx, path: path, color: haloColor,
                           baseWidth: (6 + bassW * 8) * kickW,
                           intensity: life * CGFloat(params.intensity + 0.3))
            // Hot white core inside the halo for that "plasma arc" feel
            ctx.setBlendMode(.plusLighter)
            ctx.setStrokeColor(UIColor(white: 1, alpha: Double(life)).cgColor)
            ctx.setLineWidth(1.5 + bassW * 2)
            ctx.addPath(path)
            ctx.strokePath()
            ctx.setBlendMode(.normal)
            i += 1
        }

        // Faint overall flash tint from the brightest live bolt
        if let live = bolts.first, live.life > 0.5 {
            ctx.setFillColor(UIColor(white: 1, alpha: 0.06 * Double(live.life)).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func boltPath(_ bolt: Bolt) -> CGPath {
        let path = CGMutablePath()
        guard bolt.points.count > 1 else { return path }
        path.move(to: bolt.points[0])
        for i in 1..<bolt.points.count { path.addLine(to: bolt.points[i]) }
        return path
    }

    private func spawnBolt(params: VisualizerParams) {
        let cx = CGFloat(width) * 0.5
        let cy = CGFloat(height) * 0.5
        let startSide = Int.random(in: 0..<4)
        var p0: CGPoint
        switch startSide {
        case 0: p0 = CGPoint(x: CGFloat.random(in: 0...CGFloat(width)), y: 0)
        case 1: p0 = CGPoint(x: CGFloat(width), y: CGFloat.random(in: 0...CGFloat(height)))
        case 2: p0 = CGPoint(x: CGFloat.random(in: 0...CGFloat(width)), y: CGFloat(height))
        default: p0 = CGPoint(x: 0, y: CGFloat.random(in: 0...CGFloat(height)))
        }
        let p1 = CGPoint(x: cx + CGFloat.random(in: -100...100), y: cy + CGFloat.random(in: -100...100))
        // Build a jagged path of N segments between p0 and p1
        let segs = 12 + Int.random(in: 0...8)
        var pts: [CGPoint] = []
        for s in 0...segs {
            let frac = CGFloat(s) / CGFloat(segs)
            let baseX = p0.x + (p1.x - p0.x) * frac
            let baseY = p0.y + (p1.y - p0.y) * frac
            // Perpendicular jitter
            let dx = p1.x - p0.x, dy = p1.y - p0.y
            let len = sqrt(dx*dx + dy*dy)
            let nx = len > 0 ? -dy / len : 0
            let ny = len > 0 ? dx / len : 0
            let jitter = (s == 0 || s == segs) ? 0 : CGFloat.random(in: -40...40)
            pts.append(CGPoint(x: baseX + nx * jitter, y: baseY + ny * jitter))
        }
        bolts.append(Bolt(points: pts, life: 1.0, hue: Float.random(in: 0...0.2) + params.hue))
    }

    // MARK: - Plasma: Mandala

    private func drawMandala(ctx: CGContext, time t: Float, params: VisualizerParams) {
        let cx = CGFloat(width) * 0.5
        let cy = CGFloat(height) * 0.5
        let bass = CGFloat(activeLevel) * CGFloat(params.bassResponse * 2)
        let mid = CGFloat(activeLevel)
        let high = CGFloat(activeLevel)
        // 8-fold symmetric pattern. Build a single "wedge" shape, then
        // rotate/draw N times for the kaleidoscope feel.
        let folds = max(4, Int(4 + params.density * 12))
        let baseRot = CGFloat(t) * 0.4 + bass * 0.6
        let petalLen: CGFloat = CGFloat(min(width, height)) * 0.35 * (1 + bass * 0.5)

        // Pure black background.
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setLineCap(.round)

        for f in 0..<folds {
            ctx.saveGState()
            ctx.translateBy(x: cx, y: cy)
            let rot: CGFloat = baseRot + CGFloat(f) / CGFloat(folds) * 2 * CGFloat.pi
            ctx.rotate(by: rot)

            let hue = ((Double(t) * 0.06) + Double(f) * 0.05 + Double(params.hue)).truncatingRemainder(dividingBy: 1.0)
            let bright = min(1.0, (0.7 + Double(high) * 0.3 + Double(mid) * 0.15) * Double(params.intensity + 0.3))
            let color = UIColor(hue: hue, saturation: 0.95, brightness: bright, alpha: 1)

            // Petal: a thin tear-drop made from two arcs — drawn with glow
            let path = CGMutablePath()
            let petalW: CGFloat = 30 + bass * 40
            path.move(to: CGPoint(x: 0, y: 0))
            path.addQuadCurve(to: CGPoint(x: petalLen, y: 0),
                              control: CGPoint(x: petalLen * 0.5, y: -petalW))
            path.addQuadCurve(to: CGPoint(x: 0, y: 0),
                              control: CGPoint(x: petalLen * 0.5, y: petalW))
            strokeWithGlow(ctx: ctx, path: path, color: color,
                           baseWidth: 1.5 + bass * 2.5)

            // Glowing tip orb
            fillCircleWithGlow(ctx: ctx,
                               center: CGPoint(x: petalLen, y: 0),
                               radius: 4 + bass * 4,
                               color: color, intensity: 1.0)

            ctx.restoreGState()
        }

        // Center burst with full bloom
        let cr = 6 + bass * 30
        fillCircleWithGlow(ctx: ctx,
                           center: CGPoint(x: cx, y: cy),
                           radius: cr,
                           color: UIColor(white: 1, alpha: 1),
                           intensity: min(1.0, CGFloat(0.6 + bass * 0.6)))
    }

    // MARK: - HSV → RGB helper for plasma

    private func hsvToRGB(h: Float, s: Float, v: Float) -> (UInt8, UInt8, UInt8) {
        let i = Int(h * 6) % 6
        let f = h * 6 - Float(i)
        let p = v * (1 - s)
        let q = v * (1 - f * s)
        let tt = v * (1 - (1 - f) * s)
        let r: Float, g: Float, b: Float
        switch i {
        case 0: r = v; g = tt; b = p
        case 1: r = q; g = v; b = p
        case 2: r = p; g = v; b = tt
        case 3: r = p; g = q; b = v
        case 4: r = tt; g = p; b = v
        default: r = v; g = p; b = q
        }
        return (UInt8(max(0, min(255, r * 255))),
                UInt8(max(0, min(255, g * 255))),
                UInt8(max(0, min(255, b * 255))))
    }

    // MARK: - Plasma: Spiral

    private func drawSpiral(ctx: CGContext, time t: Float, params: VisualizerParams) {
        let cx = CGFloat(width) * 0.5
        let cy = CGFloat(height) * 0.5
        let bass = CGFloat(activeLevel) * CGFloat(params.bassResponse * 2)
        let high = CGFloat(activeLevel)
        let arms = max(2, Int(2 + params.density * 6))
        let rotBase: CGFloat = CGFloat(t) * 0.6
        let rMax: CGFloat = CGFloat(min(width, height)) * 0.45 * (1 + bass * 0.4)

        // Pure black; bloom needs it.
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setLineCap(.round)

        for arm in 0..<arms {
            let armOffset: CGFloat = CGFloat(arm) / CGFloat(arms) * 2 * CGFloat.pi
            let segments = 96
            let hue = (Double(t) * 0.08 + Double(arm) * 0.2 + Double(params.hue)).truncatingRemainder(dividingBy: 1.0)
            let bright = min(1.0, (0.7 + Double(high) * 0.3) * Double(params.intensity + 0.3))
            let color = UIColor(hue: hue, saturation: 0.95, brightness: bright, alpha: 1)

            let path = CGMutablePath()
            for s in 0..<segments {
                let frac = CGFloat(s) / CGFloat(segments - 1)
                let r = frac * rMax
                let a = rotBase + armOffset + frac * 6 * CGFloat.pi
                let x = cx + cos(a) * r
                let y = cy + sin(a) * r
                if s == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            strokeWithGlow(ctx: ctx, path: path, color: color,
                           baseWidth: 2 + bass * 3)

            // Bright dot at the spiral arm's tip — characteristic
            // pinpoint sparkle that gives spiral arms their "trailing
            // sparkle" feel.
            let tipR = rMax
            let tipA = rotBase + armOffset + 1.0 * 6 * CGFloat.pi
            let tipPoint = CGPoint(x: cx + cos(tipA) * tipR,
                                   y: cy + sin(tipA) * tipR)
            fillCircleWithGlow(ctx: ctx, center: tipPoint,
                               radius: 4 + bass * 6,
                               color: color, intensity: 1.0)
        }
    }

    // MARK: - Plasma: Ribbons

    private func drawRibbons(ctx: CGContext, time t: Float, params: VisualizerParams) {
        let bass = CGFloat(activeLevel) * CGFloat(params.bassResponse * 2)
        let mid = CGFloat(activeLevel)
        let high = CGFloat(activeLevel)
        let count = max(3, Int(3 + params.density * 9))
        let H = CGFloat(height)
        let W = CGFloat(width)

        // Pure black + frame trail for that flowing motion-blur look.
        // Translucent black wash dims previous frame ~22%.
        ctx.setFillColor(UIColor(white: 0, alpha: 0.22).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        for i in 0..<count {
            let yBase = H * (CGFloat(i) + 1) / CGFloat(count + 1)
            let amp = H * 0.10 * (1 + bass * 1.5)
            let phaseSpeed: Float = 0.8 + Float(i) * 0.15
            let freq: Float = 1.5 + Float(i) * 0.3 + Float(mid) * 2
            let hue = (Double(t) * 0.05 + Double(i) * 0.12 + Double(params.hue)).truncatingRemainder(dividingBy: 1.0)
            let bright = min(1.0, (0.75 + Double(high) * 0.25) * Double(params.intensity + 0.3))
            let color = UIColor(hue: hue, saturation: 0.95, brightness: bright, alpha: 1)

            let path = CGMutablePath()
            let segments = 96
            // Build a list of points first, then draw with smooth quad
            // curves between them. Straight line segments looked
            // jagged at high motion.
            var pts: [CGPoint] = []
            for s in 0..<segments {
                let frac = Float(s) / Float(segments - 1)
                let x = CGFloat(frac) * W
                let y = yBase + CGFloat(sin(frac * freq * 2 * .pi + t * phaseSpeed)) * amp
                pts.append(CGPoint(x: x, y: y))
            }
            path.move(to: pts[0])
            // Catmull-Rom-ish smoothing: quad-curve through midpoints
            for s in 1..<(pts.count - 1) {
                let mid = CGPoint(x: (pts[s].x + pts[s + 1].x) / 2,
                                  y: (pts[s].y + pts[s + 1].y) / 2)
                path.addQuadCurve(to: mid, control: pts[s])
            }
            path.addLine(to: pts.last!)
            strokeWithGlow(ctx: ctx, path: path, color: color,
                           baseWidth: 2 + bass * 4)
        }
    }
}

/// Weakly retains the source so the CADisplayLink doesn't keep it alive
/// past `stop()`. CADisplayLink retains its target strongly; using a proxy
/// is the standard pattern.
private final class DisplayLinkProxy {
    weak var owner: AudioVisualizerSource?
    init(_ owner: AudioVisualizerSource) { self.owner = owner }
    @objc func tick() { owner?.render() }
}
