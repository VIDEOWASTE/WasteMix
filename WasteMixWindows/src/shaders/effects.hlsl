#include "common.hlsli"

Texture2D tex : register(t0);

static const float PI = 3.14159265;

float4 PSMirrorH(PSInput input) : SV_TARGET {
    float4 normal = tex.Sample(linearSampler, input.texCoord);
    float2 muv = float2(1.0 - input.texCoord.x, input.texCoord.y);
    float4 mirrored = tex.Sample(linearSampler, muv);
    return float4(lerp(normal.rgb, mirrored.rgb, param1), 1.0);
}

float4 PSMirrorV(PSInput input) : SV_TARGET {
    float4 normal = tex.Sample(linearSampler, input.texCoord);
    float2 muv = float2(input.texCoord.x, 1.0 - input.texCoord.y);
    float4 mirrored = tex.Sample(linearSampler, muv);
    return float4(lerp(normal.rgb, mirrored.rgb, param1), 1.0);
}

float4 PSInvert(PSInput input) : SV_TARGET {
    float4 c = tex.Sample(linearSampler, input.texCoord);
    float3 inv = 1.0 - c.rgb;
    return float4(lerp(c.rgb, inv, param1), c.a);
}

float4 PSMosaic(PSInput input) : SV_TARGET {
    float blocks = lerp(200.0, 4.0, param1);
    float2 uv = floor(input.texCoord * blocks + 0.5) / blocks;
    return tex.Sample(linearSampler, uv);
}

float4 PSStrobe(PSInput input) : SV_TARGET {
    float4 c = tex.Sample(linearSampler, input.texCoord);
    float rate = lerp(1.0, 30.0, param1);
    float duty = lerp(0.5, 0.9, param2);
    float flash = step(duty, frac(time * rate));
    return float4(c.rgb * flash, c.a);
}

float4 PSRGBSplit(PSInput input) : SV_TARGET {
    float hOff = param1 * 0.08;
    float vOff = param2 * 0.08;
    float r = tex.Sample(linearSampler, input.texCoord + float2(hOff, vOff)).r;
    float g = tex.Sample(linearSampler, input.texCoord).g;
    float b = tex.Sample(linearSampler, input.texCoord - float2(hOff, vOff)).b;
    return float4(r, g, b, 1.0);
}

float4 PSPosterize(PSInput input) : SV_TARGET {
    float4 c = tex.Sample(linearSampler, input.texCoord);
    float levels = lerp(24.0, 2.0, param1);
    float3 posterized = floor(c.rgb * levels + 0.5) / levels;
    return float4(posterized, c.a);
}

float4 PSBlur(PSInput input) : SV_TARGET {
    float radius = param1 * 0.015;
    float xScale = 1.0 + param2 * 2.0;
    float yScale = 1.0 - param2 * 0.8;
    float4 sum = float4(0, 0, 0, 0);
    for (int x = -3; x <= 3; x++) {
        for (int y = -3; y <= 3; y++) {
            float2 off = float2(float(x) * xScale, float(y) * yScale) * radius;
            sum += tex.Sample(linearSampler, input.texCoord + off);
        }
    }
    return sum / 49.0;
}

float4 PSSolarize(PSInput input) : SV_TARGET {
    float4 c = tex.Sample(linearSampler, input.texCoord);
    float curve = 1.0 + param2 * 4.0;
    float3 sol;
    sol.r = c.r > param1 ? 1.0 - c.r : c.r;
    sol.g = c.g > param1 ? 1.0 - c.g : c.g;
    sol.b = c.b > param1 ? 1.0 - c.b : c.b;
    sol = pow(sol, float3(curve, curve, curve));
    return float4(sol, c.a);
}

