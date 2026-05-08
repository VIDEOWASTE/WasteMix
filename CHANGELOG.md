# Changelog

All notable changes to **WasteMix** are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/).

> **Working convention** — every change made to `main` should add a line under `[Unreleased]` in the appropriate subsection (`Added`, `Changed`, `Fixed`, `Removed`, `Security`). When cutting a release, the `[Unreleased]` block is renamed to the new version + date and a fresh empty `[Unreleased]` is added at the top.

## [Unreleased]

---

## [0.0.6] — 2026-05-08

iPad camera framing & PIP overhaul. Camera frames now follow device orientation (landscape↔portrait) live via `RotationCoordinator`, dropping the static 180° iPad-TrueDepth workaround. Per-channel rotation override + Fit / Fill / Stretch aspect modes for non-16:9 sources, with PIP rotation as a new parameter. PIP now applies inside the per-channel pipeline so all changes show in PVW, not just PGM.

### Added
- **Live camera rotation tracking** — `CameraHub` installs an `AVCaptureDevice.RotationCoordinator` per camera position and KVO-observes `videoRotationAngleForHorizonLevelCapture`, writing the live angle to the connection. Frames stay upright when the iPad rotates.
- **Per-channel framing override** (`FRAMING` section in FX PARAMS panel, camera sources only):
  - `ROTATION` — Auto / 0° / 90° / 180° / 270° override on top of the auto-tracked angle.
  - `ASPECT` — Fit (letterbox), Fill (crop edges, default for new channels), Stretch (distort to fill).
  - New `fragment_transform` Metal pass running at the tail of `ChannelRenderer.currentTexture()` produces program-canvas-sized (1920×1080) output per channel, ending the implicit aspect-stretch the compositor used to do.
- **PIP rotation slider** — `ROTATE` in the `PIP / POSITION` section, range -180°…+180°. Aspect-correct so a square PIP stays square when rotated. Works at any scale (PIP shrink, fullscreen, overscan).

### Changed
- **PIP applied per channel, not in the compositor** — the PIP render pass moved from `CompositorPipeline.applyPIPIfNeeded` into `ChannelRenderer.applyPIP`, so PIP scale/offset/rotation now show up in PVW and not just PGM. `ChannelCompositeInfo.pipSettings` removed.
- **`PIP / POSITION` reset is always visible**, greys out when settings are at default.
- **Default channel `fitMode` is now `.fill`** (was `.fit`) — portrait cameras crop to fill the canvas instead of letterboxing by default.

### Fixed
- iPad TrueDepth front camera is no longer hard-coded to a 180° flip; the rotation coordinator gives the correct angle for each device + orientation.

---

## [0.0.5] — 2026-05-07

Audio Visualizer source + LZX-style 4-band envelope reactivity system. 13 visualizer styles with proper neon-on-black bloom, Tunnel rebuilt as a 3D polygon corridor, new Geometry (3D solids) variant, single-band routing so any band drives the whole visualizer.

### Added
- **Audio Visualizer source** — pick a channel's source as `Audio: FFT Bars`, `Audio: Waveform`, `Audio: Bars + Waveform`, or one of five WMP-style plasma variants (`Polygons`, `Tunnel`, `Particles`, `Spiral`, `Ribbons`). Pulls from the shared `AudioEngine` (mic input). Renders at 30fps via `CADisplayLink` to a 1280×720 CVPixelBuffer using CGContext drawing. Each plasma variant has its own animated abstract pattern reacting to bass / mid / high band levels and transient peaks (hi-hat / snare hits → particle bursts, ray flashes, etc.).
- **Visualizer Params section** in the source picker (only shown when a plasma variant is selected) — five sliders: DENSITY (object count), SPEED (animation rate), HUE (color shift), INTENSITY (brightness), BASS (response strength). Stored on `Channel.visualizerParams`; the source reads them each frame so tweaks are live.

### Fixed
- **PVW glitch with audio visualizer** — single-buffer CPU drawing raced with the GPU consumer (PVW MTKView, compositor sampling). Switched to a 3-buffer ring: `latestPixelBuffer` returns the most recently completed buffer while we draw into the next slot. Consumer never sees a half-drawn frame.
- **"Clear Source" left the last frame on PVW** — `RenderEngine.tickRender` only updated `channelPreviewTextures[i]` when a new texture arrived, so it kept the last frame from the previous source forever after `setSource(nil, ...)`. Now nils the slot when the source is gone.
- **"Clear Source" still showed the stale frame** (round 2) — root cause was `ChannelRenderer.lastSourceTexture` being sticky: when the frame provider went nil, the cached last frame kept getting reprocessed through color/effect/key, so `currentTexture(...)` never returned nil and the previous fix didn't trigger. Added a `didSet` on `frameProvider` that drops `lastSourceTexture` and `frozenTexture` when the provider goes nil.

