import SwiftUI
import PhotosUI
import AVFoundation

struct SourcePickerView: View {
    let channel: Channel
    let renderEngine: RenderEngine
    let inputManager: InputManager
    /// Called when a source is chosen or "Clear Source" is hit. The host
    /// uses this to dismiss the panel/sheet that contains us. When nil
    /// (e.g. legacy sheet usage) we fall back to `dismiss()`.
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) var dismiss

    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var selectedImageItem: PhotosPickerItem?
    @State private var cameraStatus: AVAuthorizationStatus = .notDetermined
    /// Latest live envelope values (post-GAIN / post-THRESHOLD / post-
    /// ATTACK / RELEASE) read from the active AudioVisualizerSource.
    /// Polled at 30fps; drives the band-tab meters so the user can see
    /// their envelope tweaks take effect.
    @State private var liveEnvelopeOutputs: [Float] = [0, 0, 0, 0]
    private let envPollTimer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    /// The selected/reactive band — this is now routed directly through
    /// `channel.visualizerParams.reactiveBand`. Tapping a tab routes
    /// reactivity to that band AND switches the editor to its params.
    private var selectedEnvBand: Int { channel.visualizerParams.reactiveBand }

    private func close() {
        if let onClose = onClose { onClose() } else { dismiss() }
    }

    var body: some View {
        // No NavigationStack — the host (panel header or sheet wrapper)
        // provides the title bar and close button. Embedding our own here
        // would create double chrome inside the panel.
        ScrollView {
                VStack(spacing: 12) {
                    // Camera
                    sourceSection("Camera") {
                        if cameraStatus == .denied || cameraStatus == .restricted {
                            cameraDeniedBanner
                        }
                        sourceRow(icon: "camera", label: "Back Camera", tint: .blue) {
                            selectSource(.camera(position: .back))
                        }
                        sourceRow(icon: "camera.rotate", label: "Front Camera", tint: .blue) {
                            selectSource(.camera(position: .front))
                        }
                        if !CameraHub.shared.isMultiCamSupported {
                            singleCamHint
                        }
                    }

                    // External / UVC — HDMI capture cards, USB webcams,
                    // Continuity Camera, Studio Display camera, etc. The
                    // device list updates live as cards are plugged in or
                    // unplugged (CameraHub publishes via KVO).
                    sourceSection("External Capture (UVC)") {
                        let externals = CameraHub.shared.availableExternalDevices
                        if externals.isEmpty {
                            HStack(spacing: 10) {
                                Image(systemName: "cable.connector")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("No capture devices")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white.opacity(0.7))
                                    Text("Connect an HDMI capture card or USB camera via USB-C")
                                        .font(.system(size: 10))
                                        .foregroundColor(.gray)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                        } else {
                            ForEach(externals, id: \.uniqueID) { device in
                                sourceRow(icon: "cable.connector", label: device.localizedName, tint: .orange) {
                                    selectSource(.externalCamera(
                                        uniqueID: device.uniqueID,
                                        displayName: device.localizedName
                                    ))
                                }
                            }
                        }
                    }

                    // NDI Sources
                    sourceSection("NDI Network Sources") {
                        if inputManager.discoveredNDISources.isEmpty {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Scanning local network...")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 6)
                        } else {
                            ForEach(inputManager.discoveredNDISources, id: \.name) { source in
                                sourceRow(icon: "network", label: source.name, tint: .cyan) {
                                    selectSource(.ndi(sourceName: source.name, ipAddress: source.address))
                                }
                            }
                        }
                    }

                    // Video
                    sourceSection("Video") {
                        PhotosPicker(selection: $selectedVideoItem, matching: .videos) {
                            HStack(spacing: 10) {
                                Image(systemName: "film")
                                    .font(.system(size: 16))
                                    .foregroundColor(.green)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Choose Video")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                    Text("MP4, MOV, M4V from your library")
                                        .font(.system(size: 10))
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray.opacity(0.4))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                    }

                    // Images
                    sourceSection("Images") {
                        PhotosPicker(selection: $selectedImageItem, matching: .images) {
                            HStack(spacing: 10) {
                                Image(systemName: "photo")
                                    .font(.system(size: 16))
                                    .foregroundColor(.cyan)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Choose Image")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                    Text("JPG, PNG, HEIF from your library")
                                        .font(.system(size: 10))
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray.opacity(0.4))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                    }

                    // Solid Colors
                    sourceSection("Solid Colors") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                            colorSwatch("BLK", .black, r: 0, g: 0, b: 0)
                            colorSwatch("WHT", .white, r: 1, g: 1, b: 1)
                            colorSwatch("RED", Color(red: 1.0, green: 0.15, blue: 0.15), r: 1, g: 0, b: 0)
                            colorSwatch("GRN", Color(red: 0.15, green: 0.85, blue: 0.3), r: 0, g: 1, b: 0)
                            colorSwatch("BLU", Color(red: 0.2, green: 0.4, blue: 1.0), r: 0, g: 0, b: 1)
                            colorSwatch("YLW", Color(red: 1.0, green: 0.9, blue: 0.1), r: 1, g: 1, b: 0)
                            colorSwatch("CYN", Color(red: 0.1, green: 0.9, blue: 0.9), r: 0, g: 1, b: 1)
                            colorSwatch("MAG", Color(red: 1.0, green: 0.2, blue: 0.8), r: 1, g: 0, b: 1)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                    }

                    // Test Patterns
                    sourceSection("Test Patterns") {
                        ForEach(PatternType.allCases) { pattern in
                            sourceRow(icon: "checkerboard.rectangle", label: pattern.displayName, tint: .purple) {
                                selectSource(.pattern(pattern))
                            }
                        }
                    }

                    // Audio Visualizer — live mic input rendered as video.
                    // Mic permission is requested by AudioEngine on first
                    // start; if denied the visualizer renders flat (no
                    // motion) but does not crash.
                    sourceSection("Audio Visualizer") {
                        ForEach(VisualizerStyle.allCases) { style in
                            sourceRow(icon: style.icon, label: style.displayName, tint: .pink) {
                                selectSource(.audioVisualizer(style))
                            }
                        }
                    }

                    // Visualizer params + audio-reactivity controls — only
                    // shown when a plasma variant is currently selected.
                    // Tweaks live on `channel.visualizerParams` and are
                    // read by AudioVisualizerSource each frame.
                    if case .audioVisualizer = channel.source {
                        sourceSection("Visualizer Params") {
                            visualizerVisualSliders
                        }
                        sourceSection("Audio Reactivity — Tap Band to Route") {
                            visualizerAudioSliders
                        }
                    }

                    // Clear source
                    if channel.source != nil {
                        Button {
                            channel.source = nil
                            inputManager.clearSource(for: channel.id, renderEngine: renderEngine)
                            close()
                        } label: {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                Text("Clear Source")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                Rectangle()
                                    .fill(Color.red.opacity(0.1))
                                    .overlay(
                                        Rectangle()
                                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                        .padding(.horizontal, 16)
                    }

                    Spacer(minLength: 20)
                }
                .padding(.top, 8)
        }
        .background(Color(red: 0.08, green: 0.08, blue: 0.1))
        .onChange(of: selectedVideoItem) { _, newItem in
            if let item = newItem { loadMedia(from: item, isVideo: true) }
        }
        .onChange(of: selectedImageItem) { _, newItem in
            if let item = newItem { loadMedia(from: item, isVideo: false) }
        }
        .onAppear {
            cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        }
        .onReceive(envPollTimer) { _ in
            // Pull the live post-envelope values from the active visualizer
            // source on this channel, if any. Drives the live band meters.
            if let envs = inputManager.liveVisualizerEnvelopes(for: channel.id), envs.count == 4 {
                liveEnvelopeOutputs = envs
            }
        }
    }

    private var singleCamHint: some View {
        // Heads-up for older iPads (iPad 7 and earlier, A11-and-older Pros)
        // that don't support AVCaptureMultiCamSession. Single camera works,
        // assigning a second simultaneously won't.
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 13))
                .foregroundColor(.gray)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("One camera at a time")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(.white.opacity(0.85))
                Text("This iPad doesn't support running both cameras simultaneously. Switching between front/back works as expected.")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.white.opacity(0.04))
    }

    private var cameraDeniedBanner: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.yellow)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Camera Access Denied")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(.white)
                    Text("Tap to open Settings → enable Camera for WasteMix")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 12))
                    .foregroundColor(.yellow.opacity(0.7))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color.yellow.opacity(0.10))
            .overlay(Rectangle().stroke(Color.yellow.opacity(0.3), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Visualizer Params

    /// Visual-only knobs (density, speed, color, brightness).
    @ViewBuilder
    private var visualizerVisualSliders: some View {
        VStack(spacing: 10) {
            visParamSlider(label: "DENSITY", value: Binding(
                get: { channel.visualizerParams.density },
                set: { channel.visualizerParams.density = $0 }
            ))
            visParamSlider(label: "SPEED", value: Binding(
                get: { channel.visualizerParams.speed },
                set: { channel.visualizerParams.speed = $0 }
            ))
            visParamSlider(label: "HUE", value: Binding(
                get: { channel.visualizerParams.hue },
                set: { channel.visualizerParams.hue = $0 }
            ))
            visParamSlider(label: "INTENSITY", value: Binding(
                get: { channel.visualizerParams.intensity },
                set: { channel.visualizerParams.intensity = $0 }
            ))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    /// Audio-reactivity panel — 5-channel LZX-style envelope system
    /// (SUB / BASS / MID / HIGH / AIR), each with its own gain, attack,
    /// release, and gate threshold, plus the global kick / sway knobs
    /// that apply across all visualizer variants.
    @ViewBuilder
    private var visualizerAudioSliders: some View {
        VStack(spacing: 14) {
            // 5 band tabs across the top. Tap to select; the 4 sliders
            // below show the params for the selected band.
            HStack(spacing: 4) {
                ForEach(EnvelopeBand.allCases, id: \.rawValue) { band in
                    envBandTab(band)
                }
            }

            // Active-band info row + 4 sliders. The .id() on the inner
            // VStack forces SwiftUI to tear down and rebuild the four
            // sliders whenever `selectedEnvBand` changes — without this
            // it was reusing the same Slider views with updated bindings,
            // and the displayed value/knob position wasn't refreshing
            // even though the underlying binding was correct.
            let band = EnvelopeBand(rawValue: selectedEnvBand) ?? .low
            VStack(spacing: 8) {
                HStack {
                    Text(band.name)
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundColor(envBandColor(band))
                    Text(band.freqLabel)
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundColor(.gray)
                    Spacer()
                }
                envSlider(label: "GAIN", value: envBinding(\.gain), range: 0...2,
                          formatter: { String(format: "%.2fx", $0) })
                envSlider(label: "ATTACK", value: envBinding(\.attack), range: 0...1,
                          formatter: attackTimeLabel)
                envSlider(label: "RELEASE", value: envBinding(\.release), range: 0...1,
                          formatter: releaseTimeLabel)
                envSlider(label: "THRESHOLD", value: envBinding(\.threshold), range: 0...1,
                          formatter: { String(format: "%.2f", $0) })
            }
            .id(selectedEnvBand)

            Divider().background(Color.white.opacity(0.1))

            // Global knobs (apply across every variant)
            Text("BEAT + MOTION")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundColor(.gray.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
            // Master smoothness macro — scales every band's attack +
            // release at once. Lets you go from twitchy (low) to dreamy
            // (high) without tweaking each of the 5 bands individually.
            visParamSlider(label: "SMOOTHING", value: Binding(
                get: { channel.visualizerParams.smoothing },
                set: { channel.visualizerParams.smoothing = $0 }
            ))
            visParamSlider(label: "KICK SENS", value: Binding(
                get: { channel.visualizerParams.kickSensitivity },
                set: { channel.visualizerParams.kickSensitivity = $0 }
            ))
            visParamSlider(label: "KICK PUNCH", value: Binding(
                get: { channel.visualizerParams.kickStrength },
                set: { channel.visualizerParams.kickStrength = $0 }
            ))
            visParamSlider(label: "SWAY", value: Binding(
                get: { channel.visualizerParams.swayAmount },
                set: { channel.visualizerParams.swayAmount = $0 }
            ))
            visParamSlider(label: "BASS DRIVE", value: Binding(
                get: { channel.visualizerParams.bassResponse },
                set: { channel.visualizerParams.bassResponse = $0 }
            ))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: - Envelope panel components

    private func envBandTab(_ band: EnvelopeBand) -> some View {
        let isSelected = selectedEnvBand == band.rawValue
        let color = envBandColor(band)
        // Live input meter for this band — pulled from the channel's
        // VisualizerParams envelope readback so the meter follows the
        // user's gain/attack settings.
        let level = liveEnvelopeLevel(band: band)
        return Button {
            // Route reactivity to this band AND make the editor sliders
            // load this band's params (one tap, two effects — single-band
            // routing means selection IS the routing).
            channel.visualizerParams.reactiveBand = band.rawValue
        } label: {
            VStack(spacing: 3) {
                Text(band.name)
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(isSelected ? .white : color.opacity(0.85))
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.07)).frame(height: 4)
                    GeometryReader { geo in
                        Rectangle().fill(color)
                            .frame(width: geo.size.width * CGFloat(min(1, level)))
                    }
                    .frame(height: 4)
                }
            }
            .padding(.vertical, 6).padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .background(isSelected ? color.opacity(0.25) : Color.white.opacity(0.05))
            .overlay(Rectangle().stroke(isSelected ? color : Color.white.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func envBandColor(_ band: EnvelopeBand) -> Color {
        switch band {
        case .low: return Color(red: 1.00, green: 0.35, blue: 0.25)   // amber-red
        case .mid: return Color(red: 0.95, green: 0.80, blue: 0.25)   // yellow
        case .high: return Color(red: 0.30, green: 0.85, blue: 0.95)  // cyan
        case .full: return Color(red: 0.85, green: 0.55, blue: 1.00)  // violet
        }
    }

    /// Reads the live post-envelope output for a band — i.e. the value
    /// AFTER the user's GAIN / THRESHOLD / ATTACK / RELEASE shaping has
    /// been applied. This is the actual signal the visualizer is using
    /// each frame, polled at 30fps from the AudioVisualizerSource via
    /// `inputManager.liveVisualizerEnvelopes(for:)`. If the source isn't
    /// a visualizer (or hasn't started yet), we fall back to a synthetic
    /// estimate (raw audio × stored gain) so the meters still move.
    private func liveEnvelopeLevel(band: EnvelopeBand) -> Float {
        let idx = band.rawValue
        if idx < liveEnvelopeOutputs.count, liveEnvelopeOutputs[idx] > 0.0001 {
            return min(1, liveEnvelopeOutputs[idx])
        }
        // Fallback: synthetic estimate from raw audio engine levels ×
        // user gain so the meters still animate even before a visualizer
        // source has started.
        let e = renderEngine.audioEngine
        let envs = channel.visualizerParams.envelopes
        let g = idx < envs.count ? envs[idx].gain : 1.0
        switch band {
        case .low: return min(1, (e.subBass + e.bass) * 0.5 * g)
        case .mid: return min(1, ((e.lowMid + e.mid + e.highMid) / 3.0) * g)
        case .high: return min(1, (e.high + e.brilliance) * 0.5 * g)
        case .full: return min(1, e.level * g)
        }
    }

    /// Binding to a per-channel envelope param keypath (gain / attack /
    /// release / threshold), routed through `selectedEnvBand`. Lets the
    /// 4 sliders below the tabs all share one source of truth.
    private func envBinding(_ kp: WritableKeyPath<EnvelopeChannel, Float>) -> Binding<Float> {
        Binding(
            get: { channel.visualizerParams.envelopes[selectedEnvBand][keyPath: kp] },
            set: { channel.visualizerParams.envelopes[selectedEnvBand][keyPath: kp] = $0 }
        )
    }

    /// Slider with a value-formatter callback so attack/release can be
    /// shown as ms instead of 0–1 normalized.
    private func envSlider(label: String, value: Binding<Float>,
                           range: ClosedRange<Float>,
                           formatter: @escaping (Float) -> String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 84, alignment: .leading)
            Slider(value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Float($0) }
            ), in: Double(range.lowerBound)...Double(range.upperBound))
            .tint(envBandColor(EnvelopeBand(rawValue: selectedEnvBand) ?? .low))
            Text(formatter(value.wrappedValue))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 56, alignment: .trailing)
        }
    }

    // Attack 0..1 → 5..150 ms. Release 0..1 → 30..1500 ms. Showing the
    // actual time on the slider's value readout so users can dial a
    // specific ms target.
    private func attackTimeLabel(_ v: Float) -> String {
        let ms = (5 + v * 145).rounded()
        return "\(Int(ms)) ms"
    }
    private func releaseTimeLabel(_ v: Float) -> String {
        let ms = (30 + v * 1470).rounded()
        return "\(Int(ms)) ms"
    }

    private func visParamSlider(label: String, value: Binding<Float>) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(.gray)
                .frame(width: 72, alignment: .leading)
            Slider(value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Float($0) }
            ), in: 0...1)
            .tint(.pink)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 40, alignment: .trailing)
        }
    }

    // MARK: - Components

    private func sourceSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(.gray)
                .tracking(1)
                .padding(.horizontal, 20)

            VStack(spacing: 1) {
                content()
            }
            .background(Color.white.opacity(0.04))
            .clipShape(Rectangle())
            .overlay(
                Rectangle()
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
        }
    }

    private func sourceRow(icon: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(tint)
                    .frame(width: 28)
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(.gray.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func colorSwatch(_ label: String, _ color: Color, r: Float, g: Float, b: Float) -> some View {
        Button {
            selectSource(.solidColor(red: r, green: g, blue: b))
        } label: {
            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                    )
                    .shadow(color: color.opacity(0.4), radius: 3)
                Text(label)
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundColor(.gray)
            }
        }
    }

    // MARK: - Actions

    private func selectSource(_ source: ContentSource) {
        channel.source = source
        inputManager.applySource(source, to: channel.id, channel: channel, renderEngine: renderEngine)
        close()
    }

    private func loadMedia(from item: PhotosPickerItem, isVideo: Bool) {
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let ext = isVideo ? "mov" : "png"
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(ext)
                try? data.write(to: tempURL)

                await MainActor.run {
                    if isVideo {
                        selectSource(.mediaFile(url: tempURL))
                    } else {
                        selectSource(.image(url: tempURL))
                    }
                }
            }
        }
    }
}
