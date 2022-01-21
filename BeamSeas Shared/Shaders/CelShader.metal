////
////  CelShader.metal
////  BeamSeas
////
////  Created by Scott Mehus on 1/19/22.
////  Copyright © 2022 Scott Mehus. All rights reserved.
////
//
//#include <metal_stdlib>
//using namespace metal;
//#import "ShaderTypes.h"
//
//
//constant float4 materialAmbientColor = {0.18, 0.18, 0.18, 1.0};
//constant float4 materialDiffuseColor = {0.4, 0.4, 0.4, 1.0};
//constant float4 materialSpecularColor = {1.0, 1.0, 1.0, 1.0};
//constant float  materialShine = 50.0;
//constant float d1 = 0.1;
//constant float d2 = 0.6;
//constant float d3 = 1.0;
//
//
//float4 celDiffuseLighting(float3 normal,
//                          float4 mixedColor,
//                          float3 position,
//                          float3 normal_cameraSpace,
//                          float3 eye_direction_cameraspace,
//                          constant Uniforms &uniforms,
//                          constant FragmentUniforms &fragmentUniforms,
//                          constant Light *lights,
//                          float3 baseColor) {
//    float4 ambient_color = mixedColor;
//    float3 n = normalize(normal_cameraSpace);
//
//    //    for (uint i = 0; i < fragmentUniforms.light_count; i++) {
//        Light light = lights[0];
//
//        float3 light_position_cameraspace = ( uniforms.modelMatrix * float4(light.position, 1)).xyz;
//        float3 light_direction_cameraspace = light_position_cameraspace + normalize(light.position); // This is probably wrong yo
//        float3 l = normalize(light_direction_cameraspace);
//        float n_dot_l = dot(n, l);
//
//        float diffuse_factor = saturate(n_dot_l);
//        float epsilon = fwidth(diffuse_factor);
//        // If it is on the border of the first two colors, smooth it
//        if ( (diffuse_factor > d1 - epsilon) && (diffuse_factor < d1 + epsilon) )
//        {
//            diffuse_factor = mix(d1, d2, smoothstep(d1-epsilon, d1+epsilon, diffuse_factor));
//        }
//        // If it is on the border of the second two colors, smooth it
//        else if ( (diffuse_factor > d2 - epsilon) && (diffuse_factor < d2 + epsilon) )
//        {
//            diffuse_factor = mix(d2, d3, smoothstep(d2-epsilon, d2+epsilon, diffuse_factor));
//        }
//        // If it is the darkest color
//        else if (diffuse_factor < d1)
//        {
//            diffuse_factor = 0.0;
//        }
//        // If is is the mid-range color
//        else if (diffuse_factor < d2)
//        {
//            diffuse_factor = d2;
//        }
//        // It is the brightest color
//        else
//        {
//            diffuse_factor = d3;
//        }
//
//        float4 diffuse_color = float4(light.color, 1.0) * diffuse_factor * materialDiffuseColor;
//
//        // Calculate the specular color. This is done in a similar fashion to how the diffuse color
//        // is calculated. We see if the angle between the viewer and the reflected light is small. If
//        // is it, we color it the specular color. If it is on the border of the specular highlight
//        // (i.e. it is within an epsilon value we define as the derivative of the specular factor),
//        // we linearly interpolate between the two colors to create a more natural looking, smooth
//        // transition.
//        float3 e = normalize(eye_direction_cameraspace);
//        float3 r = -l + 2.0f * n_dot_l * n;
//        float e_dot_r =  saturate( dot(e, r) );
//
//        float specular_factor = pow(e_dot_r, materialShine);
//        epsilon = fwidth(specular_factor);
//
//        // If it is on the edge of the specular highlight
//        if ( (specular_factor > 0.5f - epsilon) && (specular_factor < 0.5f + epsilon) )
//        {
//            specular_factor = smoothstep(0.5f - epsilon, 0.5f + epsilon, specular_factor);
//        }
//        // It is either in or out of the highlight
//        else
//        {
//            specular_factor = step(0.5f, specular_factor);
//        }
//
//        float4 specular_color = materialSpecularColor * float4(light.color, 1.0) * specular_factor;
//
//        return float4(ambient_color + diffuse_color + specular_color);
//}
