//
//  BasicShape.metal
//  BeamSeas
//
//  Created by Scott Mehus on 12/27/21.
//  Copyright © 2021 Scott Mehus. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderTypes.h"

struct BasicShapeVertexIn {
    float4 position [[ attribute(VertexAttributePosition) ]];
};

struct BasicShapeVertexOut {
    float4 position [[ position ]];
};


vertex BasicShapeVertexOut basicShape_vertex(const BasicShapeVertexIn in [[ stage_in ]], constant Uniforms &uniforms [[ buffer(BufferIndexUniforms)]]) {
    return {
      .position = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix * in.position,
    };
}

fragment float4 basicShape_fragment(const BasicShapeVertexOut in [[ stage_in ]],
                                    constant Material &material [[ buffer(BufferIndexMaterials) ]]) {
    return float4(material.baseColor, 1);
}
