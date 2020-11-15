//
//  Terrain.metal
//  BeamSeas
//
//  Created by Scott Mehus on 7/4/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderTypes.h"

struct ControlPoint {
    float4 position [[ attribute(0) ]];
};

struct TerrainVertexOut {
    float4 position [[ position ]];
    float4 color;
    float2 uv;
    float3 normal;
};

kernel void compute_height(constant float3 &position [[ buffer(0) ]],
                           constant float3 *control_points [[ buffer(1) ]],
                           constant TerrainParams &terrainParams [[ buffer(2) ]],
                           constant Uniforms &uniforms [[ buffer(4) ]],
                           texture2d<float> heightMap [[ texture(0) ]],
                           texture2d<float> normalMap [[ texture(2) ]],
                           device float &height_buffer [[ buffer(3) ]],
                           device float3 &normal_buffer [[ buffer(5) ]])
{
    constexpr sampler s(filter::linear);
    float2 xy = ((position.xz + terrainParams.size / 2) / terrainParams.size);

    // Calculate Height
    float3 mapValue = heightMap.sample(s, xy).xyz;
    float height = ((mapValue * 2 - 1) * terrainParams.height).x;
    height_buffer = height;


    // Calculate Normal
    xy = ((position.xz + terrainParams.size / 2) / terrainParams.size);
    float4 normal = normalMap.sample(s, xy);
    float4 outNormal = normal;//(normal * 2 - 1) * terrainParams.height;
    normal_buffer = outNormal.rgb;//float3(0.75, 0.0, 0);
}

float calc_distance(float3 pointA,
                    float3 pointB,
                    float3 camera_position,
                    float4x4 modelMatrix)
{
    float3 positionA = (modelMatrix * float4(pointA, 1)).xyz;
    float3 positionB = (modelMatrix * float4(pointB, 1)).xyz; float3 midpoint = (positionA + positionB) * 0.5;
    float camera_distance = distance(camera_position, midpoint);
    return camera_distance;
}

kernel void tessellation_main(constant float *edge_factors [[ buffer(0) ]],
                              constant float *inside_factors [[ buffer(1) ]],
                              constant Uniforms &uniforms [[ buffer(BufferIndexUniforms) ]],
                              constant FragmentUniforms &fragmentUniforms [[ buffer(BufferIndexFragmentUniforms) ]],
                              constant TerrainParams &terrainParams [[ buffer(BufferIndexTerrainParams) ]],
                              constant float3 *control_points [[ buffer(BufferIndexControlPoints) ]],
                              device MTLQuadTessellationFactorsHalf *factors [[ buffer(2) ]],
                              uint pid [[ thread_position_in_grid ]])
{
//    uint control_points_per_patch = 4;
//    uint index = pid * control_points_per_patch;
    float totalTessellation = 0;

    for (int i = 0; i < 4; i++) {
        int pointAIndex = i;
        int pointBIndex = i + 1;

        if (pointAIndex == 3) {
            pointBIndex = 0;
        }

        int edgeIndex = pointBIndex;
        // Water seems buzzy if we use this right now
//        float camera_distance = calc_distance(control_points[pointAIndex + index],
//                                              control_points[pointBIndex + index],
//                                              fragmentUniforms.camera_position.xyz,
//                                              uniforms.modelMatrix);

        float tessellation = terrainParams.maxTessellation;// max(4.0, terrainParams.maxTessellation / camera_distance);
        factors[pid].edgeTessellationFactor[edgeIndex] = tessellation;
        totalTessellation += tessellation;
    }

    factors[pid].insideTessellationFactor[0] = totalTessellation * 0.25;
    factors[pid].insideTessellationFactor[1] = totalTessellation * 0.25;
}

