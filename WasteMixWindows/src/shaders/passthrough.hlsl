#include "common.hlsli"

Texture2D tex : register(t0);

float4 PSPassthrough(PSInput input) : SV_TARGET {
    return tex.Sample(linearSampler, input.texCoord);
}

float4 PSPassthroughOpacity(PSInput input) : SV_TARGET {
    float4 color = tex.Sample(linearSampler, input.texCoord);
    return float4(color.rgb * opacity, 1.0);
}

float4 PSSolidColor(PSInput input) : SV_TARGET {
    return float4(opacity, opacity, opacity, 1.0); // repurpose opacity as gray value
}

float4 PSPIP(PSInput input) : SV_TARGET {
    float2 uv = input.texCoord;
    float scale = pipScale;
    float2 offset = float2(pipOffsetX * 0.5, pipOffsetY * 0.5);

    if (scale > 1.0) {
        float2 center = float2(0.5, 0.5) - offset;
        float invScale = 1.0 / scale;
        float2 srcUV = (uv - 0.5) * invScale + center;
        srcUV = clamp(srcUV, float2(0.0, 0.0), float2(1.0, 1.0));
        float4 color = tex.Sample(linearSampler, srcUV);
        return float4(color.rgb * pipOpacity, pipOpacity);
    } else {
        float2 pipCenter = float2(0.5, 0.5) + offset;
        float2 halfSize = float2(scale * 0.5, scale * 0.5);
        float2 minBound = pipCenter - halfSize;
        float2 maxBound = pipCenter + halfSize;
        if (uv.x < minBound.x || uv.x > maxBound.x || uv.y < minBound.y || uv.y > maxBound.y)
            return float4(0, 0, 0, 0);
        float2 srcUV = (uv - minBound) / (maxBound - minBound);
        float4 color = tex.Sample(linearSampler, srcUV);
        return float4(color.rgb * pipOpacity, pipOpacity);
    }
}
