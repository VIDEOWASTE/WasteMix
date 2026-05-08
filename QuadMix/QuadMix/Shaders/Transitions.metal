#include <metal_stdlib>
using namespace metal;

#include "ShaderTypes.h"

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

/// Compute wipe mask for a given UV and progress/direction.
/// Returns 0.0 where the "A" source shows, 1.0 where "B" source shows.
inline float wipeMask(float2 uv, float progress, int direction) {
    float edge = 0.015;
    float mask = 0.0;

    if (direction == 0) {
        // Wipe Left: B reveals from left
        mask = smoothstep(progress - edge, progress + edge, 1.0 - uv.x);
    } else if (direction == 1) {
        // Wipe Right: B reveals from right
        mask = smoothstep(progress - edge, progress + edge, uv.x);
    } else if (direction == 2) {
        // Wipe Up: B reveals from top
        mask = smoothstep(progress - edge, progress + edge, 1.0 - uv.y);
    } else if (direction == 3) {
        // Wipe Down: B reveals from bottom
        mask = smoothstep(progress - edge, progress + edge, uv.y);
    } else if (direction == 4) {
        // Diagonal Top-Left
        float d = (uv.x + uv.y) * 0.5;
        mask = smoothstep(progress - edge, progress + edge, d);
    } else if (direction == 5) {
        // Diagonal Top-Right
        float d = ((1.0 - uv.x) + uv.y) * 0.5;
        mask = smoothstep(progress - edge, progress + edge, d);
    } else if (direction == 6) {
        // Circle / Iris
        float2 center = float2(0.5, 0.5);
        float dist = length(uv - center) / 0.7071;
        mask = smoothstep(progress - edge, progress + edge, 1.0 - dist);
    } else if (direction == 7) {
        // Diamond
        float2 center = float2(0.5, 0.5);
        float dist = (abs(uv.x - center.x) + abs(uv.y - center.y));
        mask = smoothstep(progress - edge, progress + edge, 1.0 - dist);
    } else if (direction == 8) {
        // Blinds
        float slats = 8.0;
        float slat = fract(uv.x * slats);
        mask = smoothstep(progress - edge, progress + edge, slat);
    } else if (direction == 9) {
        // Star wipe: sharp 5-pointed star, point up + 20deg CW
        // At progress=0 nothing revealed, at progress=1 entire screen revealed
        float2 center = float2(0.5, 0.5);
        float2 d = uv - center;
        float angle = atan2(d.y, d.x) + M_PI_F / 2.0 + 20.0 * M_PI_F / 180.0;
        float radius = length(d);

        // Star shape in polar coords. Within each wedge of half-width
        // `wedge = π/5`, the star edge is the straight segment from the
        // apex at (outerR, 0) to the valley at (innerR·cos(wedge),
        // innerR·sin(wedge)). The radial distance to that segment at
        // polar angle `a` (measured from the apex axis) follows from the
        // line's polar equation, giving:
        //   r(a) = (innerR·sin(wedge))
        //        / (innerR·sin(wedge)·cos(a) + (outerR − innerR·cos(wedge))·sin|a|)
        // r(0) = outerR (apex), r(±wedge) = innerR (valley) — both verified.
        float wedge = M_PI_F / 5.0;
        float a = fmod(angle + 20.0 * M_PI_F, 2.0 * wedge) - wedge;
        float aAbs = abs(a);
        float outerR = 1.0;
        float innerR = 0.38;
        float sinW = sin(wedge);
        float cosW = cos(wedge);
        float denom = innerR * sinW * cos(a) + (outerR - innerR * cosW) * sin(aAbs);
        float starR = (innerR * sinW) / max(denom, 1e-6);

        // Distance along star shape, normalized so boundary = 1
        float starDist = radius / starR;

        // The farthest corner is at 0.707 from center. The minimum starR
        // (at valleys) is innerR = 0.38, so max starDist ≈ 1.86. Scale
        // progress 0→1 to cover the full range, with a small overshoot.
        float threshold = progress * 2.0;
        mask = smoothstep(threshold - edge * 3.0, threshold + edge * 3.0, starDist);
        mask = 1.0 - mask; // invert: inside star = revealed
    }

    return mask;
}

/// Two-input wipe: spatial cut between base (A) and layer (B).
/// At progress=0, output is 100% A. At progress=1, output is 100% B.
/// The wipe pattern determined by direction spatially transitions between them.
fragment float4 transition_wipe_ab(VertexOut in [[stage_in]],
                                    texture2d<float> base [[texture(0)]],
                                    texture2d<float> layer [[texture(1)]],
                                    constant TransitionUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 a = base.sample(s, in.texCoord);
    float4 b = layer.sample(s, in.texCoord);

    float mask = wipeMask(in.texCoord, u.progress, u.direction);

    // Hard spatial cut: where mask=0 show A, where mask=1 show B
    return float4(mix(a.rgb, b.rgb, mask), 1.0);
}

/// Single-input wipe (for base layer wiping in from black)
fragment float4 transition_wipe(VertexOut in [[stage_in]],
                                 texture2d<float> input [[texture(0)]],
                                 constant TransitionUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 color = input.sample(s, in.texCoord);
    float mask = wipeMask(in.texCoord, u.progress, u.direction);
    return float4(color.rgb * mask, 1.0);
}