### Changed
- **Source picker now opens in a panel** instead of a full-screen sheet — keeps PVW and PGM monitors visible at the top, matches the FX / COLOR / AUDIO REACT / MASTER LFO panel pattern. `SourcePickerView` had its `NavigationStack` + toolbar stripped (the panel header provides title + close); `dismiss()` calls swapped for an `onClose` closure. `MixerView.PanelType` gained a `.source(Int)` case.
- **Waveform redesigned** — now a static horizontal centerline with vertical "value stems" bouncing symmetrically above and below it (was a wiggling polyline). 64 stems, sin-windowed amplitude (peaks in middle, tapers at edges), glow underlay + crisp top stroke per stem.
- **Plasma family expanded + reworked**: `.plasma` is now a true demoscene flowing-color plasma (3-sin sinusoidal color field rendered at 160×90 and bilinear-upscaled by CG — the look the user originally meant by "plasma"). The old Battery-style is preserved as a separate `.polygons` case. Two new variants added: **Lightning** (jagged glowing bolts triggered by transients/bass kicks, ~0.7s lifespan, subtle screen-flicker tint) and **Mandala** (8–16 fold kaleidoscopic petals rotating with bass).
- **Particles fixed** — was nearly invisible because emission only fired on rare hi-hat-style transients. Now emits proportional to overall audio energy plus burst on bass kicks AND high-freq transients, longer particle lifespan (~2s), guaranteed baseline trickle so the visualizer is never blank on quiet input.

### Performance / smoothness pass
- **AudioEngine on the realtime audio thread**: `bandLevel(low:high:)` was allocating a temporary Array per band per audio buffer (7 mallocs × ~43 buffers/sec on the audio thread — recipe for priority-inversion glitches). Replaced with pointer-offset `vDSP_meanv`, zero allocations.
- **Magnitude computation** in `processBuffer` switched from a Swift `for i in 0..<halfFFT` loop with `sqrtf` to `vDSP_zvabs` — ~5–8× faster.
- **Visualizer envelope follower** is now asymmetric (40 ms attack, 220 ms release) and dt-based so the perceived envelope shape is identical regardless of frame rate. The previous symmetric `α = 0.4` IIR snapped both ways and felt jittery on bass hits.
- **Visualizer display link** runs at 60Hz (was 30Hz) — every variant has plenty of CPU headroom and doubling the rate halves visible jitter on motion. ProMotion (120Hz) iPads can run higher; range is 30–120 with preferred 60.
- **Per-bar attack/release smoothing** for the FFT Bars style — bars now read as stable musical levels that bounce on hits instead of flickering on per-bin FFT noise.
- **Log-spaced bin mapping** for FFT Bars — bass/low-mids get more horizontal real estate (where most musical content lives) instead of being crammed into 1–2 bars at the left edge.
- All time-decay constants in the visualizer (`transientPulse`, particle lifespan, lightning bolt life, smoothing alphas) are now frame-rate-independent — computed from real `dt` per tick. Previously hardcoded around `1/30` so changing the display link rate would have broken the timing.

### Added — WMP-aesthetic deep dive
- **WMP: Plenoptic** (replaces simple plasma flow) — two-layer plasma (broad slow color base + faster detail layer), three wandering radial lens flares with additive blending, bass-driven brightness pulse. The "psychedelic depth" feel the original Plenoptic had over a flat plasma.
- **WMP: Classic Bars** — Winamp/WMP-style 48-column spectrum: log-spaced FFT bins, full-saturation rainbow palette across the bars, peak-hold caps that snap up on rise and fall slowly, and a subtle floor reflection. Per-bar asymmetric envelope so individual bars don't flicker.
- **WMP: Alchemy** — flowing translucent ribbons (4–10 of them) with `.plusLighter` additive blending so overlaps brighten to white, Lissajous-style parametric paths, motion-trail decay (each frame dimmed 18% before drawing) for the watercolor / aurora feel.
- **CRT MODE** post-process toggle in the visualizer params section — applies scanlines (every-other-row darken), faint phosphor tint, and a radial vignette to any visualizer for an early-2000s set-top aesthetic. Per-channel via `VisualizerParams.crtMode`.

