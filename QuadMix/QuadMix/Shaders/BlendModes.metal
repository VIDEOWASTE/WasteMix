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
    // Multiply by layer alpha so per-channel keying (luma/chroma) actually
    // shows the underlying base where the layer was keyed out — without this,
    // keys only worked on Normal blend.
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
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
    // Multiply by layer alpha so per-channel keying (luma/chroma) actually
    // shows the underlying base where the layer was keyed out — without this,
    // keys only worked on Normal blend.
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
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
    // Multiply by layer alpha so per-channel keying (luma/chroma) actually
    // shows the underlying base where the layer was keyed out — without this,
    // keys only worked on Normal blend.
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
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
    // Multiply by layer alpha so per-channel keying (luma/chroma) actually
    // shows the underlying base where the layer was keyed out — without this,
    // keys only worked on Normal blend.
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
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
    // Multiply by layer alpha so per-channel keying (luma/chroma) actually
    // shows the underlying base where the layer was keyed out — without this,
    // keys only worked on Normal blend.
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
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
    // Multiply by layer alpha so per-channel keying (luma/chroma) actually
    // shows the underlying base where the layer was keyed out — without this,
    // keys only worked on Normal blend.
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
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
    // Multiply by layer alpha so per-channel keying (luma/chroma) actually
    // shows the underlying base where the layer was keyed out — without this,
    // keys only worked on Normal blend.
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
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
    // Multiply by layer alpha so per-channel keying (luma/chroma) actually
    // shows the underlying base where the layer was keyed out — without this,
    // keys only worked on Normal blend.
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
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
    // Multiply by layer alpha so per-channel keying (luma/chroma) actually
    // shows the underlying base where the layer was keyed out — without this,
    // keys only worked on Normal blend.
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
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
    // Multiply by layer alpha so per-channel keying (luma/chroma) actually
    // shows the underlying base where the layer was keyed out — without this,
    // keys only worked on Normal blend.
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
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
    // Multiply by layer alpha so per-channel keying (luma/chroma) actually
    // shows the underlying base where the layer was keyed out — without this,
    // keys only worked on Normal blend.
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
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
    // Multiply by layer alpha so per-channel keying (luma/chroma) actually
    // shows the underlying base where the layer was keyed out — without this,
    // keys only worked on Normal blend.
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
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
    // Multiply by layer alpha so per-channel keying (luma/chroma) actually
    // shows the underlying base where the layer was keyed out — without this,
    // keys only worked on Normal blend.
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
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
    // Multiply by layer alpha so per-channel keying (luma/chroma) actually
    // shows the underlying base where the layer was keyed out — without this,
    // keys only worked on Normal blend.
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
    return float4(result, 1.0);
}

// MARK: - AND (bitwise on 8-bit components, like XOR but ANDed)
fragment float4 blend_and(VertexOut in [[stage_in]],
                           texture2d<float> base [[texture(0)]],
                           texture2d<float> layer [[texture(1)]],
                           constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    uint3 bi = uint3(b.rgb * 255.0);
    uint3 li = uint3(l.rgb * 255.0);
    uint3 ai = bi & li;
    float3 blended = float3(ai) / 255.0;
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
    return float4(result, 1.0);
}

// MARK: - OR (bitwise on 8-bit components)
fragment float4 blend_or(VertexOut in [[stage_in]],
                          texture2d<float> base [[texture(0)]],
                          texture2d<float> layer [[texture(1)]],
                          constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    uint3 bi = uint3(b.rgb * 255.0);
    uint3 li = uint3(l.rgb * 255.0);
    uint3 oi = bi | li;
    float3 blended = float3(oi) / 255.0;
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
    return float4(result, 1.0);
}

// MARK: - Negation (mathematical inverse — bright where colors don't overlap)
fragment float4 blend_negation(VertexOut in [[stage_in]],
                                texture2d<float> base [[texture(0)]],
                                texture2d<float> layer [[texture(1)]],
                                constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    float3 blended = 1.0 - abs(1.0 - b.rgb - l.rgb);
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
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
    // Multiply by layer alpha so per-channel keying (luma/chroma) actually
    // shows the underlying base where the layer was keyed out — without this,
    // keys only worked on Normal blend.
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
    return float4(result, 1.0);
}

