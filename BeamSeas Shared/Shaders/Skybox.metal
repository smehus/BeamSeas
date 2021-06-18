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
};


vertex SkyboxVertexOut vertexSkybox(const SkyboxVertexIn in [[stage_in]],
                                    constant float4x4 &vp [[buffer(1)]]) {
    SkyboxVertexOut out;
    out.position = (vp * in.position).xyww;
    return out;
}

fragment half4 fragmentSkybox(SkyboxVertexOut in [[stage_in]]) {
    return half4(1, 1, 0, 1);
}