float3 terrainDiffuseLighting(float3 normal,
                       float3 position,
                       constant FragmentUniforms &fragmentUniforms,
                       constant Light *lights,
                       float3 baseColor) {
    float3 diffuseColor = 0;
    float3 normalDirection = normalize(normal);
    for (uint i = 0; i < fragmentUniforms.light_count; i++) {
        Light light = lights[i];
        if (light.type == Sunlight) {
            float3 lightDirection = normalize(light.position);
            float diffuseIntensity = saturate(dot(lightDirection, normalDirection));
            diffuseColor += light.color * light.intensity * baseColor * diffuseIntensity;
        } else if (light.type == Pointlight) {
            float d = distance(light.position, position);
            float3 lightDirection = normalize(light.position - position);
            float attenuation = 1.0 / (light.attenuation.x + light.attenuation.y * d + light.attenuation.z * d * d);
            float diffuseIntensity = saturate(dot(lightDirection, normalDirection));
            float3 color = light.color * baseColor * diffuseIntensity;
            color *= attenuation;
            diffuseColor += color;
        } else if (light.type == Spotlight) {
            float d = distance(light.position, position);
            float3 lightDirection = normalize(light.position - position);
            float3 coneDirection = normalize(-light.coneDirection);
            float spotResult = (dot(lightDirection, coneDirection));
            if (spotResult > cos(light.coneAngle)) {
                float attenuation = 1.0 / (light.attenuation.x + light.attenuation.y * d + light.attenuation.z * d * d);
                attenuation *= pow(spotResult, light.coneAttenuation);
                float diffuseIntensity = saturate(dot(lightDirection, normalDirection));
                float3 color = light.color * baseColor * diffuseIntensity;
                color *= attenuation;
                diffuseColor += color;
            }
        }
    }
    return diffuseColor;
}


[[ patch(quad, 4) ]]
vertex TerrainVertexOut vertex_terrain(patch_control_point<ControlPoint> control_points [[ stage_in ]],
                                       float2 patch_coord [[ position_in_patch ]],
                                       texture2d<float> heightMap [[ texture(0) ]],
                                       texture2d<float> normalMap [[ texture(1) ]],
                                       constant TerrainParams &terrainParams [[ buffer(BufferIndexTerrainParams) ]],
                                       uint patchID [[ patch_id ]],
                                       constant Uniforms &uniforms [[ buffer(BufferIndexUniforms) ]])
{
    TerrainVertexOut out;
    float u = patch_coord.x;
    float v = patch_coord.y;
    float2 top = mix(control_points[0].position.xz,
                     control_points[1].position.xz,
                     u);
    float2 bottom = mix(control_points[3].position.xz,
                        control_points[2].position.xz,
                        u);

    float2 interpolated = mix(top, bottom, v);
    float4 position = float4(interpolated.x, 0.0, interpolated.y, 1.0);


    // Changing this to filter linear smoothes out the texture
    // Which ends up smoothing out the rendering
    constexpr sampler sample(filter::linear, address:: repeat);

    float2 xy = ((position.xz + terrainParams.size / 2) / terrainParams.size);
    xy.x += (uniforms.deltaTime * 0.05);
    out.uv = xy;
    // Why was i doing this??
//    xy.y = 1 - xy.y;
//    xy = 1 - xy;
//    xy.x = fmod(xy.x + (uniforms.deltaTime), 1);

//    xy *= terrainParams.size;
//    float3 heightDisplacement = mix(heightMap.sample(sample, xy + 0.5).xyz, heightMap.sample(sample, xy + 1.0).xyz, 0.5);
    float3 heightDisplacement = heightMap.sample(sample, xy).xyz;

//    float inverseColor = color.r;//1 - color.r;
    float3 height = (heightDisplacement * 2 - 1) * terrainParams.height;

    // OHHHHH shit - displacment maps dispalce in the horizontal plane.....
    //Using only a straight heightmap, this is not easy to implement, however, we can have another "displacement" map which computes displacement in the horizontal plane as well. If we compute the inverse Fourier transform of the gradient of the heightmap, we can find a horizontal displacement vector which we will push vertices toward. This gives a great choppy look to the waves.

    // This means not just this y value... but also displacing the patches in the x axies
    // Y & Z values represent the horizontal displacment inside the height map
    // Height displacement would only be between -1 & 1. So we need to modify it somehow to values that
    // are relevant....
    float3 horizontalDisplacement = heightDisplacement * 2 - 1;

//    position.x += (horizontalDisplacement.y);
//    position.z += (horizontalDisplacement.z);
    position.y = height.x;
    

    float adjustedHeight = heightDisplacement.y;
//    adjustedHeight = 1 - adjustedHeight;
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix * position;
    float4 finalColor = float4(heightDisplacement.y, 0, heightDisplacement.z, 1);

    // reference AAPLTerrainRenderer in DynamicTerrainWithArgumentBuffers exmaple: EvaluateTerrainAtLocation line 235 -> EvaluateTerrainAtLocation in AAPLTerrainRendererUtilities line: 91
//    out.normal = uniforms.normalMatrix * primaryLocalNormal;//mix(primaryLocalNormal, secondarLocalNormal, 0.5);

    constexpr sampler normalSampler(min_filter::linear, mag_filter::linear, mip_filter::nearest);
    float3 normalValue = normalize(normalMap.sample(normalSampler, xy).xzy * 2.0f - 1.0f);
    float3 normal = uniforms.normalMatrix * normalValue;

    out.normal = normal;
//    finalColor += float4(0.1, 0.6, 0.988, 1);
    out.color = finalColor;

    return out;
}

