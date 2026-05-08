#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

struct VertexIn {
    simd_float2 position;
    simd_float2 texCoord;
};

struct BlendUniforms {
    float opacity;
    float padding[3];
};

struct ColorCorrectionUniforms {
    float brightness;
    float contrast;
    float saturation;
    float hueShift;
    float redGain;
    float greenGain;
    float blueGain;
    float blackLevel;
    float liftR;
    float liftG;
    float liftB;
    float padding;
};

struct TransitionUniforms {
    float progress;
    int direction; // 0=left, 1=right, 2=up, 3=down
    float padding[2];
};

struct PIPUniforms {
    float scale;
    float offsetX;
    float offsetY;
    float opacity;
    float rotationRadians;
    float targetAspect;
    float padding0;
    float padding1;
};

// Per-channel source-framing transform. Sized so the source's apparent
// rectangle fits or fills the target canvas after rotation.
struct TransformUniforms {
    float rotationRadians;  // 0, π/2, π, 3π/2 — set by ChannelRotation
    float sourceAspect;     // source.w / source.h
    float targetAspect;     // target.w / target.h
    int fillMode;           // 0 = fit (letterbox), 1 = fill (crop edges)
};

#endif
