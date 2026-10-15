#include <metal_stdlib>
using namespace metal;

struct GearVertex {
    float4 position;
    float4 normal;
    float4 detail;
};
struct GearSceneUniforms {
    float4x4 viewProjection;
    float4x4 model;
    float4 cameraAndTime;
    float4 tiltAndAspect;
    float4 material;
    float4 features;
};
struct GearRaster {
    float4 position [[position]];
    float3 world;
    float3 normal;
    float3 local;
    float detail;
};

vertex GearRaster gearVertex(uint index [[vertex_id]],
                            constant GearVertex *vertices [[buffer(0)]],
                            constant GearSceneUniforms &u [[buffer(1)]]) {
    GearRaster out;
    float4 world = u.model * vertices[index].position;
    out.position = u.viewProjection * world;
    out.world = world.xyz;
    out.normal = normalize((u.model * float4(vertices[index].normal.xyz, 0)).xyz);
    out.local = vertices[index].position.xyz;
    out.detail = vertices[index].detail.x;
    return out;
}

float gearSoftBox(float3 ray, float azimuth, float elevation, float width, float height) {
    float angle = atan2(ray.x, ray.z);
    float vertical = asin(clamp(ray.y, -1.0f, 1.0f));
    float horizontalDistance = abs(atan2(sin(angle - azimuth), cos(angle - azimuth)));
    float horizontal = 1.0f - smoothstep(width * 0.75f, width, horizontalDistance);
    float top = 1.0f - smoothstep(height * 0.65f, height, abs(vertical - elevation));
    return horizontal * top;
}
float3 gearStudio(float3 ray, float roughness, float2 tilt) {
    // Procedural studio luminaires, sampled by the actual reflected viewing ray.
    // Moving the phone moves the studio strips instead of swapping pre-baked textures.
    ray = normalize(ray + float3(tilt.x * 0.30f, -tilt.y * 0.27f, 0));
    float spread = roughness * 0.40f;
    float sky = smoothstep(-0.8f, 0.9f, ray.y);
    float3 colour = mix(float3(0.014f, 0.023f, 0.044f), float3(0.23f, 0.30f, 0.40f), sky);
    colour += float3(1.9f, 2.05f, 2.25f) * gearSoftBox(ray, -0.68f, 0.34f, 0.14f + spread, 0.9f);
    colour += float3(1.50f, 1.65f, 1.85f) * gearSoftBox(ray, 0.67f, 0.54f, 0.18f + spread, 0.75f);
    colour += float3(0.8f, 0.98f, 1.1f) * gearSoftBox(ray, 2.2f, 0.2f, 0.10f + spread, 0.9f);
    colour += float3(0.22f, 0.75f, 0.9f) * gearSoftBox(ray, -1.8f, 0.0f, 0.07f + spread, 0.8f);
    colour += float3(0.48f, 0.19f, 0.72f) * gearSoftBox(ray, 1.4f, -0.35f, 0.06f + spread, 0.75f);
    float ceiling = 1.0f - smoothstep(0.05f + spread, 0.22f + spread, abs(ray.y - 0.82f));
    colour += ceiling * float3(0.65f, 0.69f, 0.76f);
    return colour;
}

