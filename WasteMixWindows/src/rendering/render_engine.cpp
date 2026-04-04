#include "render_engine.h"
#include <cmath>

bool RenderEngine::Initialize(HWND hwnd, UINT width, UINT height) {
    if (!m_ctx.Initialize(hwnd, width, height)) return false;
    m_startTime = std::chrono::high_resolution_clock::now();
    InitPipelines();
    m_compositor.Initialize(&m_ctx);
    return true;
}

void RenderEngine::InitPipelines() {
    // Create all shader pipelines
    m_ctx.CreatePipeline("passthrough", L"shaders/passthrough.hlsl", "PSPassthrough");
    m_ctx.CreatePipeline("passthrough_opacity", L"shaders/passthrough.hlsl", "PSPassthroughOpacity");
    m_ctx.CreatePipeline("pip", L"shaders/passthrough.hlsl", "PSPIP");
    m_ctx.CreatePipeline("color_correction", L"shaders/color_correction.hlsl", "PSColorCorrection");
    m_ctx.CreatePipeline("wipe_ab", L"shaders/transitions.hlsl", "PSWipeAB", 2);
    m_ctx.CreatePipeline("wipe_single", L"shaders/transitions.hlsl", "PSWipeSingle");
    m_ctx.CreatePipeline("dip", L"shaders/transitions.hlsl", "PSDip");

    // Blend modes
    const char* blendNames[] = {
        "PSBlendNormal","PSBlendAdd","PSBlendMultiply","PSBlendScreen","PSBlendOverlay",
        "PSBlendHardLight","PSBlendSoftLight","PSBlendColorDodge","PSBlendColorBurn",
        "PSBlendDifference","PSBlendExclusion","PSBlendDarken","PSBlendLighten",
        "PSBlendSubtract","PSBlendAverage","PSBlendXOR"
    };
    for (int i = 0; i < (int)BlendMode::COUNT; i++) {
        std::string name = std::string("blend_") + std::to_string(i);
        m_ctx.CreatePipeline(name, L"shaders/blend_modes.hlsl", blendNames[i], 2);
    }

    // Effects
    const char* fxNames[] = {
        "","","PSMirrorH","PSMirrorV","PSInvert","PSMosaic","PSStrobe",
        "PSRGBSplit","PSPosterize","PSBlur","PSSolarize","PSEdges",
        "PSDatamosh","PSScanlines","PSKaleidoscope","PSHalftone"
    };
    for (int i = 2; i < (int)EffectType::COUNT; i++) {
        std::string name = std::string("fx_") + std::to_string(i);
        m_ctx.CreatePipeline(name, L"shaders/effects.hlsl", fxNames[i]);
    }
}

void RenderEngine::RenderFrame() {
    auto now = std::chrono::high_resolution_clock::now();
    float currentTime = std::chrono::duration<float>(now - m_startTime).count();
    float dt = currentTime - m_lastFrameTime;
    m_lastFrameTime = currentTime;

    UpdateTransitions(dt);
    UpdateLFOs(currentTime);

    m_ctx.BeginFrame();
    // Compositor renders all channels to the back buffer
    m_compositor.Composite(m_state, m_ctx.GetCommandList(), currentTime);
    m_ctx.EndFrame();
    m_ctx.Present();
}

void RenderEngine::UpdateTransitions(float dt) {
    for (auto& ch : m_state.channels) {
        if (!ch.isTransitioning) continue;
        ch.transitionProgress += dt / ch.transitionDuration;
        if (ch.transitionProgress >= 1.0f) {
            ch.transitionProgress = 0;
            ch.isTransitioning = false;
        }
    }
}

void RenderEngine::UpdateLFOs(float time) {
    for (auto& ch : m_state.channels) {
        if (!ch.lfo.enabled || ch.lfo.target == 0) continue;

        double freq = ch.lfo.useBPM ? (m_state.bpm / 60.0) * ch.lfo.bpmDivision : ch.lfo.rate;
        float phase = (float)fmod((double)time * freq, 1.0);
        float raw;

        switch (ch.lfo.shape) {
            case 0: raw = (sinf(phase * 6.28318f) + 1.0f) * 0.5f; break; // sine
            case 1: raw = phase < 0.5f ? phase * 2.0f : 2.0f - phase * 2.0f; break; // tri
            case 2: raw = phase < 0.5f ? 1.0f : 0.0f; break; // square
            case 3: raw = phase; break; // saw
            default: raw = fmodf(sinf(floorf((float)(time * freq)) * 12.9898f) * 43758.5453f, 1.0f); break;
        }

        raw = 0.5f + (raw - 0.5f) * ch.lfo.depth;
        ch.lfo.currentValue = ch.lfo.minVal + raw * (ch.lfo.maxVal - ch.lfo.minVal);

        switch (ch.lfo.target) {
            case 1: if (!ch.isTransitioning) ch.faderLevel = ch.lfo.currentValue; break;
            case 2: ch.effectIntensity = ch.lfo.currentValue; break;
            case 3: ch.effectParam2 = ch.lfo.currentValue; break;
            case 4: ch.pipScale = 0.1f + ch.lfo.currentValue * 4.9f; break;
            case 5: ch.pipOffsetX = ch.lfo.currentValue * 2.0f - 1.0f; break;
            case 6: ch.pipOffsetY = ch.lfo.currentValue * 2.0f - 1.0f; break;
        }
    }
}

void RenderEngine::Shutdown() {
    m_ctx.Shutdown();
}

void RenderEngine::Resize(UINT width, UINT height) {
    m_ctx.Resize(width, height);
}
