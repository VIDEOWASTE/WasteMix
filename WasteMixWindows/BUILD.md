# WasteMix — Windows Build Instructions

## Requirements

- Windows 10/11 with DirectX 12 capable GPU
- Visual Studio 2022 (Community or higher)
- Windows SDK 10.0.19041.0 or later
- CMake 3.20+

## Dependencies

### Dear ImGui (UI framework)
Download and extract to `libs/imgui/`:
```
git clone https://github.com/ocornut/imgui.git libs/imgui
```

### NDI SDK (optional, for network video)
Download from https://ndi.video/tools/ndi-sdk/ and place in `libs/ndi/`

## Build

```bash
mkdir build
cd build
cmake .. -G "Visual Studio 17 2022" -A x64
cmake --build . --config Release
```

Or open the generated `.sln` in Visual Studio and build.

## Architecture

The Windows port mirrors the iPad/Mac version 1:1:

| iPad (Metal/SwiftUI) | Windows (DX12/ImGui) |
|---|---|
| Metal shaders (.metal) | HLSL shaders (.hlsl) |
| MetalContext.swift | dx12_context.cpp |
| RenderEngine.swift | render_engine.cpp |
| CompositorPipeline.swift | compositor.cpp |
| CameraSource.swift (AVFoundation) | camera_source.cpp (Media Foundation) |
| AudioEngine.swift (AVAudioEngine) | audio_engine.cpp (WASAPI) |
| SwiftUI views | ImGui (mixer_ui.cpp) |

All shaders are direct HLSL translations of the Metal Shading Language originals.
Same blend modes, effects, transitions, wipes, keying, and color correction.

## File Structure

```
WasteMixWindows/
├── CMakeLists.txt
├── BUILD.md
├── src/
│   ├── main.cpp                    # Win32 entry point
│   ├── rendering/
│   │   ├── dx12_context.h/cpp      # DX12 device, swap chain, pipelines
│   │   ├── render_engine.h/cpp     # Frame loop, state, transitions, LFOs
│   │   └── compositor.h/cpp        # 4-channel GPU composition
│   ├── input/
│   │   ├── camera_source.h/cpp     # Webcam via Media Foundation
│   │   ├── media_source.h/cpp      # Video file playback
│   │   └── audio_engine.h/cpp      # Mic input + FFT via WASAPI
│   ├── ui/
│   │   └── mixer_ui.h/cpp          # ImGui interface
│   └── shaders/
│       ├── common.hlsli            # Shared types + vertex shader
│       ├── passthrough.hlsl        # Passthrough, opacity, PIP
│       ├── blend_modes.hlsl        # 16 blend modes
│       ├── effects.hlsl            # 16 effects
│       ├── transitions.hlsl        # Wipes, dip, star wipe
│       └── color_correction.hlsl   # BCS + RGB + hue shift
└── libs/
    └── imgui/                      # Dear ImGui (download separately)
```