fragment float4 fragment_terrain(TerrainVertexOut fragment_in [[ stage_in ]],
                                 constant Light *lights [[ buffer(BufferIndexLights) ]],
                                 constant Uniforms &uniforms [[ buffer(BufferIndexUniforms) ]],
                                 constant TerrainParams &terrainParams [[ buffer(BufferIndexTerrainParams) ]],
                                 constant FragmentUniforms &fragmentUniforms [[ buffer(BufferIndexFragmentUniforms) ]],
                                 texture2d<float> gradientMap [[ texture(0) ]],
                                 texture2d<float> normalMap [[ texture(2) ]])
{


    constexpr sampler sam(min_filter::linear, mag_filter::linear, mip_filter::nearest, address::repeat);
    float3 normalValue = normalMap.sample(sam, fragment_in.uv).xzy;
    float3 vGradJacobian = gradientMap.sample(sam, fragment_in.uv).xyz;
    float3 noise_gradient = 0.3 * normalValue;

    float jacobian = vGradJacobian.z;
    float turbulence = max(2.0 - jacobian + dot(abs(noise_gradient.xy), float2(1.2)), 0.0);

    float color_mod = 1.0  * smoothstep(1.3, 1.8, turbulence);

    float3 color = float3(0.2, 0.6, 1.0);
    float3 specular = terrainDiffuseLighting(uniforms.normalMatrix * (normalValue * 2.0f - 1.0f), fragment_in.position.xyz, fragmentUniforms, lights, color.rgb);
    return float4(specular, 1.0);
//    fragment_in.color.xyz *= 2.0;
//    return fragment_in.color;
}


float normalCoordinates(uint2 coords, texture2d<float> map, sampler s, float delta)
{

    float2 xy = float2(coords.x, coords.y);
    xy.x = fmod(xy.x + delta, 1);
    float4 d = map.sample(s, xy);

    return d.r;
}

