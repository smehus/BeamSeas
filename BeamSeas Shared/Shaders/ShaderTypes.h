//
//  ShaderTypes.h
//  BeamSeas Shared
//
//  Created by Scott Mehus on 6/15/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

//
//  Header containing types and enum constants shared between Metal shaders and Swift/ObjC source
//
#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
#else
#import <Foundation/Foundation.h>
#import "NormalDistributionBridge.h"
#endif

#include <simd/simd.h>


typedef NS_ENUM(NSInteger, BufferIndex)
{
    BufferIndexVertexBuffer     = 0,
    BufferIndexUniforms         = 11,
    BufferIndexLights           = 12,
    BufferIndexFragmentUniforms = 13,
    BufferIndexMaterials        = 14,
    BufferIndexControlPoints    = 15,
    BufferIndexTerrainParams    = 16,
    BufferIndexGausUniforms     = 17,
    BufferIndexViewport         = 18
};

typedef NS_ENUM(NSInteger, VertexAttribute)
{
    VertexAttributePosition  = 0,
    VertexAttributeNormal    = 1,
    VertexAttributeUV        = 2,
    VertexAttributeTangent   = 3,
    VertexAttributeBitangent = 4,
    VertexAttributeColor     = 5
};

typedef NS_ENUM(NSInteger, TextureIndex)
{
    TextureIndexColor           = 0,
    TextureIndexNormal          = 1,
    TextureIndexPrimarySlope    = 2,
    TextureIndexSecondarySlope  = 3,
    TextureIndexSkybox          = 4,
    TextureIndexReflection      = 5,
    TextureIndexWaterRipple     = 6,
    TextureIndexRefraction      = 7,
    TextureIndexWorldMap        = 8,
    TextureIndexHeight          = 9,
    TextureIndexGradient        = 10,
    TextureIndexScaffoldLand    = 11
};

typedef struct
{
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 viewMatrix;
    matrix_float4x4 modelMatrix;
    matrix_float3x3 normalMatrix;
    matrix_float4x4 parentTreeModelMatrix; // Used when you want to do some logic with the positons mapped to parent coordinates. But also want to render
    // the object in a different coord space.
    float currentTime;
    vector_float3 playerMovement;
    vector_float4 clipPlane;
    uint distrubtionSize;
} Uniforms;

typedef struct
{
    int dataLength;
    float amplitude;
//    vector_float2 wind_velocity;
    vector_uint2 resolution;
    vector_float2 size;
    vector_float2 normalmap_freq_mod;
    int seed;
} GausUniforms;

typedef struct
{
    uint light_count;
    vector_float3 camera_position;
    uint tiling;
    vector_float4 scaffoldingPosition;
} FragmentUniforms;

typedef enum {
    unused = 0,
    Sunlight = 1,
    Spotlight = 2,
    Pointlight = 3,
    Ambientlight = 4
} LightType;

typedef struct {
    vector_float3 position;
    vector_float3 color;
    vector_float3 specularColor;
    float intensity;
    vector_float3 attenuation;
    LightType type;
    float coneAngle;
    vector_float3 coneDirection;
    float coneAttenuation;
} Light;

typedef struct {
    vector_float3 baseColor;
    vector_float3 specularColor;
    float roughness;
    float metallic;
    vector_float3 ambientOcclusion;
    float shininess;
} Material;

typedef struct {
    vector_float2 size;
    float height;
    uint maxTessellation;
    uint numberOfPatches;
    vector_flot2 normal_scale;
} TerrainParams;

#endif /* ShaderTypes_h */

