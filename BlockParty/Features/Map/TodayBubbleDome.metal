//
//  TodayBubbleDome.metal
//  Block Party — the dome bend under a map bubble's glass (TodayBubbles.swift).
//
//  Each point samples the photo nearer the centre (radius^1.35), so the middle swells
//  toward you and the edges compress, like a photo seen through a glass bead. Static:
//  it never moves, so it never shimmers. 1.35 is the softer of the two bends Jesse saw
//  on the mock (1.6 read as a fisheye).
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

[[ stitchable ]] float2 bpDome(float2 position, float2 size) {
    float2 c = size * 0.5;
    float radius = min(c.x, c.y);
    float2 d = (position - c) / radius;
    float r = length(d);
    if (r < 0.0001 || r >= 1.0) { return position; }
    float source = pow(r, 1.35);
    return c + (d / r) * source * radius;
}
