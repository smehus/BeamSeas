//
//  Water.metal
//  BeamSeas
//
//  Created by Scott Mehus on 8/6/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderTypes.h"

struct FFTVertexOut {
    float4 position [[ position ]];
    float2 textureCoordinates;
};

struct FFTVertexIn {
    float4 position [[ attribute(VertexAttributePosition) ]];
};

float2 alias(float2 i, float2 N)
{
    float x = i.x > (0.5 * N.x);
    float y = i.y > (0.5 * N.y);

    return mix(i, i - N, float2(x, y));
}

float4 cmul(float4 a, float4 b)
{
    float4 r3 = a.yxwz;
    float4 r1 = b.xxzz;
    float4 R0 = a * r1;
    float4 r2 = b.yyww;
    float4 R1 = r2 * r3;
    return R0 + float4(-R1.x, R1.y, -R1.z, R1.w);
}

float2 cmul(float2 a, float2 b)
{
    float2 r3 = a.yx;
    float2 r1 = b.xx;
    float2 R0 = a * r1;
    float2 r2 = b.yy;
    float2 R1 = r2 * r3;
    return R0 + float2(-R1.x, R1.y);
}

kernel void generate_distribution_map_values(constant GausUniforms &uniforms [[ buffer(BufferIndexGausUniforms) ]],
                                  constant Uniforms &mainUniforms [[ buffer(BufferIndexUniforms) ]],
                                  device float *output_real [[ buffer(12) ]],
                                  device float *output_imag [[ buffer(13) ]],
                                  texture2d<float> drawTexture [[ texture(0) ]],
                                  device float *input_real [[ buffer(14) ]],
                                  device float *input_imag [[ buffer(15) ]],
                                  uint2 i [[ thread_position_in_grid ]])
{
    uint2 N = uniforms.resolution;
    float G = 9.81; // Gravity
    float2 uMod = float2(2.0 * M_PI_F) / uniforms.size;

    // Pick out the negative frequency variant.
    float2 wi = mix(float2(N - i),
                    float2(0u),
                    float2(i == uint2(0u)));


//    // Pick out positive and negative travelling waves.

    int index = (int)i.y * N.x + i.x;
    int bIndex =  (int)wi.y * N.x + wi.x;

    float a1 = input_real[index];
    float a2 = input_imag[index];
    float2 a = float2(a1, a2);

    float b1 = input_real[bIndex];
    float b2 = input_imag[bIndex];
    float2 b = float2(b1, b2);

    float2 k = uMod * alias(float2(i), float2(N));
    float k_len = length(k);
    // If this sample runs for hours on end, the cosines of very large numbers will eventually become unstable.
    // It is fairly easy to fix this by wrapping uTime,
    // and quantizing w such that wrapping uTime does not change the result.
    // See Tessendorf's paper for how to do it.
    // The sqrt(G * k_len) factor represents how fast ocean waves at different frequencies propagate.
    float w = sqrt(G * k_len) * (mainUniforms.currentTime);
    float cw = cos(w);
    float sw = sin(w);

    // Complex multiply to rotate our frequency samples.

    a = cmul(a, float2(cw, sw));
    b = cmul(b, float2(cw, sw));
    b = float2(b.x, -b.y); // Complex conjugate since we picked a frequency with the opposite direction.
    float2 res = (a + b); // Sum up forward and backwards travelling waves.

    output_real[i.y * N.x + i.x] = res.x;
    output_imag[i.y * N.x + i.x] = res.y;
}