// This is pulled directly from apples example: DynamicTerrainWithArgumentBuffers
// Should move this to BasicFFT
kernel void TerrainKnl_ComputeNormalsFromHeightmap(texture2d<float> height [[texture(0)]],
                                                   texture2d<float, access::write> normal [[texture(2)]],
                                                   constant TerrainParams &terrain [[ buffer(3) ]],
                                                   constant Uniforms &uniforms [[ buffer(BufferIndexUniforms) ]],
                                                   uint2 tid [[thread_position_in_grid]])
{
    constexpr sampler sam(min_filter::nearest, mag_filter::nearest, mip_filter::none,
                          address::clamp_to_edge, coord::pixel);



//    constexpr sampler sam(filter::linear);
//    float xz_scale = TERRAIN_SCALE / height.get_width();
    float xz_scale = terrain.size.x / height.get_width();
    float y_scale = terrain.height;

    if (tid.x < height.get_width() && tid.y < height.get_height()) {
        // I think we can just compute the normals once for each map - pass both maps into the vertex shader
        // And mix the two samples. Don't need to do anything else other than handle the mix between maps & fmod something...
//        // Which we're already doing in the vertex shader. So I think we can just add an altNormalMap to the vetex shader & use that for secondary shader

        float h_up     = height.sample(sam, (float2)(tid + uint2(0, 1))).r;
        float h_down   = height.sample(sam, (float2)(tid - uint2(0, 1))).r;
        float h_right  = height.sample(sam, (float2)(tid + uint2(1, 0))).r;
        float h_left   = height.sample(sam, (float2)(tid - uint2(1, 0))).r;
        float h_center = height.sample(sam, (float2)(tid + uint2(0, 0))).r;

        float3 v_up    = float3( 0,        (h_up    - h_center) * y_scale,  xz_scale);
        float3 v_down  = float3( 0,        (h_down  - h_center) * y_scale, -xz_scale);
        float3 v_right = float3( xz_scale, (h_right - h_center) * y_scale,  0);
        float3 v_left  = float3(-xz_scale, (h_left  - h_center) * y_scale,  0);

        float3 n0 = cross(v_up, v_right);
        float3 n1 = cross(v_left, v_up);
        float3 n2 = cross(v_down, v_left);
        float3 n3 = cross(v_right, v_down);

        float3 n = normalize(n0 + n1 + n2 + n3) * 0.5f + 0.5f;

        normal.write(float4(n.xzy, 1), tid);
    }
}

// Original
//kernel void TerrainKnl_ComputeNormalsFromHeightmap(texture2d<float> height [[texture(0)]],
//                                                   texture2d<float, access::write> normal [[texture(1)]],
//                                                   constant TerrainParams &terrain [[ buffer(3) ]],
//                                                   uint2 tid [[thread_position_in_grid]])
//{
//    constexpr sampler sam(min_filter::nearest, mag_filter::nearest, mip_filter::none,
//                          address::clamp_to_edge, coord::pixel);
//
////    float xz_scale = TERRAIN_SCALE / height.get_width();
//    float xz_scale = terrain.size.x / height.get_width();
//    float y_scale = terrain.height;
//
//    if (tid.x < height.get_width() && tid.y < height.get_height()) {
//        float h_up     = height.sample(sam, (float2)(tid + uint2(0, 1))).r;
//        float h_down   = height.sample(sam, (float2)(tid - uint2(0, 1))).r;
//        float h_right  = height.sample(sam, (float2)(tid + uint2(1, 0))).r;
//        float h_left   = height.sample(sam, (float2)(tid - uint2(1, 0))).r;
//        float h_center = height.sample(sam, (float2)(tid + uint2(0, 0))).r;
//
//        float3 v_up    = float3( 0,        (h_up    - h_center) * y_scale,  xz_scale);
//        float3 v_down  = float3( 0,        (h_down  - h_center) * y_scale, -xz_scale);
//        float3 v_right = float3( xz_scale, (h_right - h_center) * y_scale,  0);
//        float3 v_left  = float3(-xz_scale, (h_left  - h_center) * y_scale,  0);
//
//        float3 n0 = cross(v_up, v_right);
//        float3 n1 = cross(v_left, v_up);
//        float3 n2 = cross(v_down, v_left);
//        float3 n3 = cross(v_right, v_down);
//
//        float3 n = normalize(n0 + n1 + n2 + n3) * 0.5f + 0.5f;
//
//        normal.write(float4(n.xzy, 1), tid);
//    }
//}
