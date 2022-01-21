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
    float4 uv;
    float clip_distance [[clip_distance]] [1];
};

struct SkyboxFragmentIn {
    float4 position [[ position ]];
    float4 uv;
    float clip_distance;
};


vertex SkyboxVertexOut vertexSkybox(const SkyboxVertexIn in [[stage_in]],
                                    constant float4x4 &vp [[ buffer(1) ]],
                                    constant Uniforms &uniforms [[buffer(BufferIndexUniforms)]]) {
    return {
        .position = (uniforms.projectionMatrix * uniforms.viewMatrix * in.position).xyww,
        .uv = in.position,
        .clip_distance[0] = dot(uniforms.modelMatrix * in.position, uniforms.clipPlane)
    };
}

fragment half4 fragmentSkybox(SkyboxFragmentIn in [[stage_in]],
                              constant Uniforms &uniforms [[ buffer(BufferIndexUniforms) ]],
                              texturecube<half> cubeTexture [[ texture(TextureIndexSkybox) ]]) {
    constexpr sampler default_sampler(filter::linear);
    half4 color = cubeTexture.sample(default_sampler, in.uv.xyz);
    
    if (color.r < 0.1) {
        color.r = sin(uniforms.currentTime);
    }
    
    return color;
}
