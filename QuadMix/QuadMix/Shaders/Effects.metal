#include <metal_stdlib>
using namespace metal;

#include "ShaderTypes.h"

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Mirror of Swift `EffectUniforms`. Six generic param slots, then time +
// aspect. Effects that only need 1-2 knobs ignore the rest.
// param3 doubles as the invert flag for the luma/chroma key shaders.
struct EffectParams {
    float param1;
    float param2;
    float param3;
    float param4;
    float param5;
    float param6;
    float time;
    float aspect;
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
    if (p.param3 > 0.5) { alpha = 1.0 - alpha; }
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
    if (p.param3 > 0.5) { alpha = 1.0 - alpha; }

    return float4(c.rgb, alpha);
}

// MARK: - Feedback (Chromatose-style, 6 params)
// param1 = trail amount (persistence)
// param2 = zoom/rotate amount
// param3 = min luma threshold (only bright-enough pixels feed back)
// param4 = smooth (blurs the feedback sample to soften edges)
// param5 = input mix (how much of the current frame paints in vs pure trails)
// param6 = tint shift (per-iteration hue rotation — rainbow trails)
//
// Texture(0) = current input, texture(1) = previous feedback buffer.
fragment float4 effect_feedback(VertexOut in [[stage_in]],
                                 texture2d<float> tex [[texture(0)]],
                                 texture2d<float> prevTex [[texture(1)]],
                                 constant EffectParams &p [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    float4 current = tex.sample(s, in.texCoord);

    // Zoom + rotation per iteration
    float zoom = 1.0 - p.param2 * 0.02;
    float2 fbUV = (in.texCoord - 0.5) * zoom + 0.5;
    float angle = p.param2 * 0.005 * p.time;
    float2 centered = fbUV - 0.5;
    float cs = cos(angle);
    float sn = sin(angle);
    fbUV = float2(centered.x * cs - centered.y * sn,
                   centered.x * sn + centered.y * cs) + 0.5;

    // Smoothed previous-frame fetch (4-tap box blur, scaled by param4)
    float4 prev;
    if (p.param4 > 0.01) {
        float r = p.param4 * 0.005;
        prev  = prevTex.sample(s, fbUV + float2( r,  r));
        prev += prevTex.sample(s, fbUV + float2(-r,  r));
        prev += prevTex.sample(s, fbUV + float2( r, -r));
        prev += prevTex.sample(s, fbUV + float2(-r, -r));
        prev *= 0.25;
    } else {
        prev = prevTex.sample(s, fbUV);
    }

    // Min-luma gate: trails persist only on pixels brighter than the
    // threshold (param3). Below the threshold we suppress the trail's
    // contribution so dark areas don't hold smudge. Soft ramp.
    float lumaPrev = dot(prev.rgb, float3(0.299, 0.587, 0.114));
    float minLuma = p.param3;
    float lumaGate = smoothstep(minLuma, minLuma + 0.05, lumaPrev);

    // Tint shift — rotate the fed-back hue a touch each iteration.
    if (p.param6 > 0.01) {
        float hueShift = p.param6 * 0.05; // small per-frame shift
        // Cheap approx hue rotation via a fixed RGB->RGB matrix
        float c_h = cos(hueShift);
        float s_h = sin(hueShift);
        float3 rot = float3(
            prev.r * (0.213 + 0.787 * c_h - 0.213 * s_h)
          + prev.g * (0.715 - 0.715 * c_h - 0.715 * s_h)
          + prev.b * (0.072 - 0.072 * c_h + 0.928 * s_h),
            prev.r * (0.213 - 0.213 * c_h + 0.143 * s_h)
          + prev.g * (0.715 + 0.285 * c_h + 0.140 * s_h)
          + prev.b * (0.072 - 0.072 * c_h - 0.283 * s_h),
            prev.r * (0.213 - 0.213 * c_h - 0.787 * s_h)
          + prev.g * (0.715 - 0.715 * c_h + 0.715 * s_h)
          + prev.b * (0.072 + 0.928 * c_h + 0.072 * s_h)
        );
        prev.rgb = rot;
    }

    float trail = p.param1 * 0.95 * lumaGate;
    float inputMix = clamp(p.param5, 0.0, 1.0);
    float3 fb = mix(current.rgb * inputMix, prev.rgb, trail);
    // Always paint at least a faint copy of input so the loop doesn't fade
    // to black if param5 is zeroed mid-performance.
    fb = max(fb, current.rgb * 0.05);

    return float4(fb, 1.0);
}

// MARK: - Wave (Chromatose-style multi-wave UV displacement)
// param1 = amplitude (0..1 → 0..30% UV displacement)
// param2 = frequency (0..1 → 1..30 cycles per screen)
// param3 = speed (0..1 → 0..4 cycles per second)
// param4 = angle (0..1 → 0..2π wave-travel direction)
// param5 = shape (0..1 → 4 discrete shapes: sin / tri / square / saw)
// param6 = 2nd-wave mix (adds a perpendicular wave at half the frequency)
fragment float4 effect_wave(VertexOut in [[stage_in]],
                             texture2d<float> tex [[texture(0)]],
                             constant EffectParams &p [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    float amp = p.param1 * 0.3;
    float freq = mix(1.0, 30.0, p.param2);
    float speed = p.param3 * 4.0;
    float angle = p.param4 * 6.2831853;
    int shape = int(round(p.param5 * 3.0));
    float secondMix = p.param6;

    float2 dir = float2(cos(angle), sin(angle));
    float2 perp = float2(-dir.y, dir.x);

    // Wave traveling along `dir`, displacing perpendicular to it.
    float t = dot(in.texCoord - 0.5, dir) * freq + p.time * speed;
    float w;
    if (shape == 0)      w = sin(t * 6.2831853);
    else if (shape == 1) w = abs(fract(t) * 2.0 - 1.0) * 2.0 - 1.0;          // triangle
    else if (shape == 2) w = (fract(t) < 0.5) ? 1.0 : -1.0;                  // square
    else                 w = fract(t) * 2.0 - 1.0;                           // saw

    // Optional second wave perpendicular to the first
    float w2 = 0.0;
    if (secondMix > 0.001) {
        float t2 = dot(in.texCoord - 0.5, perp) * freq * 0.5 + p.time * speed * 0.7;
        w2 = sin(t2 * 6.2831853) * secondMix;
    }

    float2 disp = perp * w * amp + dir * w2 * amp;
    return tex.sample(s, in.texCoord + disp);
}

// MARK: - Tunnel (polar warp with depth illusion)
// param1 = zoom speed (forward movement through the tunnel)
// param2 = twist (angular shift that grows with radius)
// param3 = repeat count (1..8 concentric rings of the source)
// param4 = center X (0..1, default 0.5)
// param5 = center Y (0..1, default 0.5)
// param6 = edge fade (vignette toward the tunnel mouth)
fragment float4 effect_tunnel(VertexOut in [[stage_in]],
                               texture2d<float> tex [[texture(0)]],
                               constant EffectParams &p [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::repeat);

    float2 center = float2(p.param4, p.param5);
    float2 d = in.texCoord - center;
    d.x *= p.aspect;  // aspect-correct so the tunnel is round, not elliptical
    float r = length(d);
    float a = atan2(d.y, d.x);

    float zoomSpeed = p.param2 < 0 ? p.param1 * 2.0 : p.param1 * 2.0;
    float twist = (p.param2 - 0.5) * 6.2831853;
    float repeats = mix(1.0, 8.0, p.param3);

    // Map radius to depth: closer to center = "further away" tunnel walls
    // moving outward as time advances → forward-flight illusion.
    float depth = 1.0 / max(r, 1e-3);
    float u = (a + twist * r) / 6.2831853;
    float v = depth * 0.25 + p.time * zoomSpeed * 0.3;

    float2 srcUV = float2(u * repeats, v * repeats);
    float4 col = tex.sample(s, fract(srcUV));

    // Edge fade — darken near the outer rim (small r-relative is "deep",
    // larger r approaches the canvas edge).
    if (p.param6 > 0.01) {
        float fade = smoothstep(0.55, 0.05, r) * p.param6 + (1.0 - p.param6);
        col.rgb *= fade;
    }

    return col;
}

// MARK: - Channels (per-channel UV offset at arbitrary angle)
// param1 = distance (0..1 → 0..10% UV shift)
// param2 = angle (0..1 → 0..2π)
// param3 = red mix (channel intensity)
// param4 = green mix
// param5 = blue mix
// param6 = smear (spreads the offset across multiple samples for a motion-blur look)
fragment float4 effect_channels(VertexOut in [[stage_in]],
                                 texture2d<float> tex [[texture(0)]],
                                 constant EffectParams &p [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    float dist = p.param1 * 0.1;
    float angle = p.param2 * 6.2831853;
    float2 dir = float2(cos(angle), sin(angle));
    float smear = p.param6;

    // Each channel offset by a fraction of `dir * dist`. Red ahead, blue
    // behind, green centered — classic chromatic aberration along an arbitrary axis.
    float2 uvR = in.texCoord + dir * dist;
    float2 uvG = in.texCoord;
    float2 uvB = in.texCoord - dir * dist;

    float4 cR, cG, cB;
    if (smear > 0.001) {
        // 4-tap smear: average a chord of samples along the offset direction
        float step = dist * 0.5;
        cR = (tex.sample(s, uvR) + tex.sample(s, uvR - dir * step)
            + tex.sample(s, uvR - dir * step * 2.0) + tex.sample(s, uvR + dir * step)) * 0.25;
        cG = tex.sample(s, uvG);
        cB = (tex.sample(s, uvB) + tex.sample(s, uvB + dir * step)
            + tex.sample(s, uvB + dir * step * 2.0) + tex.sample(s, uvB - dir * step)) * 0.25;
        // Lerp between sharp and smeared based on `smear`
        cR = mix(tex.sample(s, uvR), cR, smear);
        cB = mix(tex.sample(s, uvB), cB, smear);
    } else {
        cR = tex.sample(s, uvR);
        cG = tex.sample(s, uvG);
        cB = tex.sample(s, uvB);
    }

    return float4(cR.r * p.param3,
                  cG.g * p.param4,
                  cB.b * p.param5,
                  1.0);
}

// MARK: - Displace (value-noise UV displacement)
// Cheap 2D value noise (hash + bilinear) → displaces UV → liquid-like warp.
// param1 = amount (0..1 → 0..15% displacement)
// param2 = noise scale (0..1 → 1..16 cells per screen)
// param3 = speed (animation rate)
// param4 = channel separation (R/G/B sampled at slightly different offsets)
// param5 = octaves (0..1 → 1..4 fractal octaves)
// param6 = direction bias (0 = isotropic, 1 = horizontal-only)
static inline float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static inline float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);     // smoothstep
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fragment float4 effect_displace(VertexOut in [[stage_in]],
                                 texture2d<float> tex [[texture(0)]],
                                 constant EffectParams &p [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    float amp = p.param1 * 0.15;
    float scale = mix(1.0, 16.0, p.param2);
    float speed = p.param3 * 0.5;
    float chanSep = p.param4 * 0.3;
    int octaves = int(round(mix(1.0, 4.0, p.param5)));
    float dirBias = p.param6;

    // Fractal value noise → 2D displacement vector
    float2 q = in.texCoord * scale + p.time * speed;
    float nx = 0.0, ny = 0.0, ampSum = 0.0, w = 1.0;
    for (int i = 0; i < octaves; ++i) {
        nx += valueNoise(q) * w;
        ny += valueNoise(q + float2(31.4, 17.7)) * w;
        ampSum += w;
        q *= 2.0;
        w *= 0.5;
    }
    nx = (nx / ampSum) * 2.0 - 1.0;
    ny = (ny / ampSum) * 2.0 - 1.0;
    // Direction bias: 0 = full 2D, 1 = horizontal-only
    ny *= (1.0 - dirBias);
    float2 disp = float2(nx, ny) * amp;

    if (chanSep > 0.001) {
        float4 cR = tex.sample(s, in.texCoord + disp * (1.0 + chanSep));
        float4 cG = tex.sample(s, in.texCoord + disp);
        float4 cB = tex.sample(s, in.texCoord + disp * (1.0 - chanSep));
        return float4(cR.r, cG.g, cB.b, 1.0);
    }
    return tex.sample(s, in.texCoord + disp);
}

// MARK: - Thermal (FLIR-style false-color heat map)
// param1 = INTENSITY (mix between original and thermal)
// param2 = PALETTE   (0 = Iron, 0.5 = Rainbow/Jet, 1 = White-hot)
// param3 = CONTRAST  (heat curve — 0.5 neutral, <0.5 lifts cold, >0.5 crushes cold)
// param4 = NOISE     (sensor grain)
// param5 = SCAN      (faint horizontal scanline overlay, FLIR display feel)
//
// Maps perceptual luminance to a 5-stop palette using smooth 0..1 ramps.
// Three palettes are blended via PALETTE so a single knob crossfades the
// look from classic Iron through Rainbow to clinical White-hot.

static inline float3 ironLUT(float t) {
    // Black -> deep purple -> red -> orange -> yellow -> white (FLIR Iron).
    float3 c0 = float3(0.0, 0.0, 0.0);
    float3 c1 = float3(0.20, 0.00, 0.40);
    float3 c2 = float3(0.85, 0.10, 0.10);
    float3 c3 = float3(1.00, 0.55, 0.05);
    float3 c4 = float3(1.00, 0.95, 0.30);
    float3 c5 = float3(1.00, 1.00, 1.00);
    if (t < 0.20) return mix(c0, c1, t / 0.20);
    if (t < 0.45) return mix(c1, c2, (t - 0.20) / 0.25);
    if (t < 0.70) return mix(c2, c3, (t - 0.45) / 0.25);
    if (t < 0.90) return mix(c3, c4, (t - 0.70) / 0.20);
    return mix(c4, c5, (t - 0.90) / 0.10);
}

static inline float3 rainbowLUT(float t) {
    // Cold blue -> cyan -> green -> yellow -> red (jet/turbo flavor).
    float3 c0 = float3(0.05, 0.00, 0.35);
    float3 c1 = float3(0.00, 0.55, 0.95);
    float3 c2 = float3(0.05, 0.90, 0.30);
    float3 c3 = float3(0.95, 0.95, 0.05);
    float3 c4 = float3(0.95, 0.05, 0.05);
    if (t < 0.25) return mix(c0, c1, t / 0.25);
    if (t < 0.50) return mix(c1, c2, (t - 0.25) / 0.25);
    if (t < 0.75) return mix(c2, c3, (t - 0.50) / 0.25);
    return mix(c3, c4, (t - 0.75) / 0.25);
}

// Hash for grain — cheap, branchless, no texture lookup.
static inline float thermalHash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

fragment float4 effect_thermal(VertexOut in [[stage_in]],
                                texture2d<float> tex [[texture(0)]],
                                constant EffectParams &p [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 c = tex.sample(s, in.texCoord);

    // Perceptual luminance (Rec. 709). Thermal cameras key off intensity,
    // so the source's color is collapsed to a single heat value.
    float lum = dot(c.rgb, float3(0.2126, 0.7152, 0.0722));

    // CONTRAST shapes the heat curve. 0.5 = neutral (gamma 1.0); below
    // lifts cold detail (gamma <1), above crushes it (gamma >1).
    float gamma = mix(0.4, 2.5, p.param3);
    float heat = pow(clamp(lum, 0.0, 1.0), gamma);

    // PALETTE crossfade: Iron <-> Rainbow <-> White-hot.
    float3 ironCol = ironLUT(heat);
    float3 rainCol = rainbowLUT(heat);
    float3 whiteCol = float3(heat); // monochrome white-hot
    float3 paletteCol;
    if (p.param2 < 0.5) {
        paletteCol = mix(ironCol, rainCol, p.param2 * 2.0);
    } else {
        paletteCol = mix(rainCol, whiteCol, (p.param2 - 0.5) * 2.0);
    }

    // Sensor grain — temporal noise that animates with `time` so it
    // doesn't look like a static dither pattern.
    float n = thermalHash(in.texCoord * float2(1920.0, 1080.0) + p.time * 73.0) - 0.5;
    paletteCol += n * p.param4 * 0.25;

    // FLIR-style display scanline — fine horizontal banding that gets
    // stronger with SCAN.
    float scan = 1.0 - p.param5 * 0.35 * (0.5 + 0.5 * sin(in.texCoord.y * 1080.0 * 3.14159));
    paletteCol *= scan;

    // INTENSITY — blend back toward the original so the user can dial in
    // a partial false-color treatment for layered looks.
    float3 outRGB = mix(c.rgb, clamp(paletteCol, 0.0, 1.0), p.param1);
    return float4(outRGB, c.a);
}
