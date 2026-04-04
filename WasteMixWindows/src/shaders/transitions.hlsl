#include "common.hlsli"

Texture2D baseTex : register(t0);
Texture2D layerTex : register(t1);

static const float PI = 3.14159265;

float wipeMask(float2 uv, float prog, int dir) {
    float edge = 0.015;
    float mask = 0.0;
    if (dir == 0) mask = smoothstep(prog - edge, prog + edge, 1.0 - uv.x);
    else if (dir == 1) mask = smoothstep(prog - edge, prog + edge, uv.x);
    else if (dir == 2) mask = smoothstep(prog - edge, prog + edge, 1.0 - uv.y);
    else if (dir == 3) mask = smoothstep(prog - edge, prog + edge, uv.y);
    else if (dir == 4) { float d = (uv.x + uv.y) * 0.5; mask = smoothstep(prog - edge, prog + edge, d); }
    else if (dir == 5) { float d = ((1-uv.x) + uv.y) * 0.5; mask = smoothstep(prog - edge, prog + edge, d); }
    else if (dir == 6) { float dist = length(uv - 0.5) / 0.7071; mask = smoothstep(prog - edge, prog + edge, 1 - dist); }
    else if (dir == 7) { float dist = abs(uv.x - 0.5) + abs(uv.y - 0.5); mask = smoothstep(prog - edge, prog + edge, 1 - dist); }
    else if (dir == 8) { float slat = frac(uv.x * 8.0); mask = smoothstep(prog - edge, prog + edge, slat); }
    else if (dir == 9) {
        float2 d = uv - 0.5;
        float angle = atan2(d.y, d.x) + PI / 2.0 + 20.0 * PI / 180.0;
        float radius = length(d);
        float wedge = PI / 5.0;
        float a = fmod(angle + 20.0 * PI, 2.0 * wedge) - wedge;
        float outerR = 1.0; float innerR = 0.38;
        float starR = (outerR * innerR) / (innerR * cos(a) + outerR * sin(abs(a)));
        float starDist = radius / starR;
        float threshold = prog * 2.0;
        mask = 1.0 - smoothstep(threshold - edge * 3, threshold + edge * 3, starDist);
    }
    return mask;
}

float4 PSWipeAB(PSInput input) : SV_TARGET {
    float4 a = baseTex.Sample(linearSampler, input.texCoord);
    float4 b = layerTex.Sample(linearSampler, input.texCoord);
    float mask = wipeMask(input.texCoord, progress, direction);
    return float4(lerp(a.rgb, b.rgb, mask), 1.0);
}

float4 PSWipeSingle(PSInput input) : SV_TARGET {
    float4 color = baseTex.Sample(linearSampler, input.texCoord);
    float mask = wipeMask(input.texCoord, progress, direction);
    return float4(color.rgb * mask, 1.0);
}

float4 PSDip(PSInput input) : SV_TARGET {
    float4 color = baseTex.Sample(linearSampler, input.texCoord);
    float fade = progress < 0.5 ? 1.0 - progress * 2.0 : (progress - 0.5) * 2.0;
    return float4(color.rgb * fade, color.a);
}
