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
