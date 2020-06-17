//
//  Shaders.metal
//  BeamSeas Shared
//
//  Created by Scott Mehus on 6/15/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

// File for Metal kernel and shader functions

#include <metal_stdlib>
#include <simd/simd.h>

// Including header shared between this Metal shader code and Swift/C code executing Metal API commands
#import "ShaderTypes.h"

using namespace metal;

struct VertexIn {
    float4 position [[ attribute(VertexAttributePosition) ]];
    float3 normal [[ attribute(VertexAttributeNormal) ]];
};

struct VertexOut {
    float4 position [[ position ]];
    float3 normal;
};

vertex VertexOut vertex_main(const VertexIn vertex_in [[ stage_in ]],
                          constant Uniforms &uniforms [[ buffer(1) ]])
{
    return {
        .position = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix * vertex_in.position,
        .normal = vertex_in.normal
    };
}

fragment float4 fragment_main(VertexOut in [[ stage_in ]])
{
    float4 sky = float4(0.34, 0.9, 1.0, 1.0);
    float4 earth = float4(0.29, 0.58, 0.2, 1.0);
    float intensity = in.normal.y * 0.5 + 0.5; // convert from -1 to 1 : 0 to 1

     return mix(earth, sky, intensity);
}