fragment float4 gearFragment(GearRaster in [[stage_in]],
                             constant GearSceneUniforms &u [[buffer(1)]]) {
    const float hologram = u.features.y;
    const float surface = u.features.z;
    if (surface > 1.5f) {
        float pulse = 0.72f + 0.20f * sin(in.world.z * 7.0f + in.world.x * 3.0f);
        return float4(u.material.rgb * (hologram > 0.5f ? 1.6f : pulse), 1);
    }
    if (surface > 0.5f) {
        float2 coord = in.world.xz * 4.0f;
        float2 derivatives = max(fwidth(coord), float2(0.0001f));
        float2 lines = abs(fract(coord - 0.5f) - 0.5f) / derivatives;
        float grid = 1.0f - saturate(min(lines.x, lines.y));
        float2 coarse = in.world.xz;
        float2 coarseLines = abs(fract(coarse - 0.5f) - 0.5f) / max(fwidth(coarse), float2(0.0001f));
        float major = 1.0f - saturate(min(coarseLines.x, coarseLines.y));
        float fade = exp(-length(in.world.xz) * 0.32f);
        float radial = abs(fract(length(in.world.xz) * 2.0f) - 0.5f);
        float circle = 1.0f - smoothstep(0.002f, 0.014f, radial);
        float3 bed = u.material.rgb * (0.50f + fade * 0.60f);
        bed += float3(0.014f, 0.040f, 0.058f) * (grid * 0.45f + major * 0.8f + circle * 0.25f) * fade;
        float contact = exp(-dot(in.world.xz, in.world.xz) * 1.8f) * 0.46f;
        return float4(bed * (1.0f - contact), 1);
    }
    float3 n = normalize(in.normal);
    float3 v = normalize(u.cameraAndTime.xyz - in.world);
    if (dot(n, v) < 0) n = -n;
    // Concentric machining marks perturb the surface normal, so they affect specular
    // reflection as well as tint. They stay attached to the rotating gear face.
    float radius = length(in.local.xy);
    float theta = atan2(in.local.y, in.local.x);
    if (in.detail > 0.9f && radius > 0.001f) {
        float3 localTangent = float3(in.local.xy / radius, 0);
        float grain = sin(radius * 530.0f) * 0.017f + sin(theta * 180.0f) * 0.005f;
        float3 worldTangent = normalize((u.model * float4(localTangent, 0)).xyz);
        n = normalize(n + worldTangent * grain);
    }
    float ndv = saturate(dot(n, v));
    float roughness = u.material.a;
    float3 ray = reflect(-v, n);
    float3 environment = gearStudio(ray, roughness, u.tiltAndAspect.xy);
    float3 f0 = u.material.rgb * 0.82f;
    float3 fresnel = f0 + (1.0f - f0) * pow(1.0f - ndv, 5.0f);
    float3 colour = environment * fresnel;
    colour += u.material.rgb * (0.08f + 0.15f * max(n.y, 0.0f));
    float3 light = normalize(float3(-2.4f, 4.4f, 3.5f) - in.world);
    float3 halfRay = normalize(light + v);
    float shine = pow(saturate(dot(n, halfRay)), mix(230.0f, 40.0f, roughness));
    colour += float3(2.1f, 2.15f, 2.25f) * shine;
    float edge = pow(1.0f - ndv, 2.9f);
    float spectrumPhase = ndv * 13.0f + radius * 1.8f + u.tiltAndAspect.x * 2.3f - u.tiltAndAspect.y * 2.0f;
    float3 iridescence = 0.5f + 0.5f * cos(spectrumPhase + float3(0.0f, 2.1f, 4.2f));
    iridescence = mix(float3(0.05f, 0.48f, 0.70f), iridescence, 0.38f);
    colour += iridescence * edge * (0.33f + hologram * 0.5f);
    if (hologram > 0.5f) {
        float scan = pow(0.5f + 0.5f * sin(in.world.y * 90.0f), 16.0f);
        float tracer = pow(0.5f + 0.5f * sin(radius * 68.0f), 24.0f);
        colour = mix(colour, float3(0.018f, 0.12f, 0.19f), 0.10f);
        colour += float3(0.10f, 0.65f, 0.92f) * (edge * 0.35f + scan * 0.035f + tracer * 0.025f);
    }
    // Prevent tiny subpixel grooves from becoming unbounded HDR sparkles.
    return float4(min(colour, float3(4.0f)), 1);
}