### Changed — WMP visualizer aesthetic deep dive (round 2)
- **`strokeWithGlow` / `fillCircleWithGlow` helpers** added — every shape-based variant now draws each path 4 times in additive blend mode (wide+faint outer halo → crisp+bright core). This is the single biggest thing that gives Winamp/WMP visualizers their characteristic "neon glow on black" look that flat CG strokes were missing.
- **Polygons / Battery, Spiral, Ribbons, Mandala, Lightning, Tunnel** all now use the bloom helper. Saturation pushed to 0.95+ across the board; brightness near 1.0 on the cores.
- **Pure black backgrounds** on all variants (no more muddy hue-tinted bgs). Bloom needs true black to read as glow.
- **Frame trails** on Ribbons, Lightning, Tunnel, Alchemy — each frame dims the previous content 18–25% before drawing, faking persistence-of-vision motion blur without needing a feedback buffer.
- **Ribbons** rebuilt with quad-curve smoothing between sample points instead of straight line segments — flowing curves instead of jagged polylines.
- **Spiral** ends each arm with a glowing tip orb (the iconic "trailing sparkle").
- **Tunnel** got streaking light particles flying from the center outward — the "warp speed" feel that classic WMP Tunnel had.
- **Lightning** rebuilt with a single neon halo + hot white core (was an outer-glow + crisp-core 2-pass; now a 4-pass bloom + `.plusLighter` core).
- **WMP: Classic Bars** rebuilt: vertical gradient per bar (saturated neon at the bottom fading to brighter near-white at the top — that LED-strip look), gradient floor reflection, peak-hold caps now drawn last with their own additive halo so they glow over the top edge of each bar.
- All visualizers in the Plasma family renamed to the **`WMP: …`** prefix in the picker so they read together as a set.

---

## [0.0.4] — 2026-05-07

Second TestFlight build. Big polish pass on the master section, FX panel layout, and Advanced Output controls — plus 14 new blend modes and Vixid-style per-channel blend.

### Changed
- FX-panel section titles unified — KEYING, PIP / POSITION, and LFO bumped to 11pt monospaced black to match EFFECT, so "Keying" and "LFO" no longer get visually lost next to the much larger Effect heading.
- LFO panel reordered to sit between EFFECT and KEYING (was below PIP). Effect modulation lives next to the effect it drives.
- Keying labels shortened to fit on one line: `Threshold` → `THRESH`, `Softness` → `SOFT`, `Key Hue` → `HUE`. PIP labels likewise shortened: `Scale (Zoom)` → `SCALE`, `X Offset` → `X POS`, `Y Offset` → `Y POS`. All match the all-caps abbreviation style already used in COLOR CORRECTION.
- `CorrectionSlider` label column now `lineLimit(1) + minimumScaleFactor(0.6)` and 8pt wider (36→44pt) — long labels shrink instead of wrapping to two lines.
- Master section sub-labels removed — CROSSFADER, AUTOMATION, TEMPO, GLOBAL COLOR, MASTER, PRESET, OUTPUT tiny gutter labels are gone. Each cell now reads from its own button content. Cleaner, less noise; the only remaining red header is the section MASTER label up top.
- Global Color cell button text changed from "ACTIVE / OFF" to "GLOBAL COLOR" (the active dot already indicates state — the label was redundant and confusing).
- SAVE / LOAD presets cell moved below ADVANCED OUTPUT MAPPING in the master right column — the heavier output button now reads first, presets sit at the bottom.
- Master right column now anchors ADVANCED OUTPUT + SAVE/LOAD to the bottom (lining up with TAP TEMPO on the left), with a flexible `Spacer(minLength: 28)` between FADE/RECALL and ADVANCED OUTPUT — guarantees breathing room so a sloppy tap can't catch the wrong button.
- Blend mode picker is alphabetical now (categorical sections — Standard / Contrast / Comparative / Special / Logic — replaced with a single flat list sorted A–Z by display name). Reordering done at the enum level so any future picker that iterates `allCases` inherits the order automatically.
- Blend mode cell ~2pt wider — `BLD` gutter label trimmed 22→20pt and cell horizontal padding 4→3pt give the picker button more tap area.

