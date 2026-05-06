# Changelog

All notable changes to **WasteMix** are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/).

> **Working convention** — every change made to `main` should add a line under `[Unreleased]` in the appropriate subsection (`Added`, `Changed`, `Fixed`, `Removed`, `Security`). When cutting a release, the `[Unreleased]` block is renamed to the new version + date and a fresh empty `[Unreleased]` is added at the top.

## [Unreleased]

### Added
-

### Changed
-

### Fixed
-

### Removed
-

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

[Unreleased]: https://github.com/VIDEOWASTE/WasteMix/compare/v0.0.2...HEAD
[0.0.2]: https://github.com/VIDEOWASTE/WasteMix/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/VIDEOWASTE/WasteMix/releases/tag/v0.0.1
