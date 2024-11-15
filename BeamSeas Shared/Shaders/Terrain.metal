//
//  Terrain.metal
//  BeamSeas
//
//  Created by Scott Mehus on 7/4/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderTypes.h"

struct ControlPoint {
    float4 position [[ attribute(0) ]];
};

struct TerrainVertexOut {
    float4 position [[ position ]];
    float4 color;
    float2 uv;
    float4 vGradNormalTex;
    float3 normal;
    float4 worldPosition;
    float3 toCamera;
    float4 parentFragmentPosition;
    float4 landColor;
    float3 normal_cameraSpace;
    float3 eye_direction_cameraspace;
};

float calc_distance(float3 pointA,
                    float3 pointB,
                    float3 camera_position,
                    float4x4 modelMatrix)
{
    float3 positionA = (modelMatrix * float4(pointA, 1)).xyz;
    float3 positionB = (modelMatrix * float4(pointB, 1)).xyz; float3 midpoint = (positionA + positionB) * 0.5;
    float camera_distance = distance(camera_position, midpoint);
    return camera_distance;
}

kernel void tessellation_main(constant float *edge_factors [[ buffer(0) ]],
                              constant float *inside_factors [[ buffer(1) ]],
                              constant Uniforms &uniforms [[ buffer(BufferIndexUniforms) ]],
                              constant FragmentUniforms &fragmentUniforms [[ buffer(BufferIndexFragmentUniforms) ]],
                              constant TerrainParams &terrainParams [[ buffer(BufferIndexTerrainParams) ]],
                              constant float3 *control_points [[ buffer(BufferIndexControlPoints) ]],
                              device MTLQuadTessellationFactorsHalf *factors [[ buffer(2) ]],
                              uint pid [[ thread_position_in_grid ]])
{
    uint index = pid * 4;
    float totalTessellation = 0;
    for (int i = 0; i < 4; i++) {
      int pointAIndex = i;
      int pointBIndex = i + 1;
      if (pointAIndex == 3) {
        pointBIndex = 0;
        
      }
      int edgeIndex = pointBIndex;
//      float cameraDistance = calc_distance(control_points[pointAIndex + index],
//                                           control_points[pointBIndex + index],
//                                           fragmentUniforms.camera_position.xyz,
//                                           uniforms.modelMatrix);
        float tessellation = terrainParams.maxTessellation;//max(4.0, terrainParams.maxTessellation / cameraDistance);
      factors[pid].edgeTessellationFactor[edgeIndex] = tessellation;
      totalTessellation += tessellation;
    }
    factors[pid].insideTessellationFactor[0] = totalTessellation * 0.25;
    factors[pid].insideTessellationFactor[1] = totalTessellation * 0.25;
}


