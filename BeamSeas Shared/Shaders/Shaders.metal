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
#import "../ShaderTypes.h"

using namespace metal;

struct VertexIn {
    float4 position [[ attribute(0) ]];
};

vertex float4 vertex_main(const VertexIn vertex_in [[ stage_in ]])
{
    return vertex_in.position;
}


fragment float4 fragment_main()
{
    return float4(1, 0, 0, 1);
}
