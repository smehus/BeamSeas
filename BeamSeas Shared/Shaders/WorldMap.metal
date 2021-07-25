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
    float3 textureCoordinates;
    uint viewport [[ viewport_array_index ]];
};

struct WorldMapVertexIn {
    float4 position [[ attribute(VertexAttributePosition) ]];
};


vertex WorldMapVertexOut worldMap_vertex(const WorldMapVertexIn in [[ stage_in ]],
                                         constant Uniforms &uniforms [[ buffer(BufferIndexUniforms) ]]) {
    return {
        .position = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix * in.position,
        .textureCoordinates =  in.position.xyz
    };
}

fragment half4 worldMap_fragment(const WorldMapVertexOut in [[ stage_in ]],
                                  constant Uniforms &uniforms [[ buffer(BufferIndexUniforms)]],
                                  sampler textureSampler [[ sampler(0) ]],
                                  texturecube<half> cubeMap [[ texture(TextureIndexColor) ]]) {
    half4 color = cubeMap.sample(textureSampler, in.textureCoordinates);
    return color;
//    return float4(1, 0, 0, 1);
}