// MARK: - Linear Burn (b + l - 1)
fragment float4 blend_linearBurn(VertexOut in [[stage_in]],
                                  texture2d<float> base [[texture(0)]],
                                  texture2d<float> layer [[texture(1)]],
                                  constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    float3 blended = max(b.rgb + l.rgb - 1.0, float3(0.0));
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
    return float4(result, 1.0);
}

// MARK: - Linear Light (b + 2l - 1) — punchy contrast
fragment float4 blend_linearLight(VertexOut in [[stage_in]],
                                   texture2d<float> base [[texture(0)]],
                                   texture2d<float> layer [[texture(1)]],
                                   constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    float3 blended = clamp(b.rgb + 2.0 * l.rgb - 1.0, float3(0.0), float3(1.0));
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
    return float4(result, 1.0);
}

// Per-channel Photoshop "Vivid Light":
//   l > 0.5 → ColorDodge with (2l - 1)
//   l ≤ 0.5 → ColorBurn  with (2l)
inline float vividLightChan(float b, float l) {
    if (l > 0.5) {
        float k = 2.0 * (l - 0.5);
        return k >= 1.0 ? 1.0 : min(1.0, b / max(1.0 - k, 1e-4));
    } else {
        float k = 2.0 * l;
        return k <= 0.0 ? 0.0 : max(0.0, 1.0 - (1.0 - b) / max(k, 1e-4));
    }
}

// MARK: - Vivid Light
fragment float4 blend_vividLight(VertexOut in [[stage_in]],
                                  texture2d<float> base [[texture(0)]],
                                  texture2d<float> layer [[texture(1)]],
                                  constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    float3 blended = float3(vividLightChan(b.r, l.r),
                            vividLightChan(b.g, l.g),
                            vividLightChan(b.b, l.b));
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
    return float4(result, 1.0);
}

// MARK: - Pin Light
//   l > 0.5 → max(b, 2l - 1)
//   l ≤ 0.5 → min(b, 2l)
fragment float4 blend_pinLight(VertexOut in [[stage_in]],
                                texture2d<float> base [[texture(0)]],
                                texture2d<float> layer [[texture(1)]],
                                constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    float3 hi = max(b.rgb, 2.0 * l.rgb - 1.0);
    float3 lo = min(b.rgb, 2.0 * l.rgb);
    float3 blended = select(lo, hi, l.rgb > 0.5);
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
    return float4(result, 1.0);
}

// MARK: - Hard Mix — extreme posterize: step(1 - b, l) per channel
fragment float4 blend_hardMix(VertexOut in [[stage_in]],
                               texture2d<float> base [[texture(0)]],
                               texture2d<float> layer [[texture(1)]],
                               constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    float3 blended = step(1.0 - b.rgb, l.rgb);
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
    return float4(result, 1.0);
}

// MARK: - Divide
fragment float4 blend_divide(VertexOut in [[stage_in]],
                              texture2d<float> base [[texture(0)]],
                              texture2d<float> layer [[texture(1)]],
                              constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    float3 blended = min(b.rgb / max(l.rgb, float3(1e-4)), float3(1.0));
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
    return float4(result, 1.0);
}

// MARK: - Phoenix — Resolume signature: min(b,l) - max(b,l) + 1
fragment float4 blend_phoenix(VertexOut in [[stage_in]],
                               texture2d<float> base [[texture(0)]],
                               texture2d<float> layer [[texture(1)]],
                               constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    float3 blended = min(b.rgb, l.rgb) - max(b.rgb, l.rgb) + 1.0;
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
    return float4(result, 1.0);
}

// MARK: - Reflect — b² / (1 - l), clamped
fragment float4 blend_reflect(VertexOut in [[stage_in]],
                               texture2d<float> base [[texture(0)]],
                               texture2d<float> layer [[texture(1)]],
                               constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    float3 denom = max(1.0 - l.rgb, float3(1e-4));
    float3 blended = min(b.rgb * b.rgb / denom, float3(1.0));
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
    return float4(result, 1.0);
}