[[ patch(quad, 4) ]]
vertex TerrainVertexOut vertex_terrain(patch_control_point<ControlPoint> control_points [[ stage_in ]],
                                       float2 patch_coord [[ position_in_patch ]],
                                       texture2d<float> heightMap [[ texture(TextureIndexHeight) ]],
                                       texture2d<float> normalMap [[ texture(TextureIndexNormal) ]],
                                       constant TerrainParams &terrainParams [[ buffer(BufferIndexTerrainParams) ]],
                                       uint patchID [[ patch_id ]],
                                       constant Uniforms &uniforms [[ buffer(BufferIndexUniforms) ]],
                                       constant FragmentUniforms &fragmentUniforms [[ buffer(BufferIndexFragmentUniforms) ]],
                                       sampler scaffoldingSampler [[ sampler(0) ]],
                                       texturecube<float> worldMapTexture [[ texture(TextureIndexWorldMap) ]])
{
    TerrainVertexOut out;
    float u = patch_coord.x;
    float v = patch_coord.y;
    float2 top = mix(control_points[0].position.xz,
                     control_points[1].position.xz,
                     u);
    float2 bottom = mix(control_points[3].position.xz,
                        control_points[2].position.xz,
                        u);

    float2 interpolated = mix(top, bottom, v);
    // Actual position
    float4 position = float4(interpolated.x, 0.0, interpolated.y, 1.0);


    // Changing this to filter linear smoothes out the texture
    // Which ends up smoothing out the rendering
    constexpr sampler sample(filter::linear, address::repeat);

    float2 xy = ((position.xz + terrainParams.size / 2) / terrainParams.size);
    xy += uniforms.playerMovement.xz;
    out.uv = xy;
    
    float2 uInvHeightmapSize = float2(1.0 / terrainParams.size);
    float2 tex = position.xz * uInvHeightmapSize;
    
    // From example
//    vGradNormalTex = vec4(tex + 0.5 * uInvHeightmapSize.xy, tex * uScale.zw);
    float2 uScale = terrainParams.normal_scale;
    out.vGradNormalTex = float4(tex.xy + 0.5 * uInvHeightmapSize.xy, tex.xy * uScale);
    
//    out.vGradNormalTex = float4(position + 0.5 * terrainParams.size)
    // Why was i doing this??
//    xy.y = 1 - xy.y;
//    xy = 1 - xy;
//    xy.x = fmod(xy.x + (uniforms.deltaTime), 1);

    // DONT DELETE \\
    // USE THE ROTATION OF PARENT SOME HOW TO MAKE THE WATER ROTATE? NOT ROTATE?
    // TO MAKE IT LOOK LIKE TURNING THE PLAYER IS ACTUALLY TURNING THE PLAYER ON THE WATER.
//    xy *= terrainParams.size;
//    float3 heightDisplacement = mix(heightMap.sample(sample, xy + 0.5).xyz, heightMap.sample(sample, xy + 1.0).xyz, 0.5);
    float3 heightDisplacement = heightMap.sample(sample, xy).xyz;

//    float inverseColor = color.r;//1 - color.r;
    float3 ifftHeight = ((heightDisplacement * 2) - 1) * terrainParams.height;
    
    

    // OHHHHH shit - displacment maps dispalce in the horizontal plane.....
    //Using only a straight heightmap, this is not easy to implement, however, we can have another "displacement" map which computes displacement in the horizontal plane as well. If we compute the inverse Fourier transform of the gradient of the heightmap, we can find a horizontal displacement vector which we will push vertices toward. This gives a great choppy look to the waves.

    // This means not just this y value... but also displacing the patches in the x axies
    // Y & Z values represent the horizontal displacment inside the height map
    // Height displacement would only be between -1 & 1. So we need to modify it somehow to values that
    // are relevant....
    float3 horizontalDisplacement = (heightDisplacement * 2) - 1;
    float4 directionToFragment = (uniforms.parentTreeModelMatrix * position) - fragmentUniforms.scaffoldingPosition;
    float3 terrainToScaffold = normalize(directionToFragment).xyz;
    float4 scaffoldSample = worldMapTexture.sample(scaffoldingSampler, terrainToScaffold);
    float4 invertedScaffoldColor = (1 - scaffoldSample);
  
    float scaffoldHeight = (invertedScaffoldColor.x * 2 - 1) * terrainParams.height;
    // This will gradually chillout the ifft height as the scaffold land masses height gets closer to 0
    float3 ifftPercentHeight = ifftHeight;// * scaffoldSample.r;
    
    // PercentiFFTHeight needs to be based on how close scaffoldHeight is to 0.
    // So that we an transition between ifftHeight & scaffoldHeight seamlessly
    position.y = ifftPercentHeight.r;//max(scaffoldHeight, ifftPercentHeight.r);
    if (ifftPercentHeight.r > scaffoldHeight) {
//        position.x += (horizontalDisplacement.y);
//        position.z += (horizontalDisplacement.z);
    }

    constexpr sampler normalSampler(min_filter::linear, mag_filter::linear, mip_filter::nearest);
    float3 normalValue = normalize(normalMap.sample(normalSampler, xy).xzy * 2.0f - 1.0f);
    float3 normal = uniforms.normalMatrix * normalValue;

    out.normal = normal;
    out.normal_cameraSpace = (normalize(uniforms.modelMatrix * float4(normal, 0.0))).xyz;
    float3 vertex_position_cameraspace = ( uniforms.viewMatrix * uniforms.modelMatrix * position ).xyz;
    out.eye_direction_cameraspace = float3(0,0,0) - vertex_position_cameraspace;
    out.color = float4(heightDisplacement.x);
    
    out.worldPosition = uniforms.modelMatrix * position;
    /// This is just the world position of terrain if terrain were a child of scaffolding
    out.parentFragmentPosition = uniforms.parentTreeModelMatrix * position;
    out.toCamera = fragmentUniforms.camera_position - out.worldPosition.xyz;
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix * position;
    
    return out;
}

