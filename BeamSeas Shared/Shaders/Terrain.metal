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
    float3 normal;// [[flat]];
};

kernel void compute_height(constant float3 &position [[ buffer(0) ]],
                           constant float3 *control_points [[ buffer(1) ]],
                           constant TerrainParams &terrain [[ buffer(2) ]],
                           device float &height_buffer [[ buffer(3) ]],
                           constant Uniforms &uniforms [[ buffer(4) ]],
                           texture2d<float> heightMap [[ texture(0) ]],
                           texture2d<float> altHeightMap [[ texture(1) ]],
                           texture2d<float> normalMap [[ texture(2) ]],
                           texture2d<float> secondaryNormalMap [[ texture(3) ]],
                           device float3 &normal_buffer [[ buffer(5) ]])
{
    uint total = terrain.numberOfPatches * 4; // 4 points per patch
    for (uint i = 0; i < total; i += 4) {
        float3 topLeft = control_points[i];
        float3 topRight = control_points[i + 1];
        float3 bottomRight = control_points[i + 2];
        float3 bottomLeft = control_points[i + 3];

        bool insideTopLeft = position.x >= topLeft.x && position.z <= topLeft.z;
        bool insideTopRight = position.x <= topRight.x && position.z <= topRight.z;
        bool insideBottomRight = position.x <= bottomRight.x && position.z >= bottomRight.z;
        bool insideBottomLeft = position.x >= bottomLeft.x && position.z >= bottomLeft.z;

        if (insideTopLeft && insideBottomLeft && insideTopRight && insideBottomRight) {
            // Can push the boat up or down rather than hard setting the value
            // Might turn out physicsy

            // Player percentage position between control points
            float u = (position.x - topLeft.x) / (topRight.x - topLeft.x);
            float v = (position.z - bottomLeft.z) / (topLeft.z - bottomLeft.z);
            float2 top = mix(topLeft.xz,
                             topRight.xz,
                             u);
            float2 bottom = mix(bottomLeft.xz,
                                bottomRight.xz,
                                u);

            float2 interpolated = mix(top, bottom, v);
            float4 interpolatedPosition = float4(interpolated.x, 0.0, interpolated.y, 1.0);


            constexpr sampler sample(filter::linear);

            // primary
            float2 xy = ((interpolatedPosition.xz + terrain.size / 2) / terrain.size);
            xy.x = fmod(xy.x + uniforms.deltaTime, 1);
            float4 primaryColor = heightMap.sample(sample, xy);
            float4 primaryNormal = normalMap.sample(sample, xy);


            // /secondary
            xy = ((interpolatedPosition.xz + terrain.size / 2) / terrain.size);
            xy.x = fmod(xy.x + (uniforms.deltaTime / 2), 1);
            float4 secondaryColor = altHeightMap.sample(sample, xy);
            float4 secondaryNormal = secondaryNormalMap.sample(sample, xy);

            normal_buffer = mix(primaryNormal, secondaryNormal, 0.5).rgb;
            float4 color = mix(primaryColor, secondaryColor, 0.5);
            float inverseColor = 1 - color.r;
            float height = (inverseColor * 2 - 1) * terrain.height;
            float delta = height - height_buffer;


            if (delta < 0) {
                height_buffer += (delta * 0.5);
            } else {
                height_buffer += (delta * 0.05);
            }

            return;
        }
    }

    height_buffer = -10;
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
                                       texture2d<float> altHeightMap [[ texture(1) ]],
                                       texture2d<float> normalMap [[ texture(2) ]],
                                       texture2d<float> secondaryNormalMap [[ texture(3) ]],
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
    constexpr sampler sample(filter::linear);
    constexpr sampler normalSampler(min_filter::linear, mag_filter::linear);


    // Can i just combine the two textures so I don't have to do this big dance
    float2 xy = ((position.xz + terrainParams.size / 2) / terrainParams.size);
    xy.x = fmod(xy.x + (uniforms.deltaTime), 1);
    float4 primaryColor = heightMap.sample(sample, xy);
    float3 primaryLocalNormal = normalize(normalMap.sample(normalSampler, xy).xzy * 2.0f - 1.0f);

    xy = ((position.xz + terrainParams.size / 2) / terrainParams.size);
    xy.x = fmod(xy.x + (uniforms.deltaTime / 2), 1);
    float4 secondaryColor = altHeightMap.sample(sample, xy);
    float3 secondarLocalNormal = normalize(secondaryNormalMap.sample(normalSampler, xy).xzy * 2.0f - 1.0f);

    float4 color = mix(primaryColor, secondaryColor, 0.5);
    float inverseColor = 1 - color.r;
    float height = (inverseColor * 2 - 1) * terrainParams.height;
    position.y = height;


    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix * position;
    float4 finalColor = float4(inverseColor, inverseColor, inverseColor, 1);

    // reference AAPLTerrainRenderer in DynamicTerrainWithArgumentBuffers exmaple: EvaluateTerrainAtLocation line 235 -> EvaluateTerrainAtLocation in AAPLTerrainRendererUtilities line: 91
    out.normal = uniforms.normalMatrix * mix(primaryLocalNormal, secondarLocalNormal, 0.5);

    finalColor += float4(0.2, 0.6, 0.7, 1);
    out.color = finalColor;

    return out;
}

fragment float4 fragment_terrain(TerrainVertexOut fragment_in [[ stage_in ]],
                                 constant Light *lights [[ buffer(BufferIndexLights) ]],
                                 constant FragmentUniforms &fragmentUniforms [[ buffer(BufferIndexFragmentUniforms) ]])
{

    float3 d = terrainDiffuseLighting(fragment_in.normal, fragment_in.position.xyz, fragmentUniforms, lights, fragment_in.color.rgb);
    return float4(d, 1);
}


float normalCoordinates(uint2 coords, texture2d<float> map, sampler s, float delta)
{

    float2 xy = float2(coords.x, coords.y);
    xy.x = fmod(xy.x + delta, 1);
    float4 d = map.sample(s, xy);

    return d.r;
}


// This is pulled directly from apples example: DynamicTerrainWithArgumentBuffers
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
        // Which we're already doing in the vertex shader. So I think we can just add an altNormalMap to the vetex shader & use that for secondary shader
        float h_up     = height.sample(sam, (float2)(tid + uint2(0, 1))).r;
        float h_down   = height.sample(sam, (float2)(tid - uint2(0, 1))).r;
        float h_right  = height.sample(sam, (float2)(tid + uint2(1, 0))).r;
        float h_left   = height.sample(sam, (float2)(tid - uint2(1, 0))).r;
        float h_center = height.sample(sam, (float2)(tid + uint2(0, 0))).r;

        float3 v_up    = float3( 0,        (h_up    - h_center) * y_scale,  xz_scale);
        float3 v_down  = float3( 0,        (h_down  - h_center) * y_scale, -xz_scale);
        // switched h_right & h_center to accomodate for map weirdness
        float3 v_right = float3( xz_scale, (h_center - h_right) * y_scale,  0);
        float3 v_left  = float3(-xz_scale, (h_center - h_left) * y_scale,  0);

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
