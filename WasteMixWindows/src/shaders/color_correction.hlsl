#include "common.hlsli"

Texture2D tex : register(t0);

float3 rgbToHsv(float3 c) {
    float4 K = float4(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

float3 hsvToRgb(float3 c) {
    float4 K = float4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    float3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * lerp(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

float4 PSColorCorrection(PSInput input) : SV_TARGET {
    float4 color = tex.Sample(linearSampler, input.texCoord);

    color.rgb *= float3(redGain, greenGain, blueGain);
    color.rgb += brightness;
    color.rgb = (color.rgb - 0.5) * contrast + 0.5;

    float lum = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    color.rgb = lerp(float3(lum, lum, lum), color.rgb, saturation);

    if (abs(hueShift) > 0.001) {
        float3 hsv = rgbToHsv(color.rgb);
        hsv.x = frac(hsv.x + hueShift / 360.0);
        color.rgb = hsvToRgb(hsv);
    }

    return float4(saturate(color.rgb), color.a);
}
