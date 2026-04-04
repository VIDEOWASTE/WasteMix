#include "common.hlsli"

Texture2D baseTex : register(t0);
Texture2D layerTex : register(t1);

float3 applyOpacity(float3 base, float3 blended, float op) {
    return lerp(base, blended, op);
}

float4 PSBlendNormal(PSInput input) : SV_TARGET {
    float4 b = baseTex.Sample(linearSampler, input.texCoord);
    float4 l = layerTex.Sample(linearSampler, input.texCoord);
    float3 result = applyOpacity(b.rgb, l.rgb, opacity * l.a);
    return float4(result, 1.0);
}

float4 PSBlendAdd(PSInput input) : SV_TARGET {
    float4 b = baseTex.Sample(linearSampler, input.texCoord);
    float4 l = layerTex.Sample(linearSampler, input.texCoord);
    float3 blended = min(b.rgb + l.rgb, float3(1, 1, 1));
    return float4(applyOpacity(b.rgb, blended, opacity), 1.0);
}

float4 PSBlendMultiply(PSInput input) : SV_TARGET {
    float4 b = baseTex.Sample(linearSampler, input.texCoord);
    float4 l = layerTex.Sample(linearSampler, input.texCoord);
    float3 blended = b.rgb * l.rgb;
    return float4(applyOpacity(b.rgb, blended, opacity), 1.0);
}

float4 PSBlendScreen(PSInput input) : SV_TARGET {
    float4 b = baseTex.Sample(linearSampler, input.texCoord);
    float4 l = layerTex.Sample(linearSampler, input.texCoord);
    float3 blended = 1.0 - (1.0 - b.rgb) * (1.0 - l.rgb);
    return float4(applyOpacity(b.rgb, blended, opacity), 1.0);
}

float4 PSBlendOverlay(PSInput input) : SV_TARGET {
    float4 b = baseTex.Sample(linearSampler, input.texCoord);
    float4 l = layerTex.Sample(linearSampler, input.texCoord);
    float3 blended;
    blended.r = b.r < 0.5 ? 2.0 * b.r * l.r : 1.0 - 2.0 * (1.0 - b.r) * (1.0 - l.r);
    blended.g = b.g < 0.5 ? 2.0 * b.g * l.g : 1.0 - 2.0 * (1.0 - b.g) * (1.0 - l.g);
    blended.b = b.b < 0.5 ? 2.0 * b.b * l.b : 1.0 - 2.0 * (1.0 - b.b) * (1.0 - l.b);
    return float4(applyOpacity(b.rgb, blended, opacity), 1.0);
}

float4 PSBlendDifference(PSInput input) : SV_TARGET {
    float4 b = baseTex.Sample(linearSampler, input.texCoord);
    float4 l = layerTex.Sample(linearSampler, input.texCoord);
    float3 blended = abs(b.rgb - l.rgb);
    return float4(applyOpacity(b.rgb, blended, opacity), 1.0);
}

float4 PSBlendExclusion(PSInput input) : SV_TARGET {
    float4 b = baseTex.Sample(linearSampler, input.texCoord);
    float4 l = layerTex.Sample(linearSampler, input.texCoord);
    float3 blended = b.rgb + l.rgb - 2.0 * b.rgb * l.rgb;
    return float4(applyOpacity(b.rgb, blended, opacity), 1.0);
}

float4 PSBlendHardLight(PSInput input) : SV_TARGET {
    float4 b = baseTex.Sample(linearSampler, input.texCoord);
    float4 l = layerTex.Sample(linearSampler, input.texCoord);
    float3 blended;
    blended.r = l.r < 0.5 ? 2.0 * b.r * l.r : 1.0 - 2.0 * (1.0 - b.r) * (1.0 - l.r);
    blended.g = l.g < 0.5 ? 2.0 * b.g * l.g : 1.0 - 2.0 * (1.0 - b.g) * (1.0 - l.g);
    blended.b = l.b < 0.5 ? 2.0 * b.b * l.b : 1.0 - 2.0 * (1.0 - b.b) * (1.0 - l.b);
    return float4(applyOpacity(b.rgb, blended, opacity), 1.0);
}

