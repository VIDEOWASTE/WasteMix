#include <metal_stdlib>
using namespace metal;

#include "ShaderTypes.h"

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct EffectParams {
    float param1;  // intensity 0-1
    float param2;  // secondary
    float time;    // animation time
    float padding;
};

// MARK: - Rotate (discrete 90° steps via UV remap)
// param1 is the standard 0-1 intensity slider, mapped to 4 discrete steps:
// 0..0.25 = 0°, 0.25..0.5 = 90°, 0.5..0.75 = 180°, 0.75..1.0 = 270° CW.
fragment float4 effect_rotate(VertexOut in [[stage_in]],
                               texture2d<float> tex [[texture(0)]],
                               constant EffectParams &p [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    int step = int(round(p.param1 * 3.0)) & 3;
    float2 uv = in.texCoord;
    if (step == 1) {
        uv = float2(in.texCoord.y, 1.0 - in.texCoord.x);
    } else if (step == 2) {
        uv = float2(1.0 - in.texCoord.x, 1.0 - in.texCoord.y);
    } else if (step == 3) {
        uv = float2(1.0 - in.texCoord.y, in.texCoord.x);
    }
    return tex.sample(s, uv);
}

// MARK: - Mirror Horizontal (blends between normal and mirrored based on intensity)
fragment float4 effect_mirror_h(VertexOut in [[stage_in]],
                                 texture2d<float> tex [[texture(0)]],
                                 constant EffectParams &p [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 normal = tex.sample(s, in.texCoord);
    float2 muv = float2(1.0 - in.texCoord.x, in.texCoord.y);
    float4 mirrored = tex.sample(s, muv);
    return float4(mix(normal.rgb, mirrored.rgb, p.param1), 1.0);
}

// MARK: - Mirror Vertical
fragment float4 effect_mirror_v(VertexOut in [[stage_in]],
                                 texture2d<float> tex [[texture(0)]],
                                 constant EffectParams &p [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 normal = tex.sample(s, in.texCoord);
    float2 muv = float2(in.texCoord.x, 1.0 - in.texCoord.y);
    float4 mirrored = tex.sample(s, muv);
    return float4(mix(normal.rgb, mirrored.rgb, p.param1), 1.0);
}

// MARK: - Invert (full range: 0 = normal, 1 = fully inverted)
fragment float4 effect_invert(VertexOut in [[stage_in]],
                               texture2d<float> tex [[texture(0)]],
                               constant EffectParams &p [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 c = tex.sample(s, in.texCoord);
    float3 inv = 1.0 - c.rgb;
    return float4(mix(c.rgb, inv, p.param1), c.a);
}

// MARK: - Mosaic / Pixelate (much more visible range)
fragment float4 effect_mosaic(VertexOut in [[stage_in]],
                               texture2d<float> tex [[texture(0)]],
                               constant EffectParams &p [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    // intensity 0 = 200 blocks (nearly invisible), intensity 1 = 4 blocks (very chunky)
    float blocks = mix(200.0, 4.0, p.param1);
    float2 uv = floor(in.texCoord * blocks + 0.5) / blocks;
    return tex.sample(s, uv);
}

// MARK: - Strobe (param1 = speed, param2 = duty cycle)
fragment float4 effect_strobe(VertexOut in [[stage_in]],
                               texture2d<float> tex [[texture(0)]],
                               constant EffectParams &p [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 c = tex.sample(s, in.texCoord);
    float rate = mix(1.0, 30.0, p.param1);
    // param2 controls duty cycle: 0 = 50/50, 1 = very short flash
    float duty = mix(0.5, 0.9, p.param2);
    float flash = step(duty, fract(p.time * rate));
    return float4(c.rgb * flash, c.a);
}

// MARK: - RGB Split (param1 = horizontal offset, param2 = vertical offset)
fragment float4 effect_rgb_split(VertexOut in [[stage_in]],
                                  texture2d<float> tex [[texture(0)]],
                                  constant EffectParams &p [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float hOff = p.param1 * 0.08;
    float vOff = p.param2 * 0.08;
    float r = tex.sample(s, in.texCoord + float2(hOff, vOff)).r;
    float g = tex.sample(s, in.texCoord).g;
    float b = tex.sample(s, in.texCoord - float2(hOff, vOff)).b;
    return float4(r, g, b, 1.0);
}

// MARK: - Posterize (wider range, more dramatic at high intensity)
fragment float4 effect_posterize(VertexOut in [[stage_in]],
                                  texture2d<float> tex [[texture(0)]],
                                  constant EffectParams &p [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 c = tex.sample(s, in.texCoord);
    // intensity 0 = 24 levels (subtle), intensity 1 = 2 levels (extreme)
    float levels = mix(24.0, 2.0, p.param1);
    float3 posterized = floor(c.rgb * levels + 0.5) / levels;
    return float4(posterized, c.a);
}

// MARK: - Blur (param1 = radius, param2 = direction bias: 0=uniform, 1=horizontal)
fragment float4 effect_blur(VertexOut in [[stage_in]],
                             texture2d<float> tex [[texture(0)]],
                             constant EffectParams &p [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float radius = p.param1 * 0.015;
    // param2 biases blur direction: 0 = uniform, 0.5 = slightly horizontal, 1 = motion blur
    float xScale = 1.0 + p.param2 * 2.0;
    float yScale = 1.0 - p.param2 * 0.8;
    float4 sum = float4(0);
    for (int x = -3; x <= 3; x++) {
        for (int y = -3; y <= 3; y++) {
            float2 off = float2(float(x) * xScale, float(y) * yScale) * radius;
            sum += tex.sample(s, in.texCoord + off);
        }
    }
    return sum / 49.0;
}

// MARK: - Solarize (param1 = threshold, param2 = curve intensity)
fragment float4 effect_solarize(VertexOut in [[stage_in]],
                                 texture2d<float> tex [[texture(0)]],
                                 constant EffectParams &p [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 c = tex.sample(s, in.texCoord);
    // Solarize: invert pixels above threshold, creating psychedelic color curves
    float threshold = p.param1;
    float curve = 1.0 + p.param2 * 4.0; // 1-5x curve intensity
    float3 sol;
    sol.r = c.r > threshold ? 1.0 - c.r : c.r;
    sol.g = c.g > threshold ? 1.0 - c.g : c.g;
    sol.b = c.b > threshold ? 1.0 - c.b : c.b;
    // Apply curve for more extreme solarization
    sol = pow(sol, float3(curve));
    return float4(sol, c.a);
}

// MARK: - Edge Detection (Sobel filter, param1 = strength)
fragment float4 effect_edges(VertexOut in [[stage_in]],
                              texture2d<float> tex [[texture(0)]],
                              constant EffectParams &p [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv = in.texCoord;
    float step = 0.002;

    // Sobel kernels
    float3 tl = tex.sample(s, uv + float2(-step, -step)).rgb;
    float3 t  = tex.sample(s, uv + float2(0, -step)).rgb;
    float3 tr = tex.sample(s, uv + float2(step, -step)).rgb;
    float3 l  = tex.sample(s, uv + float2(-step, 0)).rgb;
    float3 r  = tex.sample(s, uv + float2(step, 0)).rgb;
    float3 bl = tex.sample(s, uv + float2(-step, step)).rgb;
    float3 b  = tex.sample(s, uv + float2(0, step)).rgb;
    float3 br = tex.sample(s, uv + float2(step, step)).rgb;

    float3 gx = -tl - 2.0*l - bl + tr + 2.0*r + br;
    float3 gy = -tl - 2.0*t - tr + bl + 2.0*b + br;
    float3 edge = sqrt(gx*gx + gy*gy);

    float4 orig = tex.sample(s, uv);
    float strength = p.param1 * 3.0;
    float3 result = mix(orig.rgb, edge * strength, p.param1);
    return float4(saturate(result), 1.0);
}

// MARK: - Datamosh / Pixel Shift Glitch (param1 = shift amount, param2 = block height)
fragment float4 effect_datamosh(VertexOut in [[stage_in]],
                                 texture2d<float> tex [[texture(0)]],
                                 constant EffectParams &p [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv = in.texCoord;

    // Block height: thick chunky bands
    float blockH = mix(0.02, 0.15, p.param2);
    // Shift: how far blocks displace horizontally
    float shift = p.param1 * 0.5;

    // Stuttery datamosh tick — ~8 changes per second. The previous formula
    // was `floor(fract(time * 0.01) * 30.0)` which made the tick change
    // only every ~3.3s and repeat every 100s, so the glitch "froze" for
    // long stretches. Wrapping by fmod keeps the hash inputs in a tight
    // float range without losing variety.
    float timeTick = floor(fmod(p.time * 8.0, 4096.0));

    // Which horizontal band are we in?
    float blockY = floor(uv.y / blockH);

    // Pseudo-random hash per block, changes each tick
    float hash = fract(sin(blockY * 43.758 + timeTick * 12.989) * 28461.613);
    float hash2 = fract(sin(blockY * 71.331 + timeTick * 7.461) * 17183.927);
    float hash3 = fract(sin(blockY * 19.887 + timeTick * 23.157) * 51429.371);

    // Displace ~60% of blocks, leave others alone
    float displaced = 0.0;
    if (hash > 0.35) {
        displaced = (hash - 0.5) * 2.0 * shift;
    }

    // Some blocks get vertical shift too (like frame repeat)
    float yShift = 0.0;
    if (hash3 > 0.7) {
        yShift = (hash3 - 0.5) * blockH * 4.0 * p.param1;
    }

    float2 glitchUV = float2(uv.x + displaced, uv.y + yShift);

    // ~30% of blocks get RGB channel separation (chromatic glitch)
    if (hash2 > 0.65) {
        float chromaShift = shift * 0.4;
        float r = tex.sample(s, glitchUV + float2(chromaShift, 0)).r;
        float g = tex.sample(s, glitchUV).g;
        float b = tex.sample(s, glitchUV - float2(chromaShift, 0)).b;
        return float4(r, g, b, 1.0);
    }

    // ~15% of blocks get color quantized (posterized bands)
    if (hash2 < 0.15) {
        float4 c = tex.sample(s, glitchUV);
        float3 crushed = floor(c.rgb * 4.0) / 4.0;
        return float4(crushed, 1.0);
    }

    return tex.sample(s, glitchUV);
}

// MARK: - Scanlines (param1 = density, param2 = brightness)
fragment float4 effect_scanlines(VertexOut in [[stage_in]],
                                  texture2d<float> tex [[texture(0)]],
                                  constant EffectParams &p [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 c = tex.sample(s, in.texCoord);

    float lines = mix(100.0, 800.0, p.param1);
    float brightness = mix(0.3, 0.9, p.param2);

    float scanline = sin(in.texCoord.y * lines * M_PI_F) * 0.5 + 0.5;
    scanline = mix(brightness, 1.0, scanline);

    return float4(c.rgb * scanline, c.a);
}

// MARK: - Kaleidoscope (param1 = segments, param2 = rotation)
//
// Metal's `fmod(a,b)` returns the sign of `a`; for negative input angles
// that produces negative segment indices and inverted mirroring. Wrap with
// a non-negative modulo helper instead of relying on the +100π offset.
inline float wrapMod(float x, float m) {
    float r = fmod(x, m);
    return r < 0.0 ? r + m : r;
}

fragment float4 effect_kaleidoscope(VertexOut in [[stage_in]],
                                     texture2d<float> tex [[texture(0)]],
                                     constant EffectParams &p [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    float2 uv = in.texCoord - 0.5;
    float baseAngle = atan2(uv.y, uv.x);
    float angle = baseAngle + p.param2 * M_PI_F * 2.0;
    float radius = length(uv);

    // Number of segments: 2-16
    float segments = floor(mix(2.0, 16.0, p.param1));
    float segAngle = M_PI_F * 2.0 / segments;

    // Fold angle into one segment using non-negative modulo.
    float folded = wrapMod(angle, segAngle);
    // Mirror alternating segments — index derived from the same wrapped
    // base angle so the mirroring stays consistent regardless of rotation.
    float segIndex = floor(wrapMod(angle, M_PI_F * 2.0) / segAngle);
    if (fmod(segIndex, 2.0) > 0.5) {
        folded = segAngle - folded;
    }

    float2 kalUV = float2(cos(folded), sin(folded)) * radius + 0.5;
    kalUV = clamp(kalUV, float2(0.0), float2(1.0));

    return tex.sample(s, kalUV);
}

// MARK: - Halftone (param1 = dot size)
fragment float4 effect_halftone(VertexOut in [[stage_in]],
                                 texture2d<float> tex [[texture(0)]],
                                 constant EffectParams &p [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 c = tex.sample(s, in.texCoord);

    float dotSize = mix(3.0, 30.0, p.param1);
    float2 uv = in.texCoord;

    // Grid cell
    float2 cell = floor(uv * dotSize) / dotSize;
    float2 cellCenter = cell + 0.5 / dotSize;

    // Sample color at cell center
    float4 cellColor = tex.sample(s, cellCenter);
    float luma = dot(cellColor.rgb, float3(0.2126, 0.7152, 0.0722));

    // Distance from cell center
    float dist = length(uv - cellCenter) * dotSize;

    // Dot radius based on luminance (brighter = bigger dot)
    float dotRadius = luma * 0.5;
    float dot = smoothstep(dotRadius + 0.05, dotRadius - 0.05, dist);

    return float4(cellColor.rgb * dot, 1.0);
}

// MARK: - Luma Key
//
// param1 = threshold (0-1)
// param2 = softness (half-width of the alpha falloff edge)
// padding = invert flag (0 = key out blacks / keep brights;
//                        1 = key out whites / keep darks)
fragment float4 key_luma(VertexOut in [[stage_in]],
                          texture2d<float> tex [[texture(0)]],
                          constant EffectParams &p [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 c = tex.sample(s, in.texCoord);
    float luma = dot(c.rgb, float3(0.2126, 0.7152, 0.0722));
    float alpha = smoothstep(p.param1 - p.param2, p.param1 + p.param2, luma);
    if (p.padding > 0.5) { alpha = 1.0 - alpha; }
    return float4(c.rgb, alpha);
}

// MARK: - Chroma Key
fragment float4 key_chroma(VertexOut in [[stage_in]],
                            texture2d<float> tex [[texture(0)]],
                            constant EffectParams &p [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 c = tex.sample(s, in.texCoord);

    float cmax = max(c.r, max(c.g, c.b));
    float cmin = min(c.r, min(c.g, c.b));
    float delta = cmax - cmin;

    float hue = 0;
    if (delta > 0.001) {
        if (cmax == c.r) hue = fmod((c.g - c.b) / delta, 6.0);
        else if (cmax == c.g) hue = (c.b - c.r) / delta + 2.0;
        else hue = (c.r - c.g) / delta + 4.0;
        hue *= 60.0;
        if (hue < 0) hue += 360.0;
    }
    float sat = cmax > 0.001 ? delta / cmax : 0;

    float targetHue = p.time;
    float hueDiff = abs(hue - targetHue);
    if (hueDiff > 180.0) hueDiff = 360.0 - hueDiff;

    float tolerance = p.param1 * 180.0;
    float soft = p.param2 * 60.0;
    float mask = smoothstep(tolerance - soft, tolerance + soft, hueDiff);
    float satMask = smoothstep(0.1, 0.3, sat);
    float alpha = max(mask, 1.0 - satMask);
    // padding > 0.5 means "invert": keep the keyed-out hue and knock out
    // everything else. Same flag layout as the luma key.
    if (p.padding > 0.5) { alpha = 1.0 - alpha; }

    return float4(c.rgb, alpha);
}

// MARK: - Feedback (param1 = feedback amount/decay, param2 = zoom/drift)
// Blends current frame with the previous frame's output, creating trails/echoes.
// texture(0) = current input, texture(1) = previous feedback buffer
fragment float4 effect_feedback(VertexOut in [[stage_in]],
                                 texture2d<float> tex [[texture(0)]],
                                 texture2d<float> prevTex [[texture(1)]],
                                 constant EffectParams &p [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    float4 current = tex.sample(s, in.texCoord);

    // Subtle zoom toward center for each feedback iteration
    float zoom = 1.0 - p.param2 * 0.02;
    float2 fbUV = (in.texCoord - 0.5) * zoom + 0.5;

    // Slow rotation driven by param2
    float angle = p.param2 * 0.005 * p.time;
    float2 centered = fbUV - 0.5;
    float cs = cos(angle);
    float sn = sin(angle);
    fbUV = float2(centered.x * cs - centered.y * sn,
                   centered.x * sn + centered.y * cs) + 0.5;

    float4 prev = prevTex.sample(s, fbUV);

    // param1 controls persistence: 0 = no trails, 1 = infinite trails
    float feedbackAmount = p.param1 * 0.95;
    float4 blended = mix(current, prev, feedbackAmount);

    return float4(blended.rgb, 1.0);
}
