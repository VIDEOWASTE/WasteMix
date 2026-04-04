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
};

#endif
