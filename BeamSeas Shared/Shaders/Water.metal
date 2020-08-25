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

int alias(int x, int N) {
    if (x > (N / 2)) { x -= N; }
    return x;
}

float rand(int x, int y, int z)
{
    int seed = x + y * 57 + z * 241;
    seed= (seed<< 13) ^ seed;
    return (( 1.0 - ( (seed * (seed * seed * 15731 + 789221) + 1376312589) & 2147483647) / 1073741824.0f) + 1.0f) / 2.0f;
}

float phillips(float2 k, float max_l, float L, float2 wind_dir) {
    float k_len = length(k);
    if (k_len == 0) {
        return 0.0;
    }

    float kL = k_len * L;
    float2 k_dir = normalize(k);
    float kw = dot(k_dir, wind_dir);

    return
    pow(kw * kw, 1.0) *
    exp(-1 * k_len * k_len * max_l * max_l) *
    exp(-1 / (kL * kL)) *
    pow(k_len, -4.0);
}

float2 vecAlias(uint2 i, uint2 N)
{
    float2 n = 0.5 * float2(N);
    bool2 b = float2(i) > n;

    return mix(float2(i), float2(i - N), float2(b));
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
                                  uint2 pid [[ thread_position_in_grid ]])
{
    float2 size = uniforms.size;
    float G = 9.81; // Gravity
    float amplitude = uniforms.amplitude;

    amplitude *= 0.3 / sqrt(size.x * size.y);

    // Pick out the negative frequency variant.
    float2 wi = mix(float2(uniforms.resolution - pid),
                    float2(0u),
                    float2(pid == uint2(0u)));

    int width = uniforms.resolution.x;
    int height = uniforms.resolution.y;


//    // Pick out positive and negative travelling waves.

    int index = (int)pid.y * width + pid.x;
    int bIndex =  (int)wi.y * width + wi.x;

    float a1 = input_real[index];
    float a2 = input_imag[index];
    float2 a = float2(a1, a2);

    float b1 = input_real[bIndex];
    float b2 = input_imag[bIndex];
    float2 b = float2(b1, b2);

    float2 uMod = float2(2.0 * M_PI_F) / uniforms.size;


    float2 k = uMod * vecAlias(pid, uint2(width, height));
    float k_len = length(k);
    // If this sample runs for hours on end, the cosines of very large numbers will eventually become unstable.
    // It is fairly easy to fix this by wrapping uTime,
    // and quantizing w such that wrapping uTime does not change the result.
    // See Tessendorf's paper for how to do it.
    // The sqrt(G * k_len) factor represents how fast ocean waves at different frequencies propagate.
    float w = sqrt(G * k_len) * (mainUniforms.deltaTime * 0.003);
    float cw = cos(w);
    float sw = sin(w);

    // Complex multiply to rotate our frequency samples.

    a = cmul(a, float2(cw, sw));
    b = cmul(b, float2(cw, sw));
    b = float2(b.x, -b.y); // Complex conjugate since we picked a frequency with the opposite direction.
    float2 res = (a + b); // Sum up forward and backwards travelling waves.

    output_real[index] = res.x;
    output_imag[bIndex] = res.y;
}

kernel void generate_displacement_map_values(constant GausUniforms &uniforms [[ buffer(BufferIndexGausUniforms) ]],
                                  constant Uniforms &mainUniforms [[ buffer(BufferIndexUniforms) ]],
                                  device float *output_real [[ buffer(12) ]],
                                  device float *output_imag [[ buffer(13) ]],
                                  texture2d<float> drawTexture [[ texture(0) ]],
                                  device float *input_real [[ buffer(14) ]],
                                  device float *input_imag [[ buffer(15) ]],
                                  uint2 i [[ thread_position_in_grid ]])
{

    uint2 N = uniforms.resolution;
    float2 uMod = float2(2.0 * M_PI_F) / uniforms.size;
    int width = uniforms.resolution.x;
    int height = uniforms.resolution.y;

    uint2 wi = uint2(mix(float2(N - i),
                    float2(0u),
                    float2(i == uint2(0u))));

    float aReal = input_real[i.y * N.x + i.x];
    float aImag = input_imag[i.y * N.x + i.x];
    float2 a = float2(aReal, aImag);

    float bReal = input_real[wi.y * N.x + wi.x];
    float bImag = input_imag[wi.y * N.x + wi.x];
    float2 b = float2(bReal, bImag);

    float2 k = uMod * vecAlias(i, uint2(width, height));
    float k_len = length(k);

    const float G = 9.81;
    float w = sqrt(G * k_len) * (mainUniforms.deltaTime * 0.003); // Do phase accumulation later ...

    float cw = cos(w);
    float sw = sin(w);

    a = cmul(a, float2(cw, sw));
    b = cmul(b, float2(cw, sw));
    b = float2(b.x, -b.y);
    float2 res = a + b;

    float2 grad = cmul(res, float2(-k.y / (k_len + 0.00001), k.x / (k_len + 0.00001)));
    output_real[i.y * N.x + i.x] = grad.x;
    output_imag[i.y * N.x + i.x] = grad.y;
}


