# Changelog

All notable changes to **WasteMix** are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/).

> **Working convention** — every change made to `main` should add a line under `[Unreleased]` in the appropriate subsection (`Added`, `Changed`, `Fixed`, `Removed`, `Security`). When cutting a release, the `[Unreleased]` block is renamed to the new version + date and a fresh empty `[Unreleased]` is added at the top.

## [Unreleased]

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

[Unreleased]: https://github.com/VIDEOWASTE/WasteMix/compare/v0.0.4...HEAD
[0.0.4]: https://github.com/VIDEOWASTE/WasteMix/compare/v0.0.3...v0.0.4
[0.0.3]: https://github.com/VIDEOWASTE/WasteMix/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/VIDEOWASTE/WasteMix/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/VIDEOWASTE/WasteMix/releases/tag/v0.0.1
