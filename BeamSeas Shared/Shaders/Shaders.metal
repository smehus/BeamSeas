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
    float3 worldPosition;
    float3 worldNormal;
};

vertex VertexOut vertex_main(const VertexIn vertex_in [[ stage_in ]],
                          constant Uniforms &uniforms [[ buffer(1) ]])
{
    return {
        .position = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix * vertex_in.position,
        .worldPosition = (uniforms.modelMatrix * vertex_in.position).xyz,
        .worldNormal = uniforms.normalMatrix * vertex_in.normal
    };
}

fragment float4 fragment_main(VertexOut in [[ stage_in ]],
                              constant Light *lights [[ buffer(BufferIndexLights) ]],
                              constant FragmentUniforms &fragmentUniforms [[ buffer(BufferIndexFragmentUniforms) ]])
{
    float3 baseColor = float3(0, 0, 1);
    float3 diffuseColor = 0;
    float3 ambientColor = 0;
    float3 specularColor = 0;
    float materialShininess = 32;
    float3 materialSpecularColor = float3(1, 1, 1);

    float3 normalDirection = normalize(in.worldNormal);
    for (uint i = 0; i < fragmentUniforms.light_count; i++) {
        Light light = lights[i];
        if (light.type == Sunlight) {
            float3 lightDirection = normalize(-light.position);
            float diffuseIntensity = saturate(-dot(lightDirection, normalDirection));
            diffuseColor += light.color * baseColor * diffuseIntensity;

            // specular
            if (diffuseIntensity > 0) {
                float3 reflection = reflect(lightDirection, normalDirection);
                float3 cameraDirection = normalize(in.worldPosition - fragmentUniforms.camera_position);
                float specularIntensity = pow(saturate(-dot(reflection, cameraDirection)), materialShininess);
                specularColor += light.specularColor * materialSpecularColor * specularIntensity;
            }

        } else if (light.type == Ambientlight) {
            ambientColor += light.color * light.intensity;
        }
    }

    float3 color = diffuseColor + ambientColor + specularColor;
    return float4(color, 1);
}