float4 PSBlendSoftLight(PSInput input) : SV_TARGET {
    float4 b = baseTex.Sample(linearSampler, input.texCoord);
    float4 l = layerTex.Sample(linearSampler, input.texCoord);
    float3 blended = (1.0 - 2.0 * l.rgb) * b.rgb * b.rgb + 2.0 * l.rgb * b.rgb;
    return float4(applyOpacity(b.rgb, blended, opacity), 1.0);
}

float4 PSBlendColorDodge(PSInput input) : SV_TARGET {
    float4 b = baseTex.Sample(linearSampler, input.texCoord);
    float4 l = layerTex.Sample(linearSampler, input.texCoord);
    float3 blended;
    blended.r = l.r >= 1.0 ? 1.0 : min(1.0, b.r / (1.0 - l.r));
    blended.g = l.g >= 1.0 ? 1.0 : min(1.0, b.g / (1.0 - l.g));
    blended.b = l.b >= 1.0 ? 1.0 : min(1.0, b.b / (1.0 - l.b));
    return float4(applyOpacity(b.rgb, blended, opacity), 1.0);
}

float4 PSBlendColorBurn(PSInput input) : SV_TARGET {
    float4 b = baseTex.Sample(linearSampler, input.texCoord);
    float4 l = layerTex.Sample(linearSampler, input.texCoord);
    float3 blended;
    blended.r = l.r <= 0.0 ? 0.0 : max(0.0, 1.0 - (1.0 - b.r) / l.r);
    blended.g = l.g <= 0.0 ? 0.0 : max(0.0, 1.0 - (1.0 - b.g) / l.g);
    blended.b = l.b <= 0.0 ? 0.0 : max(0.0, 1.0 - (1.0 - b.b) / l.b);
    return float4(applyOpacity(b.rgb, blended, opacity), 1.0);
}

float4 PSBlendDarken(PSInput input) : SV_TARGET {
    float4 b = baseTex.Sample(linearSampler, input.texCoord);
    float4 l = layerTex.Sample(linearSampler, input.texCoord);
    return float4(applyOpacity(b.rgb, min(b.rgb, l.rgb), opacity), 1.0);
}

float4 PSBlendLighten(PSInput input) : SV_TARGET {
    float4 b = baseTex.Sample(linearSampler, input.texCoord);
    float4 l = layerTex.Sample(linearSampler, input.texCoord);
    return float4(applyOpacity(b.rgb, max(b.rgb, l.rgb), opacity), 1.0);
}

float4 PSBlendSubtract(PSInput input) : SV_TARGET {
    float4 b = baseTex.Sample(linearSampler, input.texCoord);
    float4 l = layerTex.Sample(linearSampler, input.texCoord);
    return float4(applyOpacity(b.rgb, max(b.rgb - l.rgb, float3(0,0,0)), opacity), 1.0);
}

float4 PSBlendAverage(PSInput input) : SV_TARGET {
    float4 b = baseTex.Sample(linearSampler, input.texCoord);
    float4 l = layerTex.Sample(linearSampler, input.texCoord);
    return float4(applyOpacity(b.rgb, (b.rgb + l.rgb) * 0.5, opacity), 1.0);
}

float4 PSBlendXOR(PSInput input) : SV_TARGET {
    float4 b = baseTex.Sample(linearSampler, input.texCoord);
    float4 l = layerTex.Sample(linearSampler, input.texCoord);
    uint3 bi = uint3(b.rgb * 255.0);
    uint3 li = uint3(l.rgb * 255.0);
    uint3 xi = bi ^ li;
    float3 blended = float3(xi) / 255.0;
    return float4(applyOpacity(b.rgb, blended, opacity), 1.0);
}
