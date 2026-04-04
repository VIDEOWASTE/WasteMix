// WasteMix — Common HLSL types and vertex shader

struct VSInput {
    float2 position : POSITION;
    float2 texCoord : TEXCOORD;
};

struct PSInput {
    float4 position : SV_POSITION;
    float2 texCoord : TEXCOORD;
};

// Shared uniform structures
cbuffer BlendUniforms : register(b0) {
    float opacity;
    float3 _pad0;
};

cbuffer ColorCorrectionUniforms : register(b0) {
    float brightness;
    float contrast;
    float saturation;
    float hueShift;
    float redGain;
    float greenGain;
    float blueGain;
    float _pad1;
};

cbuffer TransitionUniforms : register(b0) {
    float progress;
    int direction;
    float2 _pad2;
};

cbuffer EffectParams : register(b0) {
    float param1;
    float param2;
    float time;
    float _pad3;
};

cbuffer PIPUniforms : register(b0) {
    float pipScale;
    float pipOffsetX;
    float pipOffsetY;
    float pipOpacity;
};

SamplerState linearSampler : register(s0);

// Vertex shader — fullscreen quad
PSInput VSMain(VSInput input) {
    PSInput output;
    output.position = float4(input.position, 0.0, 1.0);
    output.texCoord = input.texCoord;
    return output;
}