//kernel void generate_normals

half jacobian(half2 dDdx, half2 dDdy)
{
    return (1.0 + dDdx.x) * (1.0 + dDdy.y) - dDdx.y * dDdy.x;
}

kernel void compute_height_graident(uint2 pid [[ thread_position_in_grid]],
                                    constant float4 &uInvSize [[ buffer(0) ]],
                                    constant float4 &uScale [[ buffer(1) ]],
                                    texture2d<float> heightMap [[ texture(0) ]],
                                    texture2d<float> displacementMap [[ texture(1) ]],
                                    texture2d<float, access::write> heightDisplacementMap [[ texture(2) ]],
                                    texture2d<float, access::write> gradientMap [[ texture(3) ]])
{

    constexpr sampler s;
    float4 uv = (float2(pid.xy) * uInvSize.xy).xyxy + 0.5 * uInvSize;

    float h = heightMap.sample(s, uv.xy).r;
    float displacement = displacementMap.sample(s, uv.xy).r;

    float x0 = heightMap.sample(s, (float2)uv.xy + float2(-1, 0)).r;
    float x1 = heightMap.sample(s, (float2)uv.xy + float2(+1, 0)).r;
    float y0 = heightMap.sample(s, (float2)uv.xy + float2(0, -1)).r;
    float y1 = heightMap.sample(s, (float2)uv.xy + float2(0, +1)).r;
    float2 grad = uScale.xy * 0.5 * float2(x1 - x0, y1 - y0);

    // Compute jacobian.
    float2 dDdx = 0.5 * (displacementMap.sample(s, uv.zw + float2(+1, 0)).xy - displacementMap.sample(s, uv.zw + float2(-1, 0)).xy);
    float2 dDdy = 0.5 * (displacementMap.sample(s, uv.zw + float2(0, +1)).xy - displacementMap.sample(s, uv.zw + float2(0, -1)).xy);
    float j = jacobian(half2(dDdx * uScale.z), half2(dDdy * uScale.z));


    // write to heightDisplacement texture for final sampling in vertex
    // Wait wat, we're drawing the texture in the bottom method
    // This needs to be rethought through
    // Can i just use one map that already has displacement & height?
    float heighDis = mix(h, displacement, 0.3);
    heightDisplacementMap.write(float4(heighDis, heighDis, heighDis, 1), pid);

    // write to gradient texture for final sampling in fragment
    gradientMap.write(float4(grad, j, 0.0), pid);
}

vertex FFTVertexOut fft_vertex(const FFTVertexIn in [[ stage_in ]],
                               constant Uniforms &uniforms [[ buffer(BufferIndexUniforms) ]],
                               texture2d<float> noiseMap [[ texture(8) ]],
                               constant float2 &viewPort [[ buffer(22) ]]) {
    return {
        .position = uniforms.modelMatrix * in.position,
        .textureCoordinates =  in.position.xy
    };
}

fragment float4 fft_fragment(const FFTVertexOut in [[ stage_in ]],
                             constant Uniforms &uniforms [[ buffer(BufferIndexUniforms)]],
                             constant float2 &viewPort [[ buffer(22) ]],
                             texture2d<float> noiseMap [[ texture(0) ]],
                             texture2d<float> testMap [[ texture(1) ]]) {
    constexpr sampler sam;
//    float2 normTex = in.textureCoordinates.xy;
//    normTex = normTex * 0.5 + 0.5;
    float2 tex = in.position.xy / viewPort;
    float4 color = noiseMap.sample(sam, tex);

    return float4(color.xyz, 1.0);
}

kernel void fft_kernel(texture2d<float, access::write> output_height [[ texture(0) ]],
                       texture2d<float, access::write> output_displacement [[ texture(1) ]],
                       uint2 tid [[ thread_position_in_grid]],
                       constant float *data [[ buffer(0) ]],
                       constant float *displacement [[ buffer(1) ]],
                       constant Uniforms &uniforms [[ buffer(3) ]],
                       constant GausUniforms &gausUniforms [[ buffer(4)]])
{
    // this will work because both height and displacement are the same size
    // In the future when i downsample displacement - this will need to be updated
    uint width = output_height.get_width();
    uint height = output_height.get_height();


    if (tid.x < width && tid.y < height) {

        uint index = (uint)(tid.y * width + tid.x);
        float val = data[index];
        float displace = displacement[index];
//         maybe write out both height & displacement textures separately here?

        output_height.write(float4(val, val, val, 1), tid);
        output_displacement.write(float4(displace, displace, displace, 1), tid);
    }
}
