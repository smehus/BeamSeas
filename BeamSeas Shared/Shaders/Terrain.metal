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

struct Fuck {
    float4 position [[ attribute(0) ]];
};

struct TerrainVertexOut {
    float4 position [[ position ]];
    float4 color;
    float2 uv;
    float3 normal;
};

kernel void compute_height(constant float3 &position [[ buffer(0) ]])
{

}

// Its this fucking thing - its the patch_control_point thing...
[[ patch(quad, 4) ]]
vertex TerrainVertexOut vertex_terrain(patch_control_point<Fuck> control_points [[ stage_in ]],
                                       float2 patch_coord [[ position_in_patch ]])
{
    TerrainVertexOut out;

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

    return float4(1, 0, 0, 1);
}


float normalCoordinates(uint2 coords, texture2d<float> map, sampler s, float delta)
{

    return 1.0;
}

// This is pulled directly from apples example: DynamicTerrainWithArgumentBuffers
// Should move this to BasicFFT
kernel void TerrainKnl_ComputeNormalsFromHeightmap(texture2d<float> height [[texture(0)]],
                                                   texture2d<float, access::write> normal [[texture(2)]],
                                                   constant TerrainParams &terrain [[ buffer(3) ]],
                                                   constant Uniforms &uniforms [[ buffer(BufferIndexUniforms) ]],
                                                   uint2 tid [[thread_position_in_grid]])
{

}