### Added
- 14 new blend modes: **Linear Burn**, **Linear Light**, **Vivid Light**, **Pin Light**, **Hard Mix**, **Divide**, **Phoenix**, **Reflect**, **Glow**, **Stamp**, **Hue**, **Saturation**, **Color**, **Luminosity**. Total of 33 modes now. Every mode has a matching `blend_<rawValue>` fragment shader in `BlendModes.metal`; the four HSL modes (Hue / Sat / Color / Luminosity) use Photoshop's `setLum`/`setSat`/`clipColor` algorithm with Rec.601 luma. Vivid Light is a per-channel select between Color Dodge (when layer > 0.5) and Color Burn (when layer ≤ 0.5). Pin Light uses `select(min(b, 2l), max(b, 2l-1), l > 0.5)`. Hard Mix is `step(1 - b, l)` for hard posterize. Phoenix is Resolume's `min(b,l) - max(b,l) + 1`.

### Changed
- Compositor now respects **every channel's blend mode**, including channel 1 (Vixid / Resolume convention). Previously CH1 was hardcoded to paint over with `passthroughOpacityPipeline`, so its blend mode setting was ignored. The compositor now starts with a cleared (black) program texture and composites all 4 channels through `blend_<mode>` in order. Identity-on-black modes (Normal / Add / Screen / Difference / Lighten / etc.) look the same on CH1 as before; non-identity modes (Multiply / HSL / Hard Mix) on CH1 now resolve against black, matching pro-mixer behavior.

### Fixed
- `CompositorPipeline.blendNormal` falls back to the `.normal` pipeline (and prints a one-time console warning) if a requested blend mode's pipeline isn't registered, instead of silently dropping the channel from the composite. Makes future "I picked X and nothing happened" reports self-diagnose.

### Added
- **SNAP** (pin) toggle in Advanced Output — slice translate and corner-resize edges latch to the output box (canvas) edges within ~2.5% of the canvas. Off by default; persists per-session via `OutputConfig.snapToCanvas`. Plays nicely with LOCK aspect (snap runs first, then aspect lock re-derives the orthogonal side). Button sits in the right-side cluster next to the zoom controls.
- Zoom +/- buttons changed from `minus.magnifyingglass`/`plus.magnifyingglass` to plain `minus`/`plus` glyphs at matching weight/size — the magnifier-variant strokes were noticeably mismatched between + and -. SNAP, −, %, + are all 32×26 now (down from 48×36) so the cluster is compact and unified in size.
- SCREEN tabs and DESTINATION buttons in the Advanced Output right panel bumped — section header 9→11pt, screen tab text 8→11pt with bigger vertical padding, destination icons 14→18pt and labels 9→11pt with deeper padding. Was getting visually lost.

---

## [0.0.3] — 2026-05-06

Polish pass on top of the first TestFlight build: external-display fullscreen, master-section RECALL/FADE pair, audio-react default-on, and a pile of UI/touch-target tightening.

### Added
- `ExternalDisplayController` — when the user picks a non-main display in Advanced Output, the program output is rendered fullscreen on that display via a dedicated `UIWindow` on the external `UIScreen`. No mouse needed, no manual fullscreen gesture; auto-attaches when an HDMI/USB-C display connects mid-session and tears down on unplug.
- `.oneLine()` view modifier (in `BlendModePickerView.swift`) — convenience for `lineLimit(1) + minimumScaleFactor` to keep text on one line throughout the liquid UI without re-typing the modifier chain everywhere.
- "RECALL" button in the master section next to FADE TO BLACK — captures channel fader levels at fade time and transitions them back when pressed. Disabled until a fade has actually happened.
- FADE TO BLACK button now uses the same enabled/disabled visual pair as RECALL: greyed out and non-tappable when every channel is already at 0 (nothing to fade from), bright red when at least one channel has output.

### Changed
- "OPEN" button in the destination picker now routes to the external display via the new controller when one's connected; falls back to the existing in-window `liveOutput` `WindowGroup` when no external display is attached.
- Display picker rows, destination picker, and slice list rows in Advanced Output all bumped to bigger touch targets (rows ~9pt vertical padding, 12pt fonts, 14–16pt icons, larger status dots).
- Selected PVW channel reads at a glance — top color bar fattens 2→5pt with a colored glow, header gets a tinted background + colored border, and the "PVW" label is a filled red pill.
- Audio React EQ band gains default to all-7-full (`[1, 1, 1, 1, 1, 1, 1]`) so toggling reactivity on immediately produces visible motion instead of looking broken.
- Audio React preset buttons (KICK / BASS / VOCAL / HATS / FULL / OFF) substantially bigger — 12pt label, 64pt min-width, 10pt vertical padding; wrapped to two rows so they have proper breathing room.
- Removed the red border around the master section on the main mixer; the red top bar above MASTER stays as the section indicator.
- Slice list rows in Advanced Output force-fit their labels to one line: slice name, source chip ("PROGRAM" / "CH 1" / etc.), MESH grid label, and size percentage all use `lineLimit(1)` + `minimumScaleFactor` so they shrink instead of wrapping when the panel is narrow.