struct GearOpticsUniforms {
    float4 optics;   // roll, pitch, phase, aspect
    float4 settings; // hologram, reduced motion, reduce transparency, exploded
    float4 viewport;
};
struct GearScreenRaster {
    float4 position [[position]];
    float2 uv;
};
vertex GearScreenRaster gearOpticsVertex(uint index [[vertex_id]]) {
    float2 positions[] = {float2(-1, -1), float2(3, -1), float2(-1, 3)};
    GearScreenRaster out;
    out.position = float4(positions[index], 0, 1);
    out.uv = float2((positions[index].x + 1) * 0.5f, (1 - positions[index].y) * 0.5f);
    return out;
}
float3 gearToneMap(float3 c) {
    c = max(c, 0.0f);
    c = (c * (2.51f * c + 0.03f)) / (c * (2.43f * c + 0.59f) + 0.14f);
    return pow(saturate(c), float3(1.0f / 2.2f));
}
fragment float4 gearOpticsFragment(GearScreenRaster in [[stage_in]],
                                   texture2d<float> scene [[texture(0)]],
                                   constant GearOpticsUniforms &u [[buffer(0)]]) {
    constexpr sampler linearClamp(filter::linear, address::clamp_to_edge);
    float2 uv = in.uv;
    float3 colour = scene.sample(linearClamp, uv).rgb;
    if (u.settings.z < 0.5f) {
        // A shallow curved optical cover. These are refracted texture lookups, not a
        // gradient laid over the picture: Snell's law shifts the scene behind the glass.
        float2 centred = uv - 0.5f;
        float2 q = abs(centred) - float2(0.452f, 0.421f);
        float sdf = length(max(q, 0.0f)) + min(max(q.x, q.y), 0.0f) - 0.022f;
        float lens = 1.0f - smoothstep(-0.003f, 0.003f, sdf);
        float2 phone = u.optics.xy;
        float3 normal = normalize(float3(centred * float2(0.45f, 0.32f)
                                        + phone * float2(0.22f, -0.22f), 1));
        float thickness = 0.18f * max(0.16f, 1.0f - dot(centred * 1.5f, centred * 1.5f));
        float3 redRay = refract(float3(0, 0, -1), normal, 1.0f / 1.46f);
        float3 greenRay = refract(float3(0, 0, -1), normal, 1.0f / 1.49f);
        float3 blueRay = refract(float3(0, 0, -1), normal, 1.0f / 1.52f);
        float2 redOffset = redRay.xy / max(0.1f, -redRay.z) * thickness;
        float2 greenOffset = greenRay.xy / max(0.1f, -greenRay.z) * thickness;
        float2 blueOffset = blueRay.xy / max(0.1f, -blueRay.z) * thickness;
        float3 through = float3(scene.sample(linearClamp, uv + redOffset).r,
                               scene.sample(linearClamp, uv + greenOffset).g,
                               scene.sample(linearClamp, uv + blueOffset).b);
        colour = mix(colour, through, lens);
        float rim = exp(-abs(sdf) * 360.0f);
        float rimLight = 0.13f + 0.30f * pow(saturate(dot(normal, normalize(float3(-0.4f + phone.x,
                                                                                  0.7f - phone.y, 0.4f)))), 5.0f);
        float3 prism = 0.5f + 0.5f * cos(float3(0, 2, 4) + (centred.x + centred.y) * 9.0f + phone.x * 3.0f);
        colour += rim * rimLight * mix(float3(0.43f, 0.66f, 0.80f), prism, 0.26f);
        // The cover catches a small moving softbox streak at grazing incidence.
        float streak = exp(-pow((centred.x + centred.y * 0.58f - 0.27f - phone.x * 0.17f + phone.y * 0.12f) * 100, 2.0f));
        colour += float3(0.11f, 0.16f, 0.20f) * streak * lens * 0.10f;
    }
    float vignette = 1.0f - smoothstep(0.42f, 0.90f, length((uv - 0.5f) * float2(1, 0.86f))) * 0.34f;
    colour *= vignette;
    return float4(gearToneMap(colour), 1);
}