kernel void generate_displacement_map_values(constant GausUniforms &uniforms [[ buffer(BufferIndexGausUniforms) ]],
                                             constant Uniforms &mainUniforms [[ buffer(BufferIndexUniforms) ]],
                                             device float *output_real [[ buffer(12) ]],
                                             device float *output_imag [[ buffer(13) ]],
                                             texture2d<float> drawTexture [[ texture(0) ]],
                                             device float *input_real [[ buffer(14) ]],
                                             device float *input_imag [[ buffer(15) ]],
                                             uint2 i [[ thread_position_in_grid ]],
                                            uint2 thread_size [[ threads_per_grid ]])
{
    float2 uMod = float2(2.0f * M_PI_F) / uniforms.size;
//    uint2 resolution = uniforms.resolution >> 1;
    uint2 N = uniforms.resolution >> 1;//uint2(64, 1) * thread_size;

    // I think this just uses 0 if i === 0
    float2 wi = mix(float2(N - i),
                    float2(0u),
                    float2(i == uint2(0u)));

    uint aIndex = i.y * N.x + i.x;
    uint bIndex = wi.y * N.x + wi.x;

//    if (aIndex > 16383) { return; }
//    if (bIndex > 16383) { return; }

    float aReal = input_real[aIndex];
    float aImag = input_imag[aIndex];
    float bReal = input_real[bIndex];
    float bImag = input_imag[bIndex];

    float2 k = uMod * alias(float2(i), float2(N));
    float k_len = length(k);

    float G = 9.81;
    float w = sqrt(G * k_len) * (mainUniforms.currentTime);

    float cw = cos(w);
    float sw = sin(w);

    float2 a = cmul(float2(aReal, aImag), float2(cw, sw));
    float2 b = cmul(float2(bReal, bImag), float2(cw, sw));
    float2 res = a + b;

     float2 grad = cmul(res, float2(-k.y / (k_len + 0.0000000000001), k.x / (k_len + 0.0000000000001)));

    output_real[i.y * N.x + i.x] = grad.x;
    output_imag[i.y * N.x + i.x] = grad.y;
}


//kernel void generate_normals

half jacobian(half2 dDdx, half2 dDdy)
{
    return (1.0 + dDdx.x) * (1.0 + dDdy.y) - dDdx.y * dDdy.x;
}

#define LAMBDA -4.6

kernel void compute_height_displacement_graident(uint2 pid [[ thread_position_in_grid]],
                                    constant float4 &uInvSize [[ buffer(0) ]],
                                    constant float4 &uScale [[ buffer(1) ]],
                   	                 texture2d<float> heightMap [[ texture(0) ]],
                                    texture2d<float> displacementMap [[ texture(1) ]],
                                    texture2d<float, access::write> heightDisplacementMap [[ texture(2) ]],
                                    texture2d<float, access::write> gradientMap [[ texture(3) ]])
{

    constexpr sampler s;
    float4 uv = (float2(pid.xy) * uInvSize.xy).xyxy;

    float h = heightMap.sample(s, uv.xy).r;

    float x0 = heightMap.sample(s, (float2)uv.xy + float2(-1, 0)).x;
    float x1 = heightMap.sample(s, (float2)uv.xy + float2(1, 0)).x;
    float y0 = heightMap.sample(s, (float2)uv.xy + float2(0, -1)).x;
    float y1 = heightMap.sample(s, (float2)uv.xy + float2(0, 1)).x;
    float2 grad = uScale.xy * 0.5 * float2(x1 - x0, y1 - y0);

    // Displacement map must be sampled with a different offset since it's a smaller texture.
    float2 displacement = LAMBDA * displacementMap.sample(s, uv.zw).xy;
    // Compute jacobian.
    float2 dDdx = 0.5 * LAMBDA * (
                                  displacementMap.sample(s, uv.zw + float2(1, 0)).xy -
                                  displacementMap.sample(s, uv.zw + float2(-1, 0)).xy);
    float2 dDdy = 0.5 * LAMBDA * (
                                  displacementMap.sample(s, uv.zw + float2(0,   1)).xy -
                                  displacementMap.sample(s, uv.zw + float2(0, -1)).xy);

    float j = jacobian(half2(dDdx * uScale.z), half2(dDdy * uScale.z));

    heightDisplacementMap.write(float4(h, h, h, 0.0), pid);

    // write to gradient texture for final sampling in fragment
    gradientMap.write(float4(grad, j, 0.0), pid);
}

vertex FFTVertexOut fft_vertex(const FFTVertexIn in [[ stage_in ]],
                               constant Uniforms &uniforms [[ buffer(BufferIndexUniforms) ]],
                               texture2d<float> noiseMap [[ texture(8) ]],
                               constant float2 &viewPort [[ buffer(BufferIndexViewport) ]]) {
    return {
        .position = uniforms.modelMatrix * in.position,
        .textureCoordinates =  in.position.xy
    };
}