### Removed
- "OPEN" and "REFRESH" buttons in the display destination panel — tapping a display row already toggles activation, and `UIScreen.didConnectNotification` auto-refreshes the list.

### Fixed
- Luma key / chroma key changing the threshold/softness/hue had no visible effect when applied to the base channel or with PIP active. `fragment_passthrough_opacity` and `fragment_pip` now multiply by `color.a`, so the alpha computed by `key_luma` / `key_chroma` actually drives transparency through the rest of the compositor.
- Deselecting a Main Display destination in Advanced Output now also closes the `liveOutput` window. Previously the window stayed open after the toggle was flipped off.
- Tapping "ADVANCED OUTPUT MAPPING" within ~2 seconds of cold launch made the window flash open and immediately grey out — the AppDelegate's secondary-scene destruction gate (originally added to suppress state-restored aux scenes when the engine was still lazy) was killing the user-initiated scene too. Gate now only fires for scenes with a `stateRestorationActivity`, so user-tapped opens go through cleanly on first try.

---

## [0.0.2] — 2026-05-06

First TestFlight-ready build. Native iPadOS support, NDI broadcast, multi-camera capture, App Store / TestFlight prep.

### Added
- Native iPadOS 17+ support — was Mac-only in v0.0.1.
- `CameraHub` singleton wrapping `AVCaptureMultiCamSession` for concurrent front + back camera capture on supported iPads, with a single-cam fallback path on older models and a UI hint in the source picker.
- NDI broadcast on iPad — links `libndi_advanced_ios.a` from the Advanced SDK; 640×480 @ 30 fps async send on a dedicated dispatch queue with a 3-buffer ring.
- Master LFO with target picker (master level vs. crossfader) and BPM sync, prominent inline placement in the master section between crossfader and tap tempo.
- Per-slice source picker in Advanced Output — each slice can pull from Program or any individual channel.
- Canvas zoom + pinch in Advanced Output (0.5×–4×) with reset, plus mode-bar +/− buttons.
- Aspect-locked transform corner drags — locks slice to the source's pixel aspect so the video fills slice edges.
- Mesh warp `unsubdivide()` (− button) alongside the existing subdivide (+).
- Rotation effect (`.rotate`) added to the FX picker.
- Logic / math blend modes: `AND`, `OR`, `Negation`.
- About sheet with required NDI® attribution; reachable from the WASTEMIX title in the top bar.
- Privacy manifest (`PrivacyInfo.xcprivacy`) covering NDI-relevant Required Reason APIs.
- Camera-permission-denied banner in the source picker with a deep-link to Settings.
- Settings persistence to UserDefaults — BPM, crossfader position + groups, master LFO target, selected preview channel — with range validation on load.
- App Store Connect listing under bundle ID `com.wastemix.app`.

### Changed
- Render loop is `CADisplayLink`-driven inside `RenderEngine` writing to a stable 1920×1080 program texture; all `MTKView`s are passive presenters.
- Front camera auto-flips 180° at the `AVCaptureConnection` level (TrueDepth sensor was upside-down in iPad landscape).
- Advanced Output content scaled smaller by default (`panelScale` ceiling 1.0, right panel 30 % width) so the canvas reads at appropriate size on iPad.
- Advanced Output canvas defaults to 80 % of available area at 100 % zoom for breathing room.
- Slices added via "+ ADD" cascade with 50 % size + offset so newly-added slices don't fully overlap.
- Canvas tap-to-select picks the smallest slice containing the tap (via simultaneous `SpatialTapGesture`), enabling selection of slices that overlap.
- `OutputRenderer` always renders to screen textures; `enabled` flag now only gates whether output is actually sent to NDI / external display, so the Advanced Output canvas preview is always live.
- LFO target picker replaced with a flat button grid (SwiftUI Menu picker was broken inside nested panels).
- `Effect` selection auto-applies each effect's `defaultIntensity` and `defaultParam2`.
- "Freeze" effect now actually freezes (was decorative); standalone freeze toggle removed in favor of selecting `.freeze` from the FX dropdown.
- Advanced Output Mapping CTA on the main mixer is now a prominent two-line button at the bottom of the right column, dimmed when closed and brightened when the window is on screen.

