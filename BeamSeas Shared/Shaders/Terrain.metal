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
    float2 uInvHeightmapSize = float2(1.0 / terrainParams.size.x, 1.0 / terrainParams.size.y);
    float2 tex = position.xz * uInvHeightmapSize;
    out.vGradNormalTex = float4(tex.x + 0.5 * uInvHeightmapSize.x,
                                tex.y + 0.5 * uInvHeightmapSize.y,
                                tex.x,
                                tex.y);
    
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
    float3 ifftHeight = (heightDisplacement * 2 - 1) * terrainParams.height;

    // OHHHHH shit - displacment maps dispalce in the horizontal plane.....
    //Using only a straight heightmap, this is not easy to implement, however, we can have another "displacement" map which computes displacement in the horizontal plane as well. If we compute the inverse Fourier transform of the gradient of the heightmap, we can find a horizontal displacement vector which we will push vertices toward. This gives a great choppy look to the waves.

    // This means not just this y value... but also displacing the patches in the x axies
    // Y & Z values represent the horizontal displacment inside the height map
    // Height displacement would only be between -1 & 1. So we need to modify it somehow to values that
    // are relevant....
    float3 horizontalDisplacement = heightDisplacement * 2 - 1;
    float4 directionToFragment = (uniforms.parentTreeModelMatrix * position) - fragmentUniforms.scaffoldingPosition;
    float3 terrainToScaffold = normalize(directionToFragment).xyz;
    float4 scaffoldSample = worldMapTexture.sample(scaffoldingSampler, terrainToScaffold);
    float4 invertedScaffoldColor = (1 - scaffoldSample);
  
    float scaffoldHeight = (invertedScaffoldColor.x * 2 - 1) * terrainParams.height;
    // This will gradually chillout the ifft height as the scaffold land masses height gets closer to 0
    float3 ifftPercentHeight = ifftHeight * scaffoldSample.r;
    
    // PercentiFFTHeight needs to be based on how close scaffoldHeight is to 0.
    // So that we an transition between ifftHeight & scaffoldHeight seamlessly
    
    
    position.y = max(scaffoldHeight, ifftPercentHeight.r);
    
//    if (scaffoldHeight >= 0) {
//        position.y = scaffoldHeight;
//        out.landColor = float4(0.2, 0.8, 0.2, 1.0);
//    } else {
//        if (ifftPercentHeight.r < scaffoldHeight) {
//            position.y = scaffoldHeight;
//            out.landColor = float4(0.2, 0.8, 0.2, 1.0);
//        } else {
//            position.y = ifftPercentHeight.r;
//            out.landColor = float4(0.2, 0.2, 0.6, 1.0);
//        }
//    }

     // Add a percentaged multiplied ifft height. So the higher the scaffold height, the less affect ifft height will have.
    ////        position.x += (horizontalDisplacement.y);
    ////        position.z += (horizontalDisplacement.z);
    
    
    float adjustedHeight = heightDisplacement.y;
//    adjustedHeight = 1 - adjustedHeight;
    // Changing the modelMatrix here shouldn't have any affect on the texture coordinatores.... but it does....?
    // Using scaffolding positon makes no sense here since its the position of the vertex ( or the calculated position of abstract vertext )
    // Using scaffolding position just sets the same position for all fragments
    
    float4 finalColor = float4(heightDisplacement.x);

    // reference AAPLTerrainRenderer in DynamicTerrainWithArgumentBuffers exmaple: EvaluateTerrainAtLocation line 235 -> EvaluateTerrainAtLocation in AAPLTerrainRendererUtilities line: 91
//    out.normal = uniforms.normalMatrix * primaryLocalNormal;//mix(primaryLocalNormal, secondarLocalNormal, 0.5);

    constexpr sampler normalSampler(min_filter::linear, mag_filter::linear, mip_filter::nearest);
    float3 normalValue = normalize(normalMap.sample(normalSampler, xy).xzy * 2.0f - 1.0f);
    float3 normal = uniforms.normalMatrix * normalValue;

    out.normal = normal;
    out.normal_cameraSpace = (normalize(uniforms.modelMatrix * float4(normal, 0.0))).xyz;
    float3 vertex_position_cameraspace = ( uniforms.viewMatrix * uniforms.modelMatrix * position ).xyz;
    out.eye_direction_cameraspace = float3(0,0,0) - vertex_position_cameraspace;