float4 PSEdges(PSInput input) : SV_TARGET {
    float2 uv = input.texCoord;
    float s = 0.002;
    float3 tl = tex.Sample(linearSampler, uv + float2(-s, -s)).rgb;
    float3 t  = tex.Sample(linearSampler, uv + float2( 0, -s)).rgb;
    float3 tr = tex.Sample(linearSampler, uv + float2( s, -s)).rgb;
    float3 l  = tex.Sample(linearSampler, uv + float2(-s,  0)).rgb;
    float3 r  = tex.Sample(linearSampler, uv + float2( s,  0)).rgb;
    float3 bl = tex.Sample(linearSampler, uv + float2(-s,  s)).rgb;
    float3 b  = tex.Sample(linearSampler, uv + float2( 0,  s)).rgb;
    float3 br = tex.Sample(linearSampler, uv + float2( s,  s)).rgb;
    float3 gx = -tl - 2*l - bl + tr + 2*r + br;
    float3 gy = -tl - 2*t - tr + bl + 2*b + br;
    float3 edge = sqrt(gx*gx + gy*gy);
    float4 orig = tex.Sample(linearSampler, uv);
    float3 result = lerp(orig.rgb, edge * param1 * 3.0, param1);
    return float4(saturate(result), 1.0);
}

float4 PSDatamosh(PSInput input) : SV_TARGET {
    float2 uv = input.texCoord;
    float blockH = lerp(0.02, 0.15, param2);
    float shift = param1 * 0.5;
    float timeTick = floor(frac(time * 0.01) * 30.0);
    float blockY = floor(uv.y / blockH);
    float hash  = frac(sin(blockY * 43.758 + timeTick * 12.989) * 28461.613);
    float hash2 = frac(sin(blockY * 71.331 + timeTick * 7.461) * 17183.927);
    float hash3 = frac(sin(blockY * 19.887 + timeTick * 23.157) * 51429.371);
    float displaced = 0.0;
    if (hash > 0.35) displaced = (hash - 0.5) * 2.0 * shift;
    float yShift = 0.0;
    if (hash3 > 0.7) yShift = (hash3 - 0.5) * blockH * 4.0 * param1;
    float2 glitchUV = float2(uv.x + displaced, uv.y + yShift);
    if (hash2 > 0.65) {
        float chromaShift = shift * 0.4;
        float r = tex.Sample(linearSampler, glitchUV + float2(chromaShift, 0)).r;
        float g = tex.Sample(linearSampler, glitchUV).g;
        float b = tex.Sample(linearSampler, glitchUV - float2(chromaShift, 0)).b;
        return float4(r, g, b, 1.0);
    }
    if (hash2 < 0.15) {
        float4 c = tex.Sample(linearSampler, glitchUV);
        return float4(floor(c.rgb * 4.0) / 4.0, 1.0);
    }
    return tex.Sample(linearSampler, glitchUV);
}

float4 PSScanlines(PSInput input) : SV_TARGET {
    float4 c = tex.Sample(linearSampler, input.texCoord);
    float lines = lerp(100.0, 800.0, param1);
    float bright = lerp(0.3, 0.9, param2);
    float scanline = sin(input.texCoord.y * lines * PI) * 0.5 + 0.5;
    scanline = lerp(bright, 1.0, scanline);
    return float4(c.rgb * scanline, c.a);
}

float4 PSKaleidoscope(PSInput input) : SV_TARGET {
    float2 uv = input.texCoord - 0.5;
    float angle = atan2(uv.y, uv.x) + param2 * PI * 2.0;
    float radius = length(uv);
    float segments = floor(lerp(2.0, 16.0, param1));
    float segAngle = PI * 2.0 / segments;
    angle = fmod(angle + 100.0 * PI, segAngle);
    if (fmod(floor((atan2(uv.y, uv.x) + 100.0 * PI) / segAngle), 2.0) > 0.5)
        angle = segAngle - angle;
    float2 kalUV = float2(cos(angle), sin(angle)) * radius + 0.5;
    kalUV = clamp(kalUV, float2(0, 0), float2(1, 1));
    return tex.Sample(linearSampler, kalUV);
}

float4 PSHalftone(PSInput input) : SV_TARGET {
    float dotSize = lerp(3.0, 30.0, param1);
    float2 uv = input.texCoord;
    float2 cell = floor(uv * dotSize) / dotSize;
    float2 cellCenter = cell + 0.5 / dotSize;
    float4 cellColor = tex.Sample(linearSampler, cellCenter);
    float luma = dot(cellColor.rgb, float3(0.2126, 0.7152, 0.0722));
    float dist = length(uv - cellCenter) * dotSize;
    float dotRadius = luma * 0.5;
    float d = smoothstep(dotRadius + 0.05, dotRadius - 0.05, dist);
    return float4(cellColor.rgb * d, 1.0);
}