float3 terrainDiffuseLighting(float3 normal,
                              float3 position,
                              constant FragmentUniforms &fragmentUniforms,
                              constant Light *lights,
                              float3 baseColor) {
    float3 diffuseColor = 0;
    float3 ambientColor = 0;
    float3 specularColor = 0;
    float materialShininess = 32;
    float3 materialSpecularColor = float3(1, 1, 1);
    
    float3 normalDirection = normalize(normal);
    for (uint i = 0; i < fragmentUniforms.light_count; i++) {
        Light light = lights[i];
        if (light.type == Sunlight) {
            float3 lightDirection = normalize(float3(-light.position.x, -light.position.y, -light.position.z));
            float dotVal = dot(lightDirection, normalDirection);
            float diffuseIntensity = saturate(dotVal);
            if (diffuseIntensity < 0.2) {
                diffuseIntensity = diffuseIntensity;
            } else {
                diffuseIntensity = 1.0;
            }
            
            diffuseColor += baseColor * light.color * diffuseIntensity;
            
//            if (diffuseIntensity > 0) {
//                float3 reflection = reflect(lightDirection, normalDirection);
//                float3 cameraDirection = normalize(position - fragmentUniforms.camera_position);
//                float specularIntensity = pow(saturate(-dot(reflection, cameraDirection)), materialShininess);
//                specularColor += light.specularColor * materialSpecularColor * specularIntensity;
//            }
        } else if (light.type == Ambientlight) {
            ambientColor += baseColor * 0.01;
        }
    }
    
    return diffuseColor + ambientColor + specularColor;
}

float4 sepiaShader(float4 color) {

    float y = dot(float3(0.299, 0.587, 0.114), color.rgb);
//    float4 sepia = float4(0.191, -0.054, -0.221, 0.0);
    float4 sepia = float4(-0.2, -0.4, 0.4, 0.0);
    float4 output = sepia + y;
    output.z = color.z;

    output = mix(output, color, 0.4);
    return output;
}

// Don't use water ripple texture when calculating lighting you dipshit.
// Thats probably what makes the wave lighting so confusing to look at.

