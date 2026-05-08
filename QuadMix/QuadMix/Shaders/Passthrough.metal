#include <metal_stdlib>
using namespace metal;

#include "ShaderTypes.h"

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertex_passthrough(uint vertexID [[vertex_id]],
                                     constant VertexIn *vertices [[buffer(0)]]) {
    VertexOut out;
    out.position = float4(vertices[vertexID].position, 0.0, 1.0);
    out.texCoord = vertices[vertexID].texCoord;
    return out;
}

fragment float4 fragment_passthrough(VertexOut in [[stage_in]],
                                      texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    return tex.sample(s, in.texCoord);
}

// Passthrough with opacity: multiplies rgb by opacity against black background.
// Used for rendering channel 0 (base layer) so its fader controls brightness.
// Multiplied by `color.a` so keyed-out pixels (luma/chroma key set alpha to 0)
// render as black instead of the original color — matches the cleared black
// canvas the base layer is painted onto.
fragment float4 fragment_passthrough_opacity(VertexOut in [[stage_in]],
                                              texture2d<float> tex [[texture(0)]],
                                              constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 color = tex.sample(s, in.texCoord);
    return float4(color.rgb * uniforms.opacity * color.a, 1.0);
}

fragment float4 fragment_solid_color(VertexOut in [[stage_in]],
                                      constant float4 &color [[buffer(0)]]) {
    return color;
}

// Source-framing transform: rotates the source by 0/90/180/270° and either
// letterboxes (fit) or edge-crops (fill) it onto the target canvas. Inverse
// mapping — for every output pixel we compute the source UV, sampling black
// for fit-mode pixels that fall outside the source rectangle.
fragment float4 fragment_transform(VertexOut in [[stage_in]],
                                    texture2d<float> tex [[texture(0)]],
                                    constant TransformUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    float cs = cos(u.rotationRadians);
    float sn = sin(u.rotationRadians);

    // Stretch: ignore source aspect; map full target to full source after
    // rotation. With rotation=0 this is a pure passthrough; with 90/270
    // it rotates and stretches to fill (e.g. portrait phone rotated 90
    // becomes a clean fullscreen with no bars).
    if (u.fillMode == 2) {
        float2 cn = in.texCoord - 0.5;
        float2 src = float2(cn.x * cs + cn.y * sn,
                           -cn.x * sn + cn.y * cs);
        return tex.sample(s, clamp(src + 0.5, float2(0.0), float2(1.0)));
    }

    // 1. Centered output position in target-physical units (target height = 1,
    //    target width = targetAspect).
    float2 c = in.texCoord - 0.5;
    c.x *= u.targetAspect;

    // 2. Inverse-rotate into the source's pre-rotation frame.
    float2 srcPre = float2(c.x * cs + c.y * sn,
                          -c.x * sn + c.y * cs);

    // 3. Effective source bounding-box on target (pre-scale, target_h = 1).
    bool quarter = (abs(sn) > 0.5);
    float effW = quarter ? 1.0          : u.sourceAspect;
    float effH = quarter ? u.sourceAspect : 1.0;

    // 4. Fit/fill scale.
    float fitScale  = min(u.targetAspect / effW, 1.0 / effH);
    float fillScale = max(u.targetAspect / effW, 1.0 / effH);
    float scale = (u.fillMode == 1) ? fillScale : fitScale;

    // 5. Source's pre-rotation display extent on target (post-scale).
    float dispW = u.sourceAspect * scale;
    float dispH = 1.0 * scale;

    // 6. Pre-rotation source position → source UV.
    float2 srcUV = float2(srcPre.x / dispW, srcPre.y / dispH) + 0.5;

    // 7. Letterbox black for fit-mode out-of-bounds.
    if (u.fillMode == 0 && (srcUV.x < 0.0 || srcUV.x > 1.0 ||
                            srcUV.y < 0.0 || srcUV.y > 1.0)) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    // Fill mode clamps via the sampler; fit-mode in-bounds samples normally.
    return tex.sample(s, clamp(srcUV, float2(0.0), float2(1.0)));
}

// PIP: renders texture scaled, offset, and rotated, with opacity.
// scale < 1: PIP window (shrink), pixels outside are transparent
// scale = 1: fullscreen (passthrough; rotation still applies)
// scale > 1: overscan/zoom (crops into the image)
//
// Rotation operates in canvas-aspect-corrected space so the PIP rectangle
// keeps its visual shape when rotated rather than shearing on a 16:9 canvas.
fragment float4 fragment_pip(VertexOut in [[stage_in]],
                              texture2d<float> tex [[texture(0)]],
                              constant PIPUniforms &pip [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    float2 uv = in.texCoord;
    float scale = pip.scale;
    float2 offset = float2(pip.offsetX * 0.5, pip.offsetY * 0.5);

    // Rotation pivot is the PIP center on canvas. Aspect-correct so a
    // rotated square stays a square instead of skewing.
    float aspect = pip.targetAspect;
    float cs = cos(-pip.rotationRadians);
    float sn = sin(-pip.rotationRadians);

    if (scale > 1.0) {
        // Overscan / zoom: pivot rotation around screen center.
        float2 c = (uv - 0.5);
        c.x *= aspect;
        float2 cr = float2(c.x * cs - c.y * sn, c.x * sn + c.y * cs);
        cr.x /= aspect;

        float2 center = float2(0.5) - offset;
        float invScale = 1.0 / scale;
        float2 srcUV = cr * invScale + center;

        srcUV = clamp(srcUV, float2(0.0), float2(1.0));

        float4 color = tex.sample(s, srcUV);
        return float4(color.rgb * pip.opacity, pip.opacity * color.a);
    } else {
        // PIP / shrink: rotate the small rectangle around its own center
        // (pipCenter), in aspect-corrected space.
        float2 pipCenter = float2(0.5) + offset;

        float2 c = (uv - pipCenter);
        c.x *= aspect;
        float2 cr = float2(c.x * cs - c.y * sn, c.x * sn + c.y * cs);
        cr.x /= aspect;

        // Rectangle bounds in pivot-relative coords: ±scale/2.
        float halfSize = scale * 0.5;
        if (cr.x < -halfSize || cr.x > halfSize || cr.y < -halfSize || cr.y > halfSize) {
            return float4(0, 0, 0, 0);
        }

        float2 srcUV = (cr + halfSize) / scale;
        float4 color = tex.sample(s, srcUV);
        return float4(color.rgb * pip.opacity, pip.opacity * color.a);
    }
}