// MARK: - Glow — l² / (1 - b), clamped (Reflect with operands swapped)
fragment float4 blend_glow(VertexOut in [[stage_in]],
                            texture2d<float> base [[texture(0)]],
                            texture2d<float> layer [[texture(1)]],
                            constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    float3 denom = max(1.0 - b.rgb, float3(1e-4));
    float3 blended = min(l.rgb * l.rgb / denom, float3(1.0));
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
    return float4(result, 1.0);
}

// MARK: - Stamp — base shaped by layer luma: 2*b + l - 1
fragment float4 blend_stamp(VertexOut in [[stage_in]],
                             texture2d<float> base [[texture(0)]],
                             texture2d<float> layer [[texture(1)]],
                             constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    float3 blended = clamp(2.0 * b.rgb + l.rgb - 1.0, float3(0.0), float3(1.0));
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
    return float4(result, 1.0);
}

// MARK: - HSL helpers (Photoshop algorithm, Rec.601 luma)
inline float hslLum(float3 c) { return dot(c, float3(0.3, 0.59, 0.11)); }

inline float3 hslClipColor(float3 c) {
    float L = hslLum(c);
    float n = min(min(c.r, c.g), c.b);
    float x = max(max(c.r, c.g), c.b);
    if (n < 0.0) c = L + ((c - L) * L) / (L - n);
    if (x > 1.0) c = L + ((c - L) * (1.0 - L)) / (x - L);
    return c;
}

inline float3 hslSetLum(float3 c, float L) {
    float d = L - hslLum(c);
    return hslClipColor(c + d);
}

inline float hslSat(float3 c) {
    return max(max(c.r, c.g), c.b) - min(min(c.r, c.g), c.b);
}

// Returns c with its saturation rescaled to S, preserving the relative
// position of the mid channel between min and max.
inline float3 hslSetSat(float3 c, float S) {
    float cmin = min(min(c.r, c.g), c.b);
    float cmax = max(max(c.r, c.g), c.b);
    if (cmax <= cmin) return float3(0.0);
    float scale = S / (cmax - cmin);
    float3 result;
    result.r = (c.r == cmax) ? S : ((c.r == cmin) ? 0.0 : (c.r - cmin) * scale);
    result.g = (c.g == cmax) ? S : ((c.g == cmin) ? 0.0 : (c.g - cmin) * scale);
    result.b = (c.b == cmax) ? S : ((c.b == cmin) ? 0.0 : (c.b - cmin) * scale);
    return result;
}

// MARK: - Hue — base luma+sat, layer hue
fragment float4 blend_hue(VertexOut in [[stage_in]],
                           texture2d<float> base [[texture(0)]],
                           texture2d<float> layer [[texture(1)]],
                           constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    float3 blended = hslSetLum(hslSetSat(l.rgb, hslSat(b.rgb)), hslLum(b.rgb));
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
    return float4(result, 1.0);
}

// MARK: - Saturation — base luma+hue, layer sat
fragment float4 blend_saturation(VertexOut in [[stage_in]],
                                  texture2d<float> base [[texture(0)]],
                                  texture2d<float> layer [[texture(1)]],
                                  constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    float3 blended = hslSetLum(hslSetSat(b.rgb, hslSat(l.rgb)), hslLum(b.rgb));
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
    return float4(result, 1.0);
}

// MARK: - Color — base luma, layer hue+sat (the workhorse "colorize" mode)
fragment float4 blend_color(VertexOut in [[stage_in]],
                             texture2d<float> base [[texture(0)]],
                             texture2d<float> layer [[texture(1)]],
                             constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    float3 blended = hslSetLum(l.rgb, hslLum(b.rgb));
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
    return float4(result, 1.0);
}

// MARK: - Luminosity — base hue+sat, layer luma (inverse of Color)
fragment float4 blend_luminosity(VertexOut in [[stage_in]],
                                  texture2d<float> base [[texture(0)]],
                                  texture2d<float> layer [[texture(1)]],
                                  constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 b = base.sample(s, in.texCoord);
    float4 l = layer.sample(s, in.texCoord);
    float3 blended = hslSetLum(b.rgb, hslLum(l.rgb));
    float3 result = applyOpacity(b.rgb, blended, uniforms.opacity * l.a);
    return float4(result, 1.0);
}
