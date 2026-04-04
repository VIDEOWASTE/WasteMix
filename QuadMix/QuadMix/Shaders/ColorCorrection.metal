#include <metal_stdlib>
using namespace metal;

#include "ShaderTypes.h"

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

float3 rgbToHsv(float3 c) {
    float4 K = float4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    float4 p = mix(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = mix(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

float3 hsvToRgb(float3 c) {
    float4 K = float4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

fragment float4 color_correction(VertexOut in [[stage_in]],
                                  texture2d<float> input [[texture(0)]],
                                  constant ColorCorrectionUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 color = input.sample(s, in.texCoord);

    // RGB gains
    color.rgb *= float3(u.redGain, u.greenGain, u.blueGain);

    // Brightness (additive)
    color.rgb += u.brightness;

    // Contrast (around midpoint 0.5)
    color.rgb = (color.rgb - 0.5) * u.contrast + 0.5;

    // Saturation (luminance-based)
    float lum = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    color.rgb = mix(float3(lum), color.rgb, u.saturation);

    // Hue shift via HSV
    if (abs(u.hueShift) > 0.001) {
        float3 hsv = rgbToHsv(color.rgb);
        hsv.x = fract(hsv.x + u.hueShift / 360.0);
        color.rgb = hsvToRgb(hsv);
    }

    // Black balance: raise black level + per-channel shadow tint (lift)
    color.rgb = max(color.rgb, float3(u.blackLevel));
    color.rgb += float3(u.liftR, u.liftG, u.liftB) * (1.0 - color.rgb);

    return float4(saturate(color.rgb), color.a);
}
