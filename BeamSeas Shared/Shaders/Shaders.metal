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

constant bool hasColorTexture [[ function_constant(0) ]];
constant bool hasNormalTexture [[ function_constant(1) ]];

struct VertexIn {
    float4 position [[ attribute(VertexAttributePosition) ]];
    float3 normal [[ attribute(VertexAttributeNormal) ]];
    float2 uv [[ attribute(VertexAttributeUV) ]];
    float3 tangent [[ attribute(VertexAttributeTangent) ]];
    float3 bitangent [[ attribute(VertexAttributeBitangent) ]];
};

struct VertexOut {
    float4 position [[ position ]];
    float3 worldPosition;
    float3 worldNormal;
    float2 uv;
    float3 worldTangent;
    float3 worldBitangent;
};

vertex VertexOut vertex_main(const VertexIn vertex_in [[ stage_in ]],
                             texture2d<float> primarySlopMap [[ texture(TextureIndexPrimarySlope) ]],
                            texture2d<float> seconarySlopeMap [[ texture(TextureIndexSecondarySlope) ]],
                             constant Uniforms &uniforms [[ buffer(BufferIndexUniforms) ]])
{

    VertexOut out;
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix * vertex_in.position;
    out.worldPosition = (uniforms.modelMatrix * vertex_in.position).xyz;
    out.worldNormal = uniforms.normalMatrix * vertex_in.normal;
    out.uv = vertex_in.uv;
    out.worldTangent = uniforms.normalMatrix * vertex_in.tangent;
    out.worldBitangent = uniforms.normalMatrix * vertex_in.bitangent;

    return out;
}

float3 diffuseLighting(float3 normal,
                       float3 position,
                       constant FragmentUniforms &fragmentUniforms,
                       constant Light *lights,
                       float3 baseColor) {
    float3 diffuseColor = 0;
    float3 normalDirection = normalize(normal);
    for (uint i = 0; i < fragmentUniforms.light_count; i++) {
        Light light = lights[i];
        if (light.type == Sunlight) {
            float3 lightDirection = normalize(light.position);
            float diffuseIntensity = saturate(dot(lightDirection, normalDirection));
            diffuseColor += light.color * light.intensity * baseColor * diffuseIntensity;
        } else if (light.type == Pointlight) {
            float d = distance(light.position, position);
            float3 lightDirection = normalize(light.position - position);
            float attenuation = 1.0 / (light.attenuation.x + light.attenuation.y * d + light.attenuation.z * d * d);
            float diffuseIntensity = saturate(dot(lightDirection, normalDirection));
            float3 color = light.color * baseColor * diffuseIntensity;
            color *= attenuation;
            diffuseColor += color;
        } else if (light.type == Spotlight) {
            float d = distance(light.position, position);
            float3 lightDirection = normalize(light.position - position);
            float3 coneDirection = normalize(-light.coneDirection);
            float spotResult = (dot(lightDirection, coneDirection));
            if (spotResult > cos(light.coneAngle)) {
                float attenuation = 1.0 / (light.attenuation.x + light.attenuation.y * d + light.attenuation.z * d * d);
                attenuation *= pow(spotResult, light.coneAttenuation);
                float diffuseIntensity = saturate(dot(lightDirection, normalDirection));
                float3 color = light.color * baseColor * diffuseIntensity;
                color *= attenuation;
                diffuseColor += color;
            }
        }
    }
    return diffuseColor;
}


fragment float4 fragment_main(VertexOut in [[ stage_in ]],
                              constant Light *lights [[ buffer(BufferIndexLights) ]],
                              constant FragmentUniforms &fragmentUniforms [[ buffer(BufferIndexFragmentUniforms) ]],
                              constant Material &material [[ buffer(BufferIndexMaterials) ]],
                              texture2d<float> baseColorTexture [[ texture(TextureIndexColor), function_constant(hasColorTexture) ]],
                              texture2d<float> normalTexture [[ texture(TextureIndexNormal), function_constant(hasNormalTexture) ]],
                              sampler textureSampler [[ sampler(0) ]])
{

    float3 baseColor;
    if (hasColorTexture) {
        baseColor = baseColorTexture.sample(textureSampler, in.uv * fragmentUniforms.tiling).rgb;
    } else {
        baseColor = material.baseColor;
    }

    float3 normalValue;
    if (hasNormalTexture) {
        normalValue = normalTexture.sample(textureSampler, in.uv * fragmentUniforms.tiling).xyz;
        //This redistributes the normal value to be within the range -1 to 1.
        normalValue = normalValue * 2 - 1;
    } else {
        normalValue = in.worldNormal;
    }

    normalValue = normalize(normalValue);

    float3 diffuseColor = 0;
    float3 ambientColor = 0;
    float3 specularColor = 0;
    float materialShininess = material.shininess;
    float3 materialSpecularColor = material.specularColor;

    // idk - chapter 7 - pg 199
    float3 normalDirection = float3x3(in.worldTangent, in.worldBitangent, in.worldNormal) * normalValue;
    normalDirection = normalize(normalDirection);

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
        } else if (light.type == Pointlight) {
            float d = distance(light.position, in.worldPosition);
            float3 lightDirection = normalize(in.worldPosition - light.position);
            float attenuation = 1.0 / (light.attenuation.x + light.attenuation.y * d + light.attenuation.z * d * d);
            float diffuseIntensity = saturate(-dot(lightDirection, normalDirection));
            float3 color = light.color * baseColor * diffuseIntensity;
            color *= attenuation;
            diffuseColor += color;
        } else if (light.type == Spotlight) {
            float d = distance(light.position, in.worldPosition);
            float3 lightDirection = normalize(in.worldPosition - light.position);
            float3 coneDirection = normalize(light.coneDirection);
            float spotResult = dot(lightDirection, coneDirection);
            if (spotResult > cos(light.coneAngle)) {
                float attenuation = 1.0 / (light.attenuation.x + light.attenuation.y * d + light.attenuation.z * d * d);
                attenuation *= pow(spotResult, light.coneAttenuation);
                float diffuseIntensity =
                saturate(dot(-lightDirection, normalDirection));
                float3 color = light.color * baseColor * diffuseIntensity;
                color *= attenuation;
                diffuseColor += color;
            }
        }
    }

    float3 color = diffuseColor + ambientColor + specularColor;
    return float4(color, 1);
}
