//
//  WorldMap.metal
//  BeamSeas
//
//  Created by Scott Mehus on 6/28/21.
//  Copyright © 2021 Scott Mehus. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;
#import "ShaderTypes.h"

struct WorldMapVertexOut {
    float4 position [[ position ]];
    float2 textureCoordinates;
};

struct WorldMapVertexIn {
    float4 position [[ attribute(VertexAttributePosition) ]];
};


vertex WorldMapVertexOut worldMap_vertex(const WorldMapVertexIn in [[ stage_in ]],
                               constant Uniforms &uniforms [[ buffer(BufferIndexUniforms) ]],
                               constant float2 &viewPort [[ buffer(BufferIndexViewport) ]]) {
    return {
        .position = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix * in.position,
        .textureCoordinates =  in.position.xy
    };
}

fragment float4 worldMap_fragment(const WorldMapVertexOut in [[ stage_in ]],
                             constant Uniforms &uniforms [[ buffer(BufferIndexUniforms)]],
                             constant float2 &viewPort [[ buffer(BufferIndexViewport) ]]) {
    float2 xy;
    float3 screenCoord = uniforms.modelMatrix.columns[3].xyz;
    float width = viewPort.x * 0.25;
    float height = viewPort.y * 0.25;


    return float4(1.0, 0.0, 0.0, 1.0);
}
