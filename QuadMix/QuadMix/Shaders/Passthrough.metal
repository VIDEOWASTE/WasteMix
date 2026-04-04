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

// Passthrough with opacity: multiplies rgb by opacity against black background
// Used for rendering channel 0 (base layer) so its fader controls brightness
fragment float4 fragment_passthrough_opacity(VertexOut in [[stage_in]],
                                              texture2d<float> tex [[texture(0)]],
                                              constant BlendUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 color = tex.sample(s, in.texCoord);
    return float4(color.rgb * uniforms.opacity, 1.0);
}

fragment float4 fragment_solid_color(VertexOut in [[stage_in]],
                                      constant float4 &color [[buffer(0)]]) {
    return color;
}

// PIP: renders texture scaled and offset, with opacity.
// scale < 1: PIP window (shrink), pixels outside are transparent
// scale = 1: fullscreen (passthrough)
// scale > 1: overscan/zoom (crops into the image)
fragment float4 fragment_pip(VertexOut in [[stage_in]],
                              texture2d<float> tex [[texture(0)]],
                              constant PIPUniforms &pip [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    float2 uv = in.texCoord;
    float scale = pip.scale;
    float2 offset = float2(pip.offsetX * 0.5, pip.offsetY * 0.5);

    if (scale > 1.0) {
        // Overscan / zoom: scale > 1 means we see less of the source (zoomed in)
        // Remap screen UV to a smaller region of the source texture
        float2 center = float2(0.5) - offset;
        float invScale = 1.0 / scale;
        float2 srcUV = (uv - 0.5) * invScale + center;

        // Clamp to source bounds
        srcUV = clamp(srcUV, float2(0.0), float2(1.0));

        float4 color = tex.sample(s, srcUV);
        return float4(color.rgb * pip.opacity, pip.opacity);
    } else {
        // PIP / shrink: scale < 1 means the image is smaller on screen
        float2 pipCenter = float2(0.5) + offset;
        float2 halfSize = float2(scale * 0.5);
        float2 minBound = pipCenter - halfSize;
        float2 maxBound = pipCenter + halfSize;

        if (uv.x < minBound.x || uv.x > maxBound.x || uv.y < minBound.y || uv.y > maxBound.y) {
            return float4(0, 0, 0, 0);
        }

        float2 srcUV = (uv - minBound) / (maxBound - minBound);
        float4 color = tex.sample(s, srcUV);
        return float4(color.rgb * pip.opacity, pip.opacity);
    }
}
