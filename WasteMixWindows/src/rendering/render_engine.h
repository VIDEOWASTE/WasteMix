#pragma once

#include "dx12_context.h"
#include "compositor.h"
#include <array>
#include <chrono>

enum class BlendMode {
    Normal, Add, Multiply, Screen, Overlay,
    HardLight, SoftLight, ColorDodge, ColorBurn,
    Difference, Exclusion, Darken, Lighten,
    Subtract, Average, XOR,
    COUNT
};

enum class EffectType {
    None, Freeze, MirrorH, MirrorV, Invert,
    Mosaic, Strobe, RGBSplit, Posterize, Blur,
    Solarize, Edges, Datamosh, Scanlines,
    Kaleidoscope, Halftone,
    COUNT
};

enum class TransitionType {
    Mix, Cut, DipToBlack,
    WipeLeft, WipeRight, WipeUp, WipeDown,
    WipeDiagTL, WipeDiagTR, WipeCircle, WipeDiamond,
    WipeBlinds, WipeStar,
    COUNT
};

struct ColorCorrection {
    float brightness = 0, contrast = 1, saturation = 1, hueShift = 0;
    float redGain = 1, greenGain = 1, blueGain = 1;
    bool isIdentity() const {
        return brightness == 0 && contrast == 1 && saturation == 1 &&
               hueShift == 0 && redGain == 1 && greenGain == 1 && blueGain == 1;
    }
};

struct LFOState {
    bool enabled = false;
    int shape = 0; // 0=sine,1=tri,2=square,3=saw,4=random
    int target = 0; // 0=none,1=opacity,2=fxIntensity,3=fxParam2,4=pipScale,5=pipX,6=pipY
    float rate = 0.5f, depth = 0.5f, minVal = 0, maxVal = 1;
    bool useBPM = false;
    float bpmDivision = 1;
    float currentValue = 0.5f;
};

struct Channel {
    float faderLevel = 0;
    BlendMode blendMode = BlendMode::Normal;
    EffectType effectType = EffectType::None;
    float effectIntensity = 0.5f, effectParam2 = 0;
    bool isFrozen = false;
    ColorCorrection colorCorrection;
    TransitionType transitionType = TransitionType::Mix;
    float transitionDuration = 1.0f;
    float transitionProgress = 0;
    bool isTransitioning = false;
    // PIP
    float pipScale = 1, pipOffsetX = 0, pipOffsetY = 0;
    // LFO
    LFOState lfo;
    // Audio react
    bool audioReactEnabled = false;
    int audioReactTarget = 0;
    float audioReactBandGains[7] = {};
    float audioReactSmoothing = 0.3f;
    float audioReactFloor = 0, audioReactCeiling = 1;
    float audioReactValue = 0;
};

struct MixerState {
    std::array<Channel, 4> channels;
    ColorCorrection globalColorCorrection;
    int selectedPreviewChannel = 0;
    float bpm = 120;
    float crossfaderPos = 0.5f;
    int crossfaderA = 0, crossfaderB = 1;
};

class RenderEngine {
public:
    bool Initialize(HWND hwnd, UINT width, UINT height);
    void Shutdown();
    void Resize(UINT width, UINT height);
    void RenderFrame();

    MixerState& GetState() { return m_state; }
    DX12Context& GetContext() { return m_ctx; }

private:
    void InitPipelines();
    void UpdateTransitions(float dt);
    void UpdateLFOs(float time);

    DX12Context m_ctx;
    Compositor m_compositor;
    MixerState m_state;

    std::chrono::high_resolution_clock::time_point m_startTime;
    float m_lastFrameTime = 0;
};
