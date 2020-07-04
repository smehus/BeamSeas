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

kernel void tessellation_main(constant float *edge_factors [[ buffer(0) ]],
                              constant float *inside_factors [[ buffer(1) ]],
                              device MTLQuadTessellationFactorsHalf *factors [[ buffer(2) ]],
                              uint pid [[ thread_position_in_grid ]])
{
    factors[pid].edgeTessellationFactor[0] = edge_factors[0];
    factors[pid].edgeTessellationFactor[1] = edge_factors[0];
    factors[pid].edgeTessellationFactor[2] = edge_factors[0];
    factors[pid].edgeTessellationFactor[3] = edge_factors[0];

    factors[pid].insideTessellationFactor[0] = inside_factors[0];
    factors[pid].insideTessellationFactor[1] = inside_factors[0];
}

[[ patch(quad, 4) ]]
vertex TerrainVertexOut vertex_terrain(patch_control_point<ControlPoint> control_points [[ stage_in ]],
                                float2 patch_coord [[ position_in_patch ]],
                                constant Uniforms &uniforms [[ buffer(BufferIndexUniforms) ]])
{

    float u = patch_coord.x;
    float v = patch_coord.y;

    return {
        .position = float4(u, v, 0, 1),
        .color = float4(u, v, 0, 1)
    };
}

fragment float4 fragment_terrain(TerrainVertexOut fragment_in [[ stage_in ]])
{
    return fragment_in.color;
}