/*
fragment float4 fragment_terrain(TerrainVertexOut fragment_in [[ stage_in ]],
                                 constant Light *lights [[ buffer(BufferIndexLights) ]],
                                 constant Uniforms &uniforms [[ buffer(BufferIndexUniforms) ]],
                                 constant TerrainParams &terrainParams [[ buffer(BufferIndexTerrainParams) ]],
                                 constant FragmentUniforms &fragmentUniforms [[ buffer(BufferIndexFragmentUniforms) ]],
                                 texture2d<float> heightMap [[ texture(TextureIndexHeight) ]],
                                 texture2d<float> gradientMap [[ texture(TextureIndexGradient) ]],
                                 texture2d<float> normalMap [[ texture(TextureIndexNormal) ]],
                                 texture2d<float> reflectionTexture [[ texture(TextureIndexReflection) ]],
                                 texture2d<float> refractionTexture [[ texture(TextureIndexRefraction) ]],
                                 texture2d<float> waterRippleTexture [[ texture(TextureIndexWaterRipple) ]],
                                 texturecube<float> worldMapTexture [[ texture(TextureIndexWorldMap) ]],
                                 texture2d<float> landTexture [[ texture(TextureIndexScaffoldLand) ]])
{
    constexpr sampler s(filter::linear, address::repeat);
//    constexpr sampler s(min_filter::linear, mag_filter::linear, mip_filter::nearest);

    
    // Reflection
    // Refraction - Mimicks see through water - see the ground below
    // Fresnel - Refraction + Lighting Angles - the see througness is determined by camera angle
    
    // Ripple
    float2 rippleUV = fragment_in.uv * 4.0;
    float waveStrength  = 0.1;
    float2 rippleX = float2(rippleUV.x + uniforms.currentTime, rippleUV.y);
    float2 rippleY = float2(-rippleUV.x, rippleUV.y) + uniforms.currentTime;
    float2 ripple = ((normalMap.sample(s, rippleX).rg * 2.0 - 1.0) + (normalMap.sample(s, rippleY).rg * 2.0 - 1.0)) * waveStrength;
    // Not using for now
    
    // Normal
    // 128X128
    float2 normalCoords = fragment_in.uv;
    float4 normal = normalMap.sample(s, normalCoords) * 2.0 - 1.0;
    float4 landTextureColor = landTexture.sample(s, normalCoords);

    // DEBUG
//    float3 normalDirection = normalize(normal.rgb);
//    float3 lightPosition = float3(lights[0].position.x, lights[0].position.y - 5000, lights[0].position.z);
//    float3 lightDirection = normalize(lightPosition);
//    float dotVal = dot(lightDirection, normalDirection);
//    return float4(dotVal, dotVal, dotVal, 1.0);
    // DEBUG
    
    float3 color = terrainDiffuseLighting(normal.rgb,
                                          fragment_in.worldPosition.xyz,
                                          fragmentUniforms, lights,
                                          float3(0.0 / 255.0, 105.0 / 255.0, 148.0 / 255.0));
    return float4(color, 1.0);
}
*/
fragment float4 fragment_terrain(TerrainVertexOut fragment_in [[ stage_in ]],
                                 constant Light *lights [[ buffer(BufferIndexLights) ]],
                                 constant Uniforms &uniforms [[ buffer(BufferIndexUniforms) ]],
                                 constant TerrainParams &terrainParams [[ buffer(BufferIndexTerrainParams) ]],
                                 constant FragmentUniforms &fragmentUniforms [[ buffer(BufferIndexFragmentUniforms) ]],
                                 texture2d<float> heightMap [[ texture(TextureIndexHeight) ]],
                                 texture2d<float> gradientMap [[ texture(TextureIndexGradient) ]],
                                 texture2d<float> normalMap [[ texture(TextureIndexNormal) ]],
                                 texture2d<float> secondaryNormalMap [[ texture(TextureIndexSecondaryNormal)]],
                                 texture2d<float> reflectionTexture [[ texture(TextureIndexReflection) ]],
                                 texture2d<float> refractionTexture [[ texture(TextureIndexRefraction) ]],
                                 texture2d<float> waterRippleTexture [[ texture(TextureIndexWaterRipple) ]],
                                 texturecube<float> worldMapTexture [[ texture(TextureIndexWorldMap) ]],
                                 sampler scaffoldingSampler [[ sampler(0) ]])
{

    float4 mixedColor = float4(0.4, 0.6, 1.0, 1.0);
    
    constexpr sampler sam(min_filter::linear);
    
    // I have two shading techniques (technically two normal creation techniques). These are the two normal maps.
    float3 sampledNormalMap = normalMap.sample(sam, fragment_in.uv).rgb;
    float3 normal = normalize(sampledNormalMap * 2.0 - 1.0);
    
    // Forget which one is which
    float3 secondarySampledNormalMap = secondaryNormalMap.sample(sam, fragment_in.uv).rgb;
    float3 secondaryNormal = normalize(secondarySampledNormalMap * 2.0 - 1.0);
    
    float3 lightDirection = normalize(float3(-lights[0].position.x, -lights[0].position.y, -lights[0].position.z));
    float diffuse = saturate(dot(lightDirection, secondaryNormal));

    return mixedColor * diffuse;
    
}

