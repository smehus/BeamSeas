/**
 * Copyright (c) 2019 Razeware LLC
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
 * distribute, sublicense, create a derivative work, and/or sell copies of the
 * Software in any work that is designed, intended, or marketed for pedagogical or
 * instructional purposes related to programming, coding, application development,
 * or information technology.  Permission for such use, copying, modification,
 * merger, publication, distribution, sublicensing, creation of derivative works,
 * or sale is expressly withheld.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include <metal_stdlib>
using namespace metal;

#import "ShaderTypes.h"

constant bool hasColorTexture [[function_constant(0)]];
constant bool hasNormalTexture [[function_constant(1)]];
constant bool hasRoughnessTexture [[function_constant(2)]];
constant bool hasMetallicTexture [[function_constant(3)]];
constant bool hasAOTexture [[function_constant(4)]];

constant float pi = 3.1415926535897932384626433832795;

struct VertexOut {
  float4 position [[ position ]];
  float3 worldPosition;
  float3 worldNormal;
  float3 worldTangent;
  float3 worldBitangent;
  float2 uv;
};

typedef struct Lighting {
  float3 lightDirection;
  float3 viewDirection;
  float3 baseColor;
  float3 normal;
  float metallic;
  float roughness;
  float ambientOcclusion;
  float3 lightColor;
} Lighting;

float3 render(Lighting lighting);

fragment float4 fragment_pbr(VertexOut in [[stage_in]],
          constant Light *lights [[buffer(BufferIndexLights)]],
          constant Material &material [[buffer(BufferIndexMaterials)]],
          sampler textureSampler [[sampler(0)]],
          constant FragmentUniforms &fragmentUniforms [[buffer(BufferIndexFragmentUniforms)]],
          texture2d<float> baseColorTexture [[texture(TextureIndexColor), function_constant(hasColorTexture)]],
          texture2d<float> normalTexture [[texture(TextureIndexNormal), function_constant(hasNormalTexture)]],
          texture2d<float> roughnessTexture [[texture(2), function_constant(hasRoughnessTexture)]],
          texture2d<float> metallicTexture [[texture(3), function_constant(hasMetallicTexture)]],
          texture2d<float> aoTexture [[texture(4), function_constant(hasAOTexture)]]) {
    // extract color
  float3 baseColor;
  if (hasColorTexture) {
    baseColor = baseColorTexture.sample(textureSampler,
                                        in.uv * fragmentUniforms.tiling).rgb;
  } else {
    baseColor = material.baseColor;
  }
    
  // extract metallic
  float metallic;
  if (hasMetallicTexture) {
    metallic = metallicTexture.sample(textureSampler, in.uv).r;
  } else {
    metallic = material.metallic;
  }
  // extract roughness
  float roughness;
  if (hasRoughnessTexture) {
    roughness = roughnessTexture.sample(textureSampler, in.uv).r;
  } else {
    roughness = material.roughness;
  }
  // extract ambient occlusion
  float ambientOcclusion;
  if (hasAOTexture) {
    ambientOcclusion = aoTexture.sample(textureSampler, in.uv).r;
  } else {
    ambientOcclusion = 1.0;
  }
  
  // normal map
//  float3 normal;
//  if (hasNormalTexture) {
//    float3 normalValue = normalTexture.sample(textureSampler, in.uv * fragmentUniforms.tiling).xyz * 2.0 - 1.0;
//    normal = in.worldNormal * normalValue.z + in.worldTangent * normalValue.x + in.worldBitangent * normalValue.y;
//  } else {
//    normal = in.worldNormal;
//  }
//
//  normal = normalize(normal);

    float3 normalValue;
    if (hasNormalTexture) {
        normalValue = normalTexture.sample(textureSampler, in.uv * fragmentUniforms.tiling).xyz;
        //This redistributes the normal value to be within the range -1 to 1.
        normalValue = normalValue * 2 - 1;
    } else {
        normalValue = in.worldNormal;
    }

    normalValue = normalize(normalValue);

    // idk - chapter 7 - pg 199
    float3 normalDirection = float3x3(in.worldTangent, in.worldBitangent, in.worldNormal) * normalValue;
    normalDirection = normalize(normalDirection);



  float3 viewDirection = normalize(fragmentUniforms.camera_position - in.worldPosition);
  
  Light light = lights[0];
  float3 lightDirection = normalize(light.position);
  
  // all the necessary components are in place
  Lighting lighting;
  lighting.lightDirection = lightDirection;
  lighting.viewDirection = viewDirection;
  lighting.baseColor = baseColor;
  lighting.normal = normalDirection;
  lighting.metallic = metallic;
  lighting.roughness = roughness;
  lighting.ambientOcclusion = ambientOcclusion;
  lighting.lightColor = light.color;
  
  float3 specularOutput = render(lighting);
  // compute Lambertian diffuse
  float nDotl = max(0.001, saturate(dot(lighting.normal, lighting.lightDirection)));
  // rescale from -1 : 1 to 0.4 - 1 to lighten shadows
  nDotl = ((nDotl + 1) / (1 + 1)) * (1 - 0.3) + 0.3;
  float3 diffuseColor = light.color * baseColor * nDotl * ambientOcclusion;
  diffuseColor *= 1.0 - metallic;
  float4 finalColor = float4(specularOutput + diffuseColor, 1.0);
  return finalColor;
}

/*
PBR.metal rendering equation from Apple's LODwithFunctionSpecialization sample code is under Copyright © 2017 Apple Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/


float3 render(Lighting lighting) {
  // Rendering equation courtesy of Apple et al.
  float nDotl = max(0.001, saturate(dot(lighting.normal, lighting.lightDirection)));
  float3 halfVector = normalize(lighting.lightDirection + lighting.viewDirection);
  float nDoth = max(0.001, saturate(dot(lighting.normal, halfVector)));
  float nDotv = max(0.001, saturate(dot(lighting.normal, lighting.viewDirection)));
  float hDotl = max(0.001, saturate(dot(lighting.lightDirection, halfVector)));
  
  // specular roughness
  float specularRoughness = lighting.roughness * (1.0 - lighting.metallic) + lighting.metallic;
  
  // Distribution
  float Ds;
  if (specularRoughness >= 1.0) {
    Ds = 1.0 / pi;
  }
  else {
    float roughnessSqr = specularRoughness * specularRoughness;
    float d = (nDoth * roughnessSqr - nDoth) * nDoth + 1;
    Ds = roughnessSqr / (pi * d * d);
  }
  
  // Fresnel
  float3 Cspec0 = float3(1.0);
  float fresnel = pow(clamp(1.0 - hDotl, 0.0, 1.0), 5.0);
  float3 Fs = float3(mix(float3(Cspec0), float3(1), fresnel));
  
  
  // Geometry
  float alphaG = (specularRoughness * 0.5 + 0.5) * (specularRoughness * 0.5 + 0.5);
  float a = alphaG * alphaG;
  float b1 = nDotl * nDotl;
  float b2 = nDotv * nDotv;
  float G1 = (float)(1.0 / (b1 + sqrt(a + b1 - a*b1)));
  float G2 = (float)(1.0 / (b2 + sqrt(a + b2 - a*b2)));
  float Gs = G1 * G2;
  
  float3 specularOutput = (Ds * Gs * Fs * lighting.lightColor) * (1.0 + lighting.metallic * lighting.baseColor) + lighting.metallic * lighting.lightColor * lighting.baseColor;
  specularOutput = specularOutput * lighting.ambientOcclusion;
  
  return specularOutput;
}

struct LightingParameters {
    float3 lightDir;
    float3 viewDir;
    float3 halfVector;
    float3 reflectedVector;
    float3 normal;
    float3 reflectedColor;
    float3 irradiatedColor;
    float3 baseColor;
    float3 diffuseLightColor;
    float  NdotH;
    float  NdotV;
    float  NdotL;
    float  HdotL;
    float  metalness;
    float  roughness;
};

#define SRGB_ALPHA 0.055

float linear_from_srgb(float x) {
    if (x <= 0.04045)
        return x / 12.92;
    else
        return powr((x + SRGB_ALPHA) / (1.0 + SRGB_ALPHA), 2.4);
}

float3 linear_from_srgb(float3 rgb) {
    return float3(linear_from_srgb(rgb.r), linear_from_srgb(rgb.g), linear_from_srgb(rgb.b));
}

//vertex VertexOut vertex_main(Vertex in [[stage_in]],
//                             constant Uniforms &uniforms [[buffer(vertexBufferIndexUniforms)]])
//{
//    VertexOut out;
//    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
//    out.texCoords = in.texCoords;
//    out.normal = uniforms.normalMatrix * in.normal;
//    out.tangent = uniforms.normalMatrix * in.tangent;
//    out.bitangent = uniforms.normalMatrix * cross(in.normal, in.tangent);
//    out.worldPos = (uniforms.modelMatrix * float4(in.position, 1.0)).xyz;
//    return out;
//}

static float3 diffuseTerm(LightingParameters parameters) {
    float3 diffuseColor = (parameters.baseColor.rgb / M_PI_F) * (1.0 - parameters.metalness);
    return diffuseColor * parameters.NdotL * parameters.diffuseLightColor;
}

static float SchlickFresnel(float dotProduct) {
    return pow(clamp(1.0 - dotProduct, 0.0, 1.0), 5.0);
}

static float Geometry(float NdotV, float alphaG) {
    float a = alphaG * alphaG;
    float b = NdotV * NdotV;
    return 1.0 / (NdotV + sqrt(a + b - a * b));
}

static float TrowbridgeReitzNDF(float NdotH, float roughness) {
    if (roughness >= 1.0)
        return 1.0 / M_PI_F;

    float roughnessSqr = roughness * roughness;

    float d = (NdotH * roughnessSqr - NdotH) * NdotH + 1;
    return roughnessSqr / (M_PI_F * d * d);
}

static float3 specularTerm(LightingParameters parameters) {
    float specularRoughness = parameters.roughness * (1.0 - parameters.metalness) + parameters.metalness;

    float D = TrowbridgeReitzNDF(parameters.NdotH, specularRoughness);

    float Cspec0 = 0.04;
    float3 F = mix(Cspec0, 1, SchlickFresnel(parameters.HdotL));
    float alphaG = powr(specularRoughness * 0.5 + 0.5, 2);
    float G = Geometry(parameters.NdotL, alphaG) * Geometry(parameters.NdotV, alphaG);

    float3 specularOutput = (D * G * F * parameters.irradiatedColor) * (1.0 + parameters.metalness * parameters.baseColor) +
                                                 parameters.irradiatedColor * parameters.metalness * parameters.baseColor;

    return specularOutput;
}

fragment half4 fragment_warren(VertexOut in [[stage_in]],
                             constant Light *lights [[buffer(BufferIndexLights)]],
                             constant Material &material [[buffer(BufferIndexMaterials)]],
                             sampler textureSampler [[sampler(0)]],
                             constant FragmentUniforms &fragmentUniforms [[buffer(BufferIndexFragmentUniforms)]],
                             texture2d<float> baseColorTexture [[texture(TextureIndexColor), function_constant(hasColorTexture)]],
                             texture2d<float> normalTexture [[texture(TextureIndexNormal), function_constant(hasNormalTexture)]],
                             texture2d<float> roughnessTexture [[texture(2), function_constant(hasRoughnessTexture)]],
                             texture2d<float> metallicTexture [[texture(3), function_constant(hasMetallicTexture)]],
                             texture2d<float> aoTexture [[texture(4), function_constant(hasAOTexture)]]) {
    constexpr sampler linearSampler (mip_filter::linear, mag_filter::linear, min_filter::linear);
    constexpr sampler mipSampler(min_filter::linear, mag_filter::linear, mip_filter::linear);
    constexpr sampler normalSampler(filter::nearest);

    const float3 diffuseLightColor(4);

    LightingParameters parameters;

    float4 baseColor = baseColorTexture.sample(linearSampler, in.uv);
    parameters.baseColor = linear_from_srgb(baseColor.rgb);
    parameters.roughness = roughnessTexture.sample(linearSampler, in.uv).g;
    parameters.metalness = metallicTexture.sample(linearSampler, in.uv).b;
    float3 mapNormal = normalTexture.sample(normalSampler, in.uv).rgb * 2.0 - 1.0;
    //mapNormal.y = -mapNormal.y; // Flip normal map Y-axis if necessary
    float3x3 TBN(in.worldTangent, in.worldBitangent, in.worldNormal);
    parameters.normal = normalize(TBN * mapNormal);

    parameters.diffuseLightColor = diffuseLightColor;
    parameters.lightDir = normalize(lights[0].position);
    parameters.viewDir = normalize(fragmentUniforms.camera_position - in.worldPosition);
    parameters.halfVector = normalize(parameters.lightDir + parameters.viewDir);
    parameters.reflectedVector = reflect(-parameters.viewDir, parameters.normal);

    parameters.NdotL = saturate(dot(parameters.normal, parameters.lightDir));
    parameters.NdotH = saturate(dot(parameters.normal, parameters.halfVector));
    parameters.NdotV = saturate(dot(parameters.normal, parameters.viewDir));
    parameters.HdotL = saturate(dot(parameters.lightDir, parameters.halfVector));

//    float mipLevel = parameters.roughness * irradianceMap.get_num_mip_levels();
//    parameters.irradiatedColor = irradianceMap.sample(mipSampler, parameters.reflectedVector, level(mipLevel)).rgb;

//    float3 emissiveColor = emissiveMap.sample(linearSampler, in.uv).rgb;

    float3 color = diffuseTerm(parameters) + specularTerm(parameters);// + emissiveColor;

    return half4(half3(color), baseColor.a);
}

