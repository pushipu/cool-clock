#include <metal_stdlib>
using namespace metal;

struct CloudUniforms { float4 size; uint4 state; };
struct CloudRectangle { float4 bounds; float4 blend; };

vertex float4 cloudVertex(uint id [[vertex_id]]) {
    const float2 positions[] = {float2(-1, -1), float2(3, -1), float2(-1, 3)};
    return float4(positions[id], 0, 1);
}

float3 cloudColor(texture2d<float> first, texture2d<float> second, texture2d<float> alternate,
                  constant uchar4 *luts, uint source, float2 uv) {
    constexpr sampler sampling(coord::normalized, address::clamp_to_edge, filter::linear);
    if (source == 3 || source == 5) uv.x = 1 - uv.x;
    if (source == 4 || source == 6) uv.y = 1 - uv.y;
    float luma = source == 0 ? first.sample(sampling, uv).r
        : (source == 1 || source == 3 || source == 6) ? second.sample(sampling, uv).r
        : alternate.sample(sampling, uv).r;
    uint gray = uint(clamp(rint((luma * 255 - 16) * (255.0 / 219.0)), 0.0, 255.0));
    return float3(luts[gray + (source == 0 ? 0 : 256)].rgb);
}

fragment float4 cloudFragment(float4 position [[position]],
                              constant CloudUniforms &frame [[buffer(0)]],
                              constant CloudRectangle *rectangles [[buffer(1)]],
                              constant uchar4 *luts [[buffer(2)]],
                              texture2d<float> first [[texture(0)]],
                              texture2d<float> second [[texture(1)]],
                              texture2d<float> alternate [[texture(2)]]) {
    float4 choice = float4(frame.state.x, frame.state.x, 0, 0);
    for (uint index = 0; index < frame.state.y; ++index) {
        float4 bounds = rectangles[index].bounds;
        if (position.x >= bounds.x && position.y >= bounds.y && position.x < bounds.z && position.y < bounds.w) {
            choice = rectangles[index].blend;
        }
    }
    float2 uv = (position.xy / frame.size.xy - 0.5) * frame.size.zw + 0.5;
    uint before = uint(choice.x), after = uint(choice.y);
    float3 color = cloudColor(first, second, alternate, luts, before, uv);
    if (before != after && choice.z > 0) {
        color = rint(mix(color, cloudColor(first, second, alternate, luts, after, uv), choice.z));
    }
    return float4(color / 255, 1);
}
