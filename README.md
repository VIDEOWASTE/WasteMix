# WasteMix

Real-time 4-channel video mixer with NDI I/O, projection mapping, and live effects. Built for VJ performance.

## Features

### Mixer
- 4 independent video channels with vertical faders
- 16 blend modes (Normal, Add, Multiply, Screen, Overlay, Difference, etc.)
- Multi-select A/B crossfader with transition controls
- Cut, Mix, Dip, and 8 directional wipe transitions
- Preview (PVW) and Program (PGM) monitors
- Tap tempo with BPM sync

### Effects
- 16+ real-time GPU effects: Mirror, Invert, Mosaic, Strobe, RGB Split, Posterize, Blur, Solarize, Edges, Datamosh, Scanlines, Kaleidoscope, Halftone, Feedback
- Per-channel freeze frame
- Luma key and chroma key
- Picture-in-Picture (PIP) with scale/position
- Per-channel and global color correction (brightness, contrast, saturation, hue, RGB gain, lift)

### Modulation
- LFO with sine, triangle, square, sawtooth, random waveforms
- BPM-synced modulation
- Audio reactivity with 7-band EQ (Sub Bass through Brilliance)
- Quick presets: Kick, Bass, Vocal, Hats, Full

### Input Sources
- Camera (front/back)
- NDI network sources (auto-discovery)
- Video files (MP4, MOV, M4V)
- Images (JPG, PNG, HEIF)
- Solid colors
- Test patterns (Color Bars, Gradient, Checkerboard)

### Output
- NDI output (global program feed + per-screen sends)
- External display output via HDMI/USB-C with fullscreen support
- Advanced Output with Resolume-style projection mapping:
  - Multi-screen, multi-slice output
  - Per-slice mesh warp with draggable grid nodes
  - Corner-pin perspective warping
  - Soft edge blending for multi-projector setups
  - Free transform (move, resize, rotate)
  - 1920x1080 render resolution

### Presets
- Save and load full mixer state
- Per-channel settings preserved

## Build

### macOS (Mac Catalyst)

Requires Xcode 15+ and macOS 17+.

```bash
cd QuadMix
xcodebuild -project QuadMix.xcodeproj \
  -scheme QuadMix \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath build \
  build
open build/Build/Products/Debug-maccatalyst/WasteMix.app
```

### NDI Support

1. Download the [NDI SDK](https://ndi.video/tools/ndi-sdk/)
2. Copy `libndi.dylib` to `QuadMix/QuadMix/NDI/`
3. Copy `Processing.NDI.Lib.h` to `QuadMix/QuadMix/NDI/`
4. Build with `ENABLE_NDI=1` (already set in build settings)

### Windows (DirectX)

See `WasteMixWindows/` for the DirectX/C++ build. Requires Visual Studio 2022 with C++ desktop development workload.

## Architecture

- **Metal** rendering pipeline with compute shaders for all effects
- **CVMetalTextureCache** for zero-copy camera/video frame conversion
- **Triple-buffered** render loop at 60fps
- **CVPixelBufferPool** for NDI receive (no per-frame allocation)
- **SwiftUI** interface with Mac Catalyst support
- Liquid UI scaling — adapts to any window size

## License

All rights reserved.
