#include <metal_stdlib>
using namespace metal;

struct RoomRaster { float4 position [[position]]; float2 uv; };
struct RoomUniforms { float referenceSpeed; float displayMode; float time; float reducedMotion; float4 optics; };

vertex RoomRaster roomVertex(uint index [[vertex_id]]) {
    const float2 vertices[] = { float2(-1,-1), float2(3,-1), float2(-1,3) };
    RoomRaster out;
    out.position = float4(vertices[index],0,1);
    out.uv = (vertices[index] + 1) * 0.5;
    return out;
}

float segmentDistance(float2 p, float2 a, float2 b) {
    float2 ab = b-a;
    return length(p-a-ab*clamp(dot(p-a,ab)/max(dot(ab,ab),0.00001),0.0,1.0));
}

fragment float4 roomFragment(RoomRaster in [[stage_in]],
                            texture2d<float> field [[texture(0)]],
                            constant RoomUniforms &uniforms [[buffer(0)]]) {
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    constexpr sampler nearestSampler(coord::normalized, address::clamp_to_edge, filter::nearest);
    float2 uv = clamp(in.uv,0.0,1.0);
    float4 sample = field.sample(linearSampler,uv);
    float2 cell = float2(field.get_width(),field.get_height());
    float2 texel = 1.0/cell;
    float solid = field.sample(nearestSampler,uv).w;
    float3 midnight = float3(0.018,0.039,0.058);
    float speed = length(sample.xy);
    float normalizedSpeed = clamp(speed/max(uniforms.referenceSpeed,1.0),0.0,2.0)*0.5;
    float3 color;
    if (uniforms.displayMode > 1.5) {
        float4 left = field.sample(linearSampler,uv-float2(texel.x,0));
        float4 right = field.sample(linearSampler,uv+float2(texel.x,0));
        float4 below = field.sample(linearSampler,uv-float2(0,texel.y));
        float4 above = field.sample(linearSampler,uv+float2(0,texel.y));
        float spin = (right.y-left.y)/(2*12.0/cell.x) - (above.x-below.x)/(2*8.0/cell.y);
        float strength = clamp(abs(spin)/max(uniforms.referenceSpeed,1.0),0.0,1.0);
        color = mix(midnight, spin > 0 ? float3(1.0,0.48,0.25) : float3(0.21,0.72,0.95),strength);
    } else if (uniforms.displayMode > 0.5) {
        color = mix(midnight,float3(0.06,0.37,0.48),smoothstep(0.0,0.6,normalizedSpeed));
        color = mix(color,float3(0.92,0.74,0.35),smoothstep(0.5,1.0,normalizedSpeed));
    } else {
        color = midnight + float3(0.045,0.26,0.30)*normalizedSpeed;
        color = mix(color,float3(0.24,0.81,0.88),pow(sample.z,1.3)*0.80);
    }
    // Grid measures the 12 × 8 m room; the vectors come from solved velocities.
    float2 grid = abs(fract(uv*float2(12,8))-0.5);
    float gridLine = 1.0-smoothstep(0.474,0.492,max(grid.x,grid.y));
    color += float3(0.055)* (1-gridLine);
    float2 arrowGrid = float2(14,9);
    float2 centerUV = (floor(uv*arrowGrid)+0.5)/arrowGrid;
    float4 vectorCell = field.sample(linearSampler,centerUV);
    float2 p = (uv-centerUV)*float2(12,8);
    float2 direction = normalize(vectorCell.xy + float2(0.00001,0));
    float arrowLength = min(0.32,length(vectorCell.xy)/max(uniforms.referenceSpeed,1.0)*0.22);
    float2 tail = -direction*arrowLength, tip = direction*arrowLength;
    float2 normal = float2(-direction.y,direction.x);
    float distance = min(segmentDistance(p,tail,tip),
                         min(segmentDistance(p,tip,tip-direction*0.10+normal*0.055),
                             segmentDistance(p,tip,tip-direction*0.10-normal*0.055)));
    float arrow = (1.0-smoothstep(0.008,0.022,distance))*step(0.15,length(vectorCell.xy))*(1-vectorCell.w);
    color = mix(color,float3(0.80,0.96,0.96),arrow*0.65);
    if (solid > 0.5) {
        float neighbor = min(min(field.sample(nearestSampler,uv+float2(texel.x,0)).w,
                                 field.sample(nearestSampler,uv-float2(texel.x,0)).w),
                             min(field.sample(nearestSampler,uv+float2(0,texel.y)).w,
                                 field.sample(nearestSampler,uv-float2(0,texel.y)).w));
        float brushed = 0.022*sin((uv.x+uv.y)*260);
        float glint = pow(0.5+0.5*sin(uv.x*25+uv.y*19+uniforms.optics.x*3-uniforms.optics.y*2),12.0);
        color = float3(0.16,0.22,0.27) + brushed + glint*float3(0.58,0.66,0.69);
        color = mix(color,float3(0.45,0.92,0.97), (1-neighbor)*0.8);
    }
    return float4(color,1);
}