### Fixed
- `NDIWrapper._ndi_frame[128]` heap-buffer truncation — bumped to 512 bytes with a runtime guard so newer SDK structs don't corrupt memory on `Free`.
- `NDIWrapper` `memset`s added for `find_create_t`, `send_create_t`, and `video_frame_v2_t` so unset fields don't read garbage stack memory.
- `AVCaptureSessionInterruptionEnded` observer added — cameras now resume after phone calls / Control Center grabs / Stage Manager focus changes.
- Audio session `setCategory(.playAndRecord, …)` is configured exactly once per process — was previously firing on every AUDIO button tap and taking the active camera down via audio-session interruption.
- `AudioEngine.processBuffer` no longer allocates on the real-time audio thread (pre-allocated FFT scratch buffers).
- `MediaPlayerSource` notification observer leak fixed — switched to KVO with proper invalidation in `deinit`.
- `OutputDisplayView` shares the engine's `MetalContext.commandQueue` (was using a separate queue, causing tearing on the live external display).
- `OutputRenderer.ensureScreenTexture` clamps screen W/H to `[64, 4096]` and falls back to a 64×64 texture if allocation fails — no more force-unwrap crashes on garbage user input.
- `MetalContext` shader force-unwraps replaced with descriptive `fatalError`s pointing to the missing shader name.
- `MeshWarp.subdivide()` mesh node `ForEach` now iterates by stable `WarpNode.id` (UUID) instead of `\.self` index, preventing gesture state from sticking to stale node positions.
- NDI ring-buffer race that produced banding/tearing on the broadcast (frame N's send was reading bytes that frame N+1 had already overwritten).
- NDI dropouts — switched to `NDIlib_send_send_video_async_v2` with `clock_video=false` and dedicated send queue so compress + network work doesn't block the Metal completion thread.
- Drag anchor jump — slice transform drag captures the start position on first `onChanged` rather than guessing from translation magnitude.
- PreviewView in the canvas is now sized + positioned to match the slice coordinate space (`canvasW × canvasH`), so dragging a slice no longer creates a "perspective" mismatch between the slice border and the rendered image.
- Camera-switching on non-multi-cam iPads (single-camera AVCaptureSession path now fully detaches old inputs when consumers drop to zero, allowing the new camera to attach).
- `RenderEngine` is constructed eagerly at app init so a state-restored Advanced Output scene without the mixer no longer shows a black screen.

### Removed
- Mac `libndi.dylib` from the iOS archive — was triggering an App Store rejection risk + dSYM validation warning. The "Embed NDI Library" Run Script now gates on `PLATFORM_NAME == macosx` or `IS_MACCATALYST == YES`.
- Standalone freeze toggle UI (subsumed by the `.freeze` effect).
- Source rect (X/Y/W/H) numeric fields under the slice INPUT section in Advanced Output.

---

## [0.0.1] — 2026-04-04

Initial public commit. Mac Catalyst + Windows DirectX builds.

### Added
- 4 independent video channels with vertical faders.
- 16 blend modes, A/B crossfader, cut/mix/dip/wipe transitions.
- 16+ GPU effects (mirror, mosaic, strobe, RGB split, blur, datamosh, scanlines, kaleidoscope, halftone, feedback, etc.).
- Per-channel freeze, luma key, chroma key.
- LFO with sine/triangle/square/sawtooth/random shapes, BPM sync.
- Audio reactivity with 7-band EQ.
- Camera, NDI receive, video file, image, solid color, and test pattern sources.
- NDI send (Mac), external display HDMI/USB-C output, advanced output with projection mapping (mesh warp, corner-pin, soft-edge blending).
- Mac Catalyst app shipped as `WasteMix.app`.
- Windows DirectX 12 / C++ port skeleton (`WasteMixWindows/`).

[Unreleased]: https://github.com/VIDEOWASTE/WasteMix/compare/v0.0.5...HEAD
[0.0.5]: https://github.com/VIDEOWASTE/WasteMix/compare/v0.0.4...v0.0.5
[0.0.4]: https://github.com/VIDEOWASTE/WasteMix/compare/v0.0.3...v0.0.4
[0.0.3]: https://github.com/VIDEOWASTE/WasteMix/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/VIDEOWASTE/WasteMix/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/VIDEOWASTE/WasteMix/releases/tag/v0.0.1