//    finalColor += float4(0.1, 0.6, 0.988, 1);
    out.color = finalColor;
    
    out.worldPosition = uniforms.modelMatrix * position;

    // Imaginary world position if the terrain was a child of the scaffolding.
    // World position to create texture coordinates
    
                                /// Imaginary position               // fragment position
                                // scaffolding * terrain
    
    /// This is just the world position of terrain if terrain were a child of scaffolding
    out.parentFragmentPosition = uniforms.parentTreeModelMatrix * position;
    /// ^^^ forget about this for now
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
                                 texture2d<float> landTexture [[ texture(TextureIndexScaffoldLand) ]],
                                 sampler scaffoldingSampler [[ sampler(0) ]])
{
    constexpr sampler mainSampler(filter::linear, address::repeat);
    float width = float(reflectionTexture.get_width() * 2.0);
    float height = float(reflectionTexture.get_height() * 2.0);
    float x = fragment_in.position.x / width;
    float y = fragment_in.position.y / height;
    float z = fragment_in.position.z / height;
    float2 reflectionCoords = float2(x, 1 - y);
    float2 refractionCoords = float2(x, y);
    
    float4 directionToFragment = fragment_in.parentFragmentPosition - fragmentUniforms.scaffoldingPosition;
    float4 terrainToScaffold = normalize(directionToFragment);
    float4 scaffoldSample = worldMapTexture.sample(scaffoldingSampler, terrainToScaffold.xyz);
    // so that white is 0 and black is one
    float4 invertedScaffoldColor = (1 - scaffoldSample);
    // transform to -1 to 1 * constant variable
    float4 scaffoldHeight = (invertedScaffoldColor * 2 - 1) * terrainParams.height;
    
    
    // Multiplier determines ripple size
    float timer = uniforms.currentTime * 0.007;
    float2 rippleUV = fragment_in.uv * 0.5;
    float waveStrength = 0.1;
    float2 rippleX = float2(rippleUV.x/* + timer*/, rippleUV.y) + timer;
    float2 rippleY = float2(rippleUV.x - timer, rippleUV.y);

    float4 rippleSampleX = waterRippleTexture.sample(mainSampler, rippleX);
    float4 rippleSampleY = waterRippleTexture.sample(mainSampler, rippleY);
    float2 normalizedRippleX = rippleSampleX.rg * 2.0 - 1.0;
    float2 normalizedRippleY = rippleSampleY.rg * 2.0 - 1.0;

    // Is the problem that scaffold is a world map so i'm using 3d coords
    // And this is a 2d texture so i'm using refractionCoords
    // Maybe i can just take this from vertex shader - since this should map to position.y.
    // so maybe check position.y & scaffold height.// But then it will just be the scaffold height from vertex so idk.
    
    // TEST - ONLY USE SCAFFOLD HEIGHT IN THE VERTEX.
    // THAN GRAB THE SCAFFOLD WORLD HEIGHT HERE & CHECK TO MAKE SURE THEY ARE KINDA THE SAME.
    // THAN DO THE SAME THING WITH THE POSITION.Y & THE WORLDIFFTHEIGHT DAWGGGGGGG
    // THAN NEED TO JUST DECIDE? IDK - FIGURE IT OUT FROM THERE DIPSHIT
    float4 heightDisplacement = heightMap.sample(mainSampler, refractionCoords);
    float4 ifftHeight = (heightDisplacement * 2 - 1) * terrainParams.height;
    float4 ifftPercentHeight = ifftHeight * scaffoldSample.r;
    
    float4 landWater = landTexture.sample(mainSampler, refractionCoords);
    // Do this before clamping yo
    // I think i need to do a worldPosition comparision though.
    // Cause it gets all squirrely when I compare height maps
    float4 scaffoldPosition = fragmentUniforms.scaffoldingPosition;
    scaffoldPosition.y += scaffoldHeight.r;
    float4 scaffoldWorldPositions = uniforms.modelMatrix * scaffoldPosition;
    float diff = abs(scaffoldWorldPositions.y - fragment_in.worldPosition.y);
    
    // Do a more relaxed check yo. like.....chill out dawg
    if (diff > 1.0) {
        
        float2 ripple = (normalizedRippleX + normalizedRippleY) * waveStrength;
        reflectionCoords += ripple;
        refractionCoords += ripple;
        landWater = float4(0.8, 0.4, 0.6, 1.0);
    }

    reflectionCoords = clamp(reflectionCoords, 0.001, 0.999);
    refractionCoords = clamp(refractionCoords, 0.001, 0.999);

//    float4 mixedColor = reflectionTexture.sample(reflectionSampler, reflectionCoords);
//    float4 mixedColor = refractionTexture.sample(mainSampler, refractionCoords);
    float3 viewVector = normalize(fragment_in.toCamera);
    float mixRatio = dot(viewVector, float3(0.0, 1.0, 0.0));
    float4 mixedColor = mix(reflectionTexture.sample(mainSampler, reflectionCoords),
                            refractionTexture.sample(mainSampler, refractionCoords),
                            mixRatio);

//    if (scaffoldHeight >= 0) {
//        mixedColor = mix(mixedColor, float4(0.1, scaffoldSample.r, 0.1, 1), 0.3);
//    } else {
//        mixedColor = mix(mixedColor, float4(0.2, 0.2, 0.6, 1), 0.3);
//    }
    
    
    mixedColor = mix(mixedColor, landWater, 0.6);
    
//    mixedColor = fragment_in.landColor;

    constexpr sampler sam(min_filter::linear, mag_filter::linear, mip_filter::nearest, address::repeat);
    float3 vGradJacobian = gradientMap.sample(sam, fragment_in.vGradNormalTex.xy).xyz;
    float2 noise_gradient = 0.3 * normalMap.sample(sam, fragment_in.vGradNormalTex.zw).xy;
    float3 normalValue = normalMap.sample(mainSampler, fragment_in.uv).xzy;
    
    float jacobian = vGradJacobian.z;
    float turbulence = max(2.0 - jacobian + dot(abs(noise_gradient.xy), float2(1.2)), 0.0);
    
    
    // This is from example but not sure if i can use it \\
//    float3 normal = float3(-vGradJacobian.x, 1.0, -vGradJacobian.y);
//    normal.xz -= noise_gradient;
//    normal = normalize(normal);

//  Need to double check creation of gradient map
//    float color_mod = 1.0  * smoothstep(1.3, 1.8, turbulence);
//
    float3 specular = terrainDiffuseLighting(uniforms.normalMatrix * (normalValue * 2.0f - 1.0f), fragment_in.position.xyz, fragmentUniforms, lights, mixedColor.rgb);

    return float4(specular, 1.0);
}