//var maxRange = 0.3
//var val = 0.12
//let doubleMaxRange = (maxRange - -maxRange)
//let valuePlusMaxRange = (val - -maxRange)
//let convertedToPositiveScale = valuePlusMaxRange / doubleMaxRange
//let revertedToPositiveNegative = convertedToPositiveScale * doubleMaxRange - maxRange

// This relies on the ehight an dnormal textures to be teh same size. 128x128
kernel void TerrainKnl_ComputeNormalsFromHeightmap(texture2d<float> height [[texture(0)]],
                                                   texture2d<float, access::write> normal [[texture(2)]],
                                                   constant TerrainParams &terrain [[ buffer(3) ]],
                                                   constant Uniforms &uniforms [[ buffer(BufferIndexUniforms) ]],
                                                   uint2 tid [[thread_position_in_grid]],
                                                   constant float &xz_scale [[ buffer(4) ]],
                                                   constant float &y_scale [[ buffer(5) ]])
{
    constexpr sampler sam(min_filter::nearest, mag_filter::nearest, mip_filter::none,
                          address::clamp_to_edge, coord::pixel);

//    float xz_scale = (float(uniforms.distrubtionSize) / float(height.get_width()) / 2);

    if (tid.x < height.get_width() && tid.y < height.get_height()) {
        float h_up     = height.sample(sam, (float2)(tid + uint2(0, 1))).r;
        float h_down   = height.sample(sam, (float2)(tid - uint2(0, 1))).r;
        float h_right  = height.sample(sam, (float2)(tid + uint2(1, 0))).r;
        float h_left   = height.sample(sam, (float2)(tid - uint2(1, 0))).r;
        float h_center = height.sample(sam, (float2)(tid + uint2(0, 0))).r;

        float3 v_up    = float3( 0,        (h_up    - h_center) * y_scale,  xz_scale);
        float3 v_down  = float3( 0,        (h_down  - h_center) * y_scale, -xz_scale);
        float3 v_right = float3( xz_scale, (h_right - h_center) * y_scale,  0);
        float3 v_left  = float3(-xz_scale, (h_left  - h_center) * y_scale,  0);

        float3 n0 = cross(v_up, v_right);
        float3 n1 = cross(v_left, v_up);
        float3 n2 = cross(v_down, v_left);
        float3 n3 = cross(v_right, v_down);

        float3 n = normalize(n0 + n1 + n2 + n3) * 0.5f + 0.5f;

        normal.write(float4(n.xzy, 1), tid);
    }
}


// ORIGINAL

/*
 constexpr sampler sam(min_filter::nearest, mag_filter::nearest, mip_filter::none,
                       address::clamp_to_edge, coord::pixel);

 float xz_scale = TERRAIN_SCALE / height.get_width();
 float y_scale = TERRAIN_HEIGHT;

 if (tid.x < height.get_width() && tid.y < height.get_height()) {
     float h_up     = height.sample(sam, (float2)(tid + uint2(0, 1))).r;
     float h_down   = height.sample(sam, (float2)(tid - uint2(0, 1))).r;
     float h_right  = height.sample(sam, (float2)(tid + uint2(1, 0))).r;
     float h_left   = height.sample(sam, (float2)(tid - uint2(1, 0))).r;
     float h_center = height.sample(sam, (float2)(tid + uint2(0, 0))).r;

     float3 v_up    = float3( 0,        (h_up    - h_center) * y_scale,  xz_scale);
     float3 v_down  = float3( 0,        (h_down  - h_center) * y_scale, -xz_scale);
     float3 v_right = float3( xz_scale, (h_right - h_center) * y_scale,  0);
     float3 v_left  = float3(-xz_scale, (h_left  - h_center) * y_scale,  0);

     float3 n0 = cross(v_up, v_right);
     float3 n1 = cross(v_left, v_up);
     float3 n2 = cross(v_down, v_left);
     float3 n3 = cross(v_right, v_down);

     float3 n = normalize(n0 + n1 + n2 + n3) * 0.5f + 0.5f;

     normal.write(float4(n.xzy, 1), tid);
 }
 */
