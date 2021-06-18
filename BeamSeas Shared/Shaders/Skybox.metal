//
//  Skybox.metal
//  BeamSeas
//
//  Created by Scott Mehus on 6/16/21.
//  Copyright © 2021 Scott Mehus. All rights reserved.
//

#include <metal_stdlib>
#import "ShaderTypes.h"

using namespace metal;


struct SkyboxVertexIn {
    float4 position [[ attribute(0) ]];
};
struct SkyboxVertexOut {
    float4 position [[ position ]];
    float3 textureCoordinates;
};


vertex SkyboxVertexOut vertexSkybox(const SkyboxVertexIn in [[stage_in]],
                                    constant float4x4 &vp [[buffer(1)]]) {
    return {
        .position = (vp * in.position).xyww,
        .textureCoordinates = in.position.xyz
    };
}

fragment half4 fragmentSkybox(SkyboxVertexOut in [[stage_in]],
                              texturecube<half> cubeTexture [[ texture(TextureIndexSkybox) ]]) {
    constexpr sampler default_sampler(filter::linear);
    half4 color = cubeTexture.sample(default_sampler, in.textureCoordinates);
    return color;
}
