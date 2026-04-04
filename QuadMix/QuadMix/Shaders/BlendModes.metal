#include <metal_stdlib>
using namespace metal;

#include "ShaderTypes.h"

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Helper: mix blend result with base using opacity
inline float3 applyOpacity(float3 base, float3 blended, float opacity) {
    return mix(base, blended, opacity);
}

// MARK: - Normal
fragment float4 blend_normal(VertexOut in [[stage_in]],
                              texture2d<float> base [[texture(0)]],
                              texture2d<float> layer [[texture(1)]],
                              constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    float3 result = applyOpacity(b.rgb, l.rgb, uniforms.opacity * l.a);
    return float4(result, 1.0);
}

// MARK: - Add
fragment float4 blend_add(VertexOut in [[stage_in]],
                           texture2d<float> base [[texture(0)]],
                           texture2d<float> layer [[texture(1)]],
                           constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    float3 blended = min(b.rgb + l.rgb, float3(1.0));
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity);
    return float4(result, 1.0);
}

// MARK: - Multiply
fragment float4 blend_multiply(VertexOut in [[stage_in]],
                                texture2d<float> base [[texture(0)]],
                                texture2d<float> layer [[texture(1)]],
                                constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    float3 blended = b.rgb * l.rgb;
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity);
    return float4(result, 1.0);
}

// MARK: - Screen
fragment float4 blend_screen(VertexOut in [[stage_in]],
                              texture2d<float> base [[texture(0)]],
                              texture2d<float> layer [[texture(1)]],
                              constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    float3 blended = 1.0 - (1.0 - b.rgb) * (1.0 - l.rgb);
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity);
    return float4(result, 1.0);
}

// MARK: - Overlay
fragment float4 blend_overlay(VertexOut in [[stage_in]],
                               texture2d<float> base [[texture(0)]],
                               texture2d<float> layer [[texture(1)]],
                               constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    float3 blended;
    blended.r = b.r < 0.5 ? 2.0 * b.r * l.r : 1.0 - 2.0 * (1.0 - b.r) * (1.0 - l.r);
    blended.g = b.g < 0.5 ? 2.0 * b.g * l.g : 1.0 - 2.0 * (1.0 - b.g) * (1.0 - l.g);
    blended.b = b.b < 0.5 ? 2.0 * b.b * l.b : 1.0 - 2.0 * (1.0 - b.b) * (1.0 - l.b);
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity);
    return float4(result, 1.0);
}

// MARK: - Difference
fragment float4 blend_difference(VertexOut in [[stage_in]],
                                  texture2d<float> base [[texture(0)]],
                                  texture2d<float> layer [[texture(1)]],
                                  constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    float3 blended = abs(b.rgb - l.rgb);
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity);
    return float4(result, 1.0);
}

// MARK: - Exclusion
fragment float4 blend_exclusion(VertexOut in [[stage_in]],
                                 texture2d<float> base [[texture(0)]],
                                 texture2d<float> layer [[texture(1)]],
                                 constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    float3 blended = b.rgb + l.rgb - 2.0 * b.rgb * l.rgb;
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity);
    return float4(result, 1.0);
}

// MARK: - Hard Light
fragment float4 blend_hardLight(VertexOut in [[stage_in]],
                                 texture2d<float> base [[texture(0)]],
                                 texture2d<float> layer [[texture(1)]],
                                 constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    float3 blended;
    blended.r = l.r < 0.5 ? 2.0 * b.r * l.r : 1.0 - 2.0 * (1.0 - b.r) * (1.0 - l.r);
    blended.g = l.g < 0.5 ? 2.0 * b.g * l.g : 1.0 - 2.0 * (1.0 - b.g) * (1.0 - l.g);
    blended.b = l.b < 0.5 ? 2.0 * b.b * l.b : 1.0 - 2.0 * (1.0 - b.b) * (1.0 - l.b);
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity);
    return float4(result, 1.0);
}

// MARK: - Soft Light (Pegtop formula)
fragment float4 blend_softLight(VertexOut in [[stage_in]],
                                 texture2d<float> base [[texture(0)]],
                                 texture2d<float> layer [[texture(1)]],
                                 constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    float3 blended = (1.0 - 2.0 * l.rgb) * b.rgb * b.rgb + 2.0 * l.rgb * b.rgb;
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity);
    return float4(result, 1.0);
}

// MARK: - Color Dodge
fragment float4 blend_colorDodge(VertexOut in [[stage_in]],
                                  texture2d<float> base [[texture(0)]],
                                  texture2d<float> layer [[texture(1)]],
                                  constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    float3 blended;
    blended.r = l.r >= 1.0 ? 1.0 : min(1.0, b.r / (1.0 - l.r));
    blended.g = l.g >= 1.0 ? 1.0 : min(1.0, b.g / (1.0 - l.g));
    blended.b = l.b >= 1.0 ? 1.0 : min(1.0, b.b / (1.0 - l.b));
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity);
    return float4(result, 1.0);
}

// MARK: - Color Burn
fragment float4 blend_colorBurn(VertexOut in [[stage_in]],
                                 texture2d<float> base [[texture(0)]],
                                 texture2d<float> layer [[texture(1)]],
                                 constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    float3 blended;
    blended.r = l.r <= 0.0 ? 0.0 : max(0.0, 1.0 - (1.0 - b.r) / l.r);
    blended.g = l.g <= 0.0 ? 0.0 : max(0.0, 1.0 - (1.0 - b.g) / l.g);
    blended.b = l.b <= 0.0 ? 0.0 : max(0.0, 1.0 - (1.0 - b.b) / l.b);
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity);
    return float4(result, 1.0);
}

// MARK: - Darken
fragment float4 blend_darken(VertexOut in [[stage_in]],
                              texture2d<float> base [[texture(0)]],
                              texture2d<float> layer [[texture(1)]],
                              constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    float3 blended = min(b.rgb, l.rgb);
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity);
    return float4(result, 1.0);
}

// MARK: - Lighten
fragment float4 blend_lighten(VertexOut in [[stage_in]],
                               texture2d<float> base [[texture(0)]],
                               texture2d<float> layer [[texture(1)]],
                               constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    float3 blended = max(b.rgb, l.rgb);
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity);
    return float4(result, 1.0);
}

// MARK: - Subtract
fragment float4 blend_subtract(VertexOut in [[stage_in]],
                                texture2d<float> base [[texture(0)]],
                                texture2d<float> layer [[texture(1)]],
                                constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    float3 blended = max(b.rgb - l.rgb, float3(0.0));
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity);
    return float4(result, 1.0);
}

// MARK: - Average
fragment float4 blend_average(VertexOut in [[stage_in]],
                               texture2d<float> base [[texture(0)]],
                               texture2d<float> layer [[texture(1)]],
                               constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    float3 blended = (b.rgb + l.rgb) * 0.5;
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity);
    return float4(result, 1.0);
}

// MARK: - XOR
fragment float4 blend_xor(VertexOut in [[stage_in]],
                           texture2d<float> base [[texture(0)]],
                           texture2d<float> layer [[texture(1)]],
                           constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    // Simulate XOR on normalized floats
    uint3 bi = uint3(b.rgb * 255.0);
    uint3 li = uint3(l.rgb * 255.0);
    uint3 xi = bi ^ li;
    float3 blended = float3(xi) / 255.0;
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity);
    return float4(result, 1.0);
}
