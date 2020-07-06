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
    BufferIndexTerrainParams    = 16
};

typedef NS_ENUM(NSInteger, VertexAttribute)
{
    VertexAttributePosition  = 0,
    VertexAttributeNormal    = 1,
    VertexAttributeUV        = 2,
    VertexAttributeTangent   = 3,
    VertexAttributeBitangent = 4
};

typedef NS_ENUM(NSInteger, TextureIndex)
{
    TextureIndexColor    = 0,
    TextureIndexNormal   = 1
};

typedef struct
{
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 viewMatrix;
    matrix_float4x4 modelMatrix;
    matrix_float3x3 normalMatrix;
    float deltaTime;
} Uniforms;

typedef struct
{
    uint light_count;
    vector_float3 camera_position;
    uint tiling;
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
    float shininess;
} Material;

typedef struct {
    vector_float2 size;
    float height;
    uint maxTessellation;
    uint numberOfPatches;
} TerrainParams;

#endif /* ShaderTypes_h */