float normalCoordinates(uint2 coords, texture2d<float> map, sampler s, float delta)
{

    float2 xy = float2(coords.x, coords.y);
    xy.x = fmod(xy.x + delta, 1);
    float4 d = map.sample(s, xy);

    return d.r;
}

// This is pulled directly from apples example: DynamicTerrainWithArgumentBuffers
// Should move this to BasicFFT
//kernel void TerrainKnl_ComputeNormalsFromHeightmap(texture2d<float> height [[texture(0)]],
//                                                   texture2d<float, access::write> normal [[texture(2)]],
//                                                   constant TerrainParams &terrain [[ buffer(3) ]],
//                                                   constant Uniforms &uniforms [[ buffer(BufferIndexUniforms) ]],
//                                                   uint2 tid [[thread_position_in_grid]])
//{
//    constexpr sampler sam(min_filter::nearest, mag_filter::nearest, mip_filter::none,
//                          address::clamp_to_edge, coord::pixel);
//
//
//
////    constexpr sampler sam(filter::linear);
////    float xz_scale = TERRAIN_SCALE / height.get_width();
//    float xz_scale = terrain.size.x / height.get_width();
//    float y_scale = terrain.height;
//
//    if (tid.x < height.get_width() && tid.y < height.get_height()) {
//        // I think we can just compute the normals once for each map - pass both maps into the vertex shader
//        // And mix the two samples. Don't need to do anything else other than handle the mix between maps & fmod something...
////        // Which we're already doing in the vertex shader. So I think we can just add an altNormalMap to the vetex shader & use that for secondary shader
//
//        float h_up     = height.sample(sam, (float2)(tid + uint2(0, 1))).r;
//        float h_down   = height.sample(sam, (float2)(tid - uint2(0, 1))).r;
//        float h_right  = height.sample(sam, (float2)(tid + uint2(1, 0))).r;
//        float h_left   = height.sample(sam, (float2)(tid - uint2(1, 0))).r;
//        float h_center = height.sample(sam, (float2)(tid + uint2(0, 0))).r;
//
//        float3 v_up    = float3( 0,        (h_up    - h_center) * y_scale,  xz_scale);
//        float3 v_down  = float3( 0,        (h_down  - h_center) * y_scale, -xz_scale);
//        float3 v_right = float3( xz_scale, (h_right - h_center) * y_scale,  0);
//        float3 v_left  = float3(-xz_scale, (h_left  - h_center) * y_scale,  0);
//
//        float3 n0 = cross(v_up, v_right);
//        float3 n1 = cross(v_left, v_up);
//        float3 n2 = cross(v_down, v_left);
//        float3 n3 = cross(v_right, v_down);
//
//        float3 n = normalize(n0 + n1 + n2 + n3) * 0.5f + 0.5f;
//
//        normal.write(float4(n.xzy, 1), tid);
//    }
//}

// Original
kernel void TerrainKnl_ComputeNormalsFromHeightmap(texture2d<float> height [[texture(0)]],
                                                   texture2d<float, access::write> normal [[texture(2)]],
                                                   constant TerrainParams &terrain [[ buffer(3) ]],
                                                   uint2 tid [[thread_position_in_grid]])
{
    constexpr sampler sam(min_filter::nearest, mag_filter::nearest, mip_filter::none,
                          address::clamp_to_edge, coord::pixel);

//    float xz_scale = TERRAIN_SCALE / height.get_width();
    float xz_scale = terrain.size.x / height.get_width();
    float y_scale = terrain.height;

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
