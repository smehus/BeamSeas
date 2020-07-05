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
};

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
    uint control_points_per_patch = 4;
    uint index = pid * control_points_per_patch;
    float totalTessellation = 0;

    for (int i = 0; i < 4; i++) {
        int pointAIndex = i;
        int pointBIndex = i + 1;

        if (pointAIndex == 3) {
            pointBIndex = 0;
        }

        int edgeIndex = pointBIndex;
        float camera_distance = calc_distance(control_points[pointAIndex + index],
                                              control_points[pointBIndex + index],
                                              fragmentUniforms.camera_position.xyz,
                                              uniforms.modelMatrix);

        float tessellation = terrainParams.maxTessellation;// max(4.0, terrainParams.maxTessellation / camera_distance);
        factors[pid].edgeTessellationFactor[edgeIndex] = tessellation;
        totalTessellation += tessellation;
    }

    factors[pid].insideTessellationFactor[0] = totalTessellation * 0.25;
    factors[pid].insideTessellationFactor[1] = totalTessellation * 0.25;
}

[[ patch(quad, 4) ]]
vertex TerrainVertexOut vertex_terrain(patch_control_point<ControlPoint> control_points [[ stage_in ]],
                                       float2 patch_coord [[ position_in_patch ]],
                                       texture2d<float> heightMap [[ texture(0) ]],
                                       constant float &timer [[ buffer(6) ]],
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


    float2 xy = ((position.xz + terrainParams.size / 2) / terrainParams.size);
    xy.x = fmod(xy.x + timer, 1);

    constexpr sampler sample;
    float4 color = heightMap.sample(sample, xy);
    float height = (color.r * 2 - 1) * terrainParams.height;
    position.y = height;


    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix * position;
    out.color = color.r;


    return out;
}

fragment float4 fragment_terrain(TerrainVertexOut fragment_in [[ stage_in ]])
{
    return fragment_in.color;
}
