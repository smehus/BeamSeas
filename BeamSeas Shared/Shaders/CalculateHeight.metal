//
//  CalculateHeight.metal
//  BeamSeas
//
//  Created by Scott Mehus on 11/15/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderTypes.h"

kernel void compute_height(constant float3 &position [[ buffer(0) ]],
                           constant float3 *control_points [[ buffer(1) ]],
                           constant TerrainParams &terrainParams [[ buffer(2) ]],
                           constant Uniforms &uniforms [[ buffer(4) ]],
                           texture2d<float> heightMap [[ texture(0) ]],
                           texture2d<float> normalMap [[ texture(2) ]],
                           device float &height_buffer [[ buffer(3) ]],
                           device float3 &normal_buffer [[ buffer(5) ]])
{
    constexpr sampler s(filter::linear, address::repeat);
    float2 xy = ((position.xz + ((terrainParams.size / 16) / 2) / (terrainParams.size / 16)));

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

/*
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

constexpr sampler sample(filter::linear, address::repeat);

float2 xy = ((position.xz + ((terrainParams.size / 16) / 2) / (terrainParams.size / 16)));
out.uv = position.xz;

float3 heightDisplacement = heightMap.sample(sample, xy).xyz;

float3 height = (heightDisplacement * 2 - 1) * terrainParams.height;
float3 horizontalDisplacement = heightDisplacement * 2 - 1;
position.y = height.x;
*/
