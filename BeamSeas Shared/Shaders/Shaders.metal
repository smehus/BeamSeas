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

constant float4 materialAmbientColor = {0.18, 0.18, 0.18, 1.0};
constant float4 materialDiffuseColor = {0.2, 0.2, 0.9, 1.0};
constant float4 materialSpecularColor = {0.3, 0.3, 1.0, 1.0};
constant float  materialShine = 50.0;
constant float d1 = 0.1;
constant float d2 = 0.6;
constant float d3 = 1.0;

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
    float3 normal_cameraSpace;
    float3 eye_direction_cameraspace;
    float3 light_direction_cameraspace;
};

vertex VertexOut vertex_main(const VertexIn vertex_in [[ stage_in ]],
                             constant Light *lights [[ buffer(BufferIndexLights) ]],
                             constant TerrainParams &terrain [[ buffer(BufferIndexTerrainParams) ]],
                             texture2d<float> terrainNormalMap [[ texture(TextureIndexNormal) ]],
                             texture2d<float> primarySlopMap [[ texture(TextureIndexPrimarySlope) ]],
                             texture2d<float> secondarySlopeMap [[ texture(TextureIndexSecondarySlope) ]],
                             constant Uniforms &uniforms [[ buffer(BufferIndexUniforms) ]])
{

    VertexOut out;

//    constexpr sampler sample;
//    float3 worldPosition = uniforms.modelMatrix.columns[3].xyz;
//    float2 xy = ((worldPosition.xy + terrain.size / 2) / terrain.size);
//
//    float4 primarySlope = primarySlopMap.sample(sample, xy);
//    float4 secondarySlope = secondarySlopeMap.sample(sample, xy);
//    // gotta find the dot prods?
//    float3 normalMapValue = terrainNormalMap.sample(sample, xy).rgb;
//
//
//    float slopeAngle = (mix(primarySlope, secondarySlope, 0.5).r * 100);
//    slopeAngle = (slopeAngle / 180) * M_PI_F;
//
//
//    float3 normalizedWorldPosition = normalize(worldPosition.xyz);
//    float dotProd = saturate(dot(normalizedWorldPosition, normalMapValue));
//    float normalAngle = dotProd * 100;
//
//    if (dotProd > 0.5) {
//        normalAngle = 90;
//    } else {
//        normalAngle = 0;
//    }
//
//    float radiansNormalAngle = (normalAngle / 180) * M_PI_F;
//
//
//    float angle = radiansNormalAngle;
//
//    float4x4 modelMatrix = float4x4(1); // Creates identity matrix
//    modelMatrix.columns[0][0] = cos(angle);
//    modelMatrix.columns[0][2] = sin(angle);
//    modelMatrix.columns[2][0] = -sin(angle);
//    modelMatrix.columns[2][2] = cos(angle);
//    float4x4 slopeModelVertex = uniforms.modelMatrix * modelMatrix;

    // I forget why I was calculating the slop here... maybe for white cap things. 
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix * vertex_in.position;
    out.worldPosition = (uniforms.modelMatrix * vertex_in.position).xyz;
    out.worldNormal = uniforms.normalMatrix * vertex_in.normal;
    out.uv = vertex_in.uv;
    out.worldTangent = uniforms.normalMatrix * vertex_in.tangent;
    out.worldBitangent = uniforms.normalMatrix * vertex_in.bitangent;
    out.normal_cameraSpace = (normalize(uniforms.modelMatrix * float4(vertex_in.normal, 0.0))).xyz;
    float3 vertex_position_cameraspace = ( uniforms.viewMatrix * uniforms.modelMatrix * out.position ).xyz;
    out.eye_direction_cameraspace = float3(0,0,0) - vertex_position_cameraspace;
    Light light = lights[0];
    float3 light_position_cameraspace = ( uniforms.modelMatrix * float4(light.position, 1)).xyz;
    out.light_direction_cameraspace = light_position_cameraspace + normalize(light.position); // This is probably wrong yo

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

float4 sepiaShaderCharacter(float4 color) {

    float y = dot(float3(0.299, 0.587, 0.114), color.rgb);
    float4 sepia = float4(0.191, -0.054, -0.221, 0.0);
    float4 output = sepia + y;
    output.z = color.z;

    output = mix(output, color, 0.4);
    return output;
}

fragment float4 fragment_main(VertexOut in [[ stage_in ]],
                              constant Light *lights [[ buffer(BufferIndexLights) ]],
                              constant Uniforms &uniforms [[ buffer(BufferIndexUniforms) ]],
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
//
//    float3 diffuseColor = 0;
//    float3 ambientColor = 0;
//    float3 specularColor = 0;
//    float materialShininess = material.shininess;
//    float4 materialSpecularColor = float4(material.specularColor, 1.0);

    // idk - chapter 7 - pg 199
    float3 normalDirection = float3x3(in.worldTangent, in.worldBitangent, in.worldNormal) * normalValue;
    normalDirection = normalize(normalDirection);

//    for (uint i = 0; i < fragmentUniforms.light_count; i++) {
//        Light light = lights[i];
//        if (light.type == Sunlight) {
//            float3 lightDirection = normalize(-light.position);
//            float diffuseIntensity = saturate(-dot(lightDirection, normalDirection));
//            diffuseColor += light.color * baseColor * diffuseIntensity;
//
//            // specular
//            if (diffuseIntensity > 0) {
//                float3 reflection = reflect(lightDirection, normalDirection);
//                float3 cameraDirection = normalize(in.worldPosition - fragmentUniforms.camera_position);
//                float specularIntensity = pow(saturate(-dot(reflection, cameraDirection)), materialShininess);
//                specularColor += light.specularColor * materialSpecularColor * specularIntensity;
//            }
//
//        } else if (light.type == Ambientlight) {
//            ambientColor += light.color * light.intensity;
//        } else if (light.type == Pointlight) {
//            float d = distance(light.position, in.worldPosition);
//            float3 lightDirection = normalize(in.worldPosition - light.position);
//            float attenuation = 1.0 / (light.attenuation.x + light.attenuation.y * d + light.attenuation.z * d * d);
//            float diffuseIntensity = saturate(-dot(lightDirection, normalDirection));
//            float3 color = light.color * baseColor * diffuseIntensity;
//            color *= attenuation;
//            diffuseColor += color;
//        } else if (light.type == Spotlight) {
//            float d = distance(light.position, in.worldPosition);
//            float3 lightDirection = normalize(in.worldPosition - light.position);
//            float3 coneDirection = normalize(light.coneDirection);
//            float spotResult = dot(lightDirection, coneDirection);
//            if (spotResult > cos(light.coneAngle)) {
//                float attenuation = 1.0 / (light.attenuation.x + light.attenuation.y * d + light.attenuation.z * d * d);
//                attenuation *= pow(spotResult, light.coneAttenuation);
//                float diffuseIntensity =
//                saturate(dot(-lightDirection, normalDirection));
//                float3 color = light.color * baseColor * diffuseIntensity;
//                color *= attenuation;
//                diffuseColor += color;
//            }
//        }
//    }

//    float3 color = diffuseColor + ambientColor + specularColor;
    
//    return float4(color, 1);
//    return sepiaShaderCharacter(float4(color, 1.0));
//    return celDiffuseLighting(normalDirection,
//                                      float4(baseColor, 1.0),
//                                      in.worldPosition,
//                                      in.normal_cameraSpace,
//                                      in.eye_direction_cameraspace,
//                                      uniforms,
//                                      fragmentUniforms,
//                                      lights,
//                                      baseColor)

//    float4 blah = celDiffuseLighting(normalDirection, float4(baseColor, 1.0), in.worldPosition, in.normal_cameraSpace, in.eye_direction_cameraspace, uniforms, fragmentUniforms, lights, baseColor);
    
    
    
    float4 ambient_color = float4(baseColor, 1.0);
    float3 n = normalize(in.normal_cameraSpace);

    //    for (uint i = 0; i < fragmentUniforms.light_count; i++) {
        Light light = lights[0];


        float3 l = normalize(in.light_direction_cameraspace);
        float n_dot_l = dot(n, l);

        float diffuse_factor = saturate(n_dot_l);
        float epsilon = fwidth(diffuse_factor);
        // If it is on the border of the first two colors, smooth it
        if ( (diffuse_factor > d1 - epsilon) && (diffuse_factor < d1 + epsilon) )
        {
            diffuse_factor = mix(d1, d2, smoothstep(d1-epsilon, d1+epsilon, diffuse_factor));
        }
        // If it is on the border of the second two colors, smooth it
        else if ( (diffuse_factor > d2 - epsilon) && (diffuse_factor < d2 + epsilon) )
        {
            diffuse_factor = mix(d2, d3, smoothstep(d2-epsilon, d2+epsilon, diffuse_factor));
        }
        // If it is the darkest color
        else if (diffuse_factor < d1)
        {
            diffuse_factor = 0.0;
        }
        // If is is the mid-range color
        else if (diffuse_factor < d2)
        {
            diffuse_factor = d2;
        }
        // It is the brightest color
        else
        {
            diffuse_factor = d3;
        }

        float4 diffuse_color = float4(light.color, 1.0) * diffuse_factor * materialDiffuseColor;

        // Calculate the specular color. This is done in a similar fashion to how the diffuse color
        // is calculated. We see if the angle between the viewer and the reflected light is small. If
        // is it, we color it the specular color. If it is on the border of the specular highlight
        // (i.e. it is within an epsilon value we define as the derivative of the specular factor),
        // we linearly interpolate between the two colors to create a more natural looking, smooth
        // transition.
        float3 e = normalize(in.eye_direction_cameraspace);
        float3 r = -l + 2.0f * n_dot_l * n;
        float e_dot_r =  saturate( dot(e, r) );

        float specular_factor = pow(e_dot_r, materialShine);
        epsilon = fwidth(specular_factor);

        // If it is on the edge of the specular highlight
        if ( (specular_factor > 0.5f - epsilon) && (specular_factor < 0.5f + epsilon) )
        {
            specular_factor = smoothstep(0.5f - epsilon, 0.5f + epsilon, specular_factor);
        }
        // It is either in or out of the highlight
        else
        {
            specular_factor = step(0.5f, specular_factor);
        }

        float4 specular_color = materialSpecularColor * float4(light.color, 1.0) * specular_factor;

    return sepiaShaderCharacter(float4(ambient_color + diffuse_color + specular_color));
}