fragment float4 fft_fragment(const FFTVertexOut in [[ stage_in ]],
                             constant Uniforms &uniforms [[ buffer(BufferIndexUniforms)]],
                             constant float2 &viewPort [[ buffer(BufferIndexViewport) ]],
                             texture2d<float> noiseMap [[ texture(0) ]],
                             texture2d<float> testMap [[ texture(1) ]]) {
    constexpr sampler sam;

    float2 xy;
    float3 screenCoord = uniforms.modelMatrix.columns[3].xyz;
    float width = viewPort.x * 0.25;
    float height = viewPort.y * 0.25;

    if (screenCoord.y == 0.25) {
        float yOrigin = viewPort.y * screenCoord.y;

        float x = in.position.x / width;
        float normalizedY = in.position.y - yOrigin;
        float y = normalizedY / height;
        xy = float2(x, y);
    } else {
        float x = in.position.x / width;
        float y = in.position.y / height;
        xy = float2(x, y);
    }

    float4 color = noiseMap.sample(sam, xy);

    return float4(color.xyz, 1.0);
}

kernel void fft_kernel(texture2d<float, access::write> output_texture [[ texture(0) ]],
                       constant Uniforms &uniforms [[ buffer(BufferIndexUniforms) ]],
                       uint2 tid [[ thread_position_in_grid]],
                       constant float *data [[ buffer(0) ]])
{
    uint width = output_texture.get_width();
    uint height = output_texture.get_height();

    // output_text: 512
    // data:        128
    // Data is 1/4 the size of the image
    // Need to divide index by 4 & then mix between whole number max / min
    // No, wait, i need to multiplyl the tid by 4
    
    // TID SHOULD MATCH TEXTURE YO
    // with the tid being correct - or the right amount of data - can we just use that and not have to fuck up the index with width?
    // or... something
    
    float scale = 0.25;//width / uniforms.distrubtionSize;
    float2 distributionTID = float2(tid) * scale;
    uint gridWidth = uniforms.distrubtionSize - 1;
    
    // Index calculations
    uint distributionFloorY = (uint)floor(distributionTID.y);
    uint distributionCeilY = (uint)ceil(distributionTID.y);
    uint textureFloorY = distributionFloorY / scale;
    uint textureCeilY = distributionCeilY / scale;
    
    // How many texture coordinate units will equate to moving on distribution unit (scale is 0.25, 128 vs 512)
    uint yChunk = textureCeilY - textureFloorY;
    // Where the kernel tid (texture tid) fits  in the range of of yChunke
    // if we break up the texture tid total (512, texture width) into chunks of 8.
    // Which chunk of 8 does the current tid fit in.
    // And how far in that range are we. between 0 - 8.
    uint yPosition = yChunk - (textureCeilY - tid.y);
    
    // Floor and ceil shoudl be one off here. But they fucking aren't. Stupid maths.
    // wait.... maybe they are supposed be way different because
    // We're thinking inside the texture. So we need one y row above. Which is not 
    uint floorYIndex = (uint)distributionFloorY * gridWidth + distributionTID.x;
    uint ceilYIndex = (uint)distributionCeilY * gridWidth + distributionTID.x;
    float floorYVal = data[floorYIndex];
    float ceilYVal = data[ceilYIndex];
    float yVal = mix(floorYVal, ceilYVal, yPosition / yChunk);
    
    
    uint distributionFloorX = (uint)floor(distributionTID.x);
    uint distributionCeilX = (uint)ceil(distributionTID.x);
    uint textureFloorX = distributionFloorX / scale;
    uint textureCeilX = distributionCeilX / scale;
    uint xChunk = textureCeilX - textureFloorX;
    uint xPosition = xChunk - (textureCeilX - tid.x);
    
    gridWidth += 1; // i don't know why - maths
    uint floorXIndex = (uint)distributionTID.y * gridWidth + distributionFloorX;
    uint ceilXIndex = (uint)distributionTID.y * gridWidth + distributionCeilX;
    float floorXVal = data[floorXIndex];
    float ceilXVal = data[ceilXIndex];
    float xVal = mix(floorXVal, ceilXVal, xPosition / xChunk);
    
    float val = mix(xVal, yVal, 0.5);
    val = (val - -1) / (1 - -1);
    output_texture.write(float4(val, val, val, 1), tid);
    
    // I THINK THIS IS SLOW AND SHITTY BECAUSE I'M INDEXING OUT OF BOUNDS YO \\
}
