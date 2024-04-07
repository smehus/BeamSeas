//
//  Water.swift
//  BeamSeas
//
//  Created by Scott Mehus on 7/28/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

import MetalKit
import simd
import GameplayKit
import Numerics
import Accelerate

class Water {
    var distribution: [Complex<Float>]
    var distribution_buffer: MTLBuffer!

    var distribution_displacement: [Complex<Float>]
    var distribution_displacement_buffer: MTLBuffer!

    var distribution_normal: [Complex<Float>]
    var distribution_normal_buffer: MTLBuffer!

    private let wind_velocity: SIMD2<Float>
    private let wind_dir: SIMD2<Float>
    private let Nx: Int
    private let Nz: Int
    private let size: SIMD2<Float>
    // NEED THIS
    private let size_normal: SIMD2<Float>


    private let L: Float
    static var G: Float = 9.81
    private var A: Float

    private let displacement_downsample: Int = 1
    private let normal_distribution = NormalDistributionBridge()


    init(
        amplitude: Float,
        wind_velocity: SIMD2<Float>,
        resolution: SIMD2<Int>,
        size: SIMD2<Float>,
        normalmap_freq_mod: SIMD2<Float>
    ) {
        self.wind_velocity = wind_velocity
        self.wind_dir = normalize(wind_velocity)
        self.Nx = resolution.x
        self.Nz = resolution.y
        self.size = size
        self.size_normal = size / normalmap_freq_mod

        // Factor in phillips spectrum
        L = simd_dot(wind_velocity, wind_velocity) / Self.G;
        
        // Normalize amplitude a bit based on the heightmap size.
        A = amplitude * (0.3 / sqrt(size.x * size.y))
        
        // Array Init \\
         
        let n = vDSP_Length(Nx * Nz)
        distribution = Array(repeating: 0, count: Int(n))
        distribution_normal = Array(repeating: 0, count: Int(n))

        let displacementLength = n//(Nx * Nz) >> (displacement_downsample * 2)
        distribution_displacement = Array(repeating: 0, count: Int(displacementLength))

        
        // HEIGHT DISTRIBUTION \\
        
        // Create distribution Array
        generate_distribution(
            distribution: &distribution,
            size: size,
            amplitude: A,
            max_l: 0.2
        )

        // Put that array in to buffer so we can send off to gpu!
        distribution_buffer = Renderer.device.makeBuffer(
            bytes: &distribution,
            length: MemoryLayout<Float>.stride * Int(n),
            options: .storageModeShared
        )!
        
        
        // NORMAL DISTRIBUTION \\
        
        generate_distribution(
            distribution: &distribution_normal,
            size: size_normal,
            amplitude: A * sqrtf(normalmap_freq_mod.x * normalmap_freq_mod.y), // sqrtf ???? idk
            max_l: 0.2
        )

        distribution_normal_buffer = Renderer.device.makeBuffer(
            bytes: &distribution_normal,
            length: MemoryLayout<Float>.stride * Int(n)
        )
        
        
        // DISPLACEMENT DISTRIBUTIONS \\
        
        downsample_distribution(
            displacement: &distribution_displacement,
            in: distribution,
            rate_log2: displacement_downsample
        )

        distribution_displacement_buffer = Renderer.device.makeBuffer(
            bytes: &distribution_displacement,
            length: MemoryLayout<Float>.stride * Int(displacementLength),
            options: .storageModeShared
        )!
    }


    private func downsample_distribution(displacement: inout [Complex<Float>],
                                         in: [Complex<Float>],
                                         rate_log2: Int)
    {

        
        // Pick out the lower frequency samples only which is the same as downsampling "perfectly".
        let out_width: Int = Nx// >> rate_log2;
        let out_height: Int = Nz// >> rate_log2;

        for z in 0..<out_height {
            for x in 0..<out_width {
                var alias_x = alias(x, N: out_width);
                var alias_z = alias(z, N: out_height);

                if (alias_x < 0)
                {
                    alias_x += Nx;
                }

                if (alias_z < 0)
                {
                    alias_z += Nz;
                }

//                displacement_real[z * out_width + x] = in_real[alias_z * Nx + alias_x];
//                displacement_img[z * out_width + x] = in_imag[alias_z * Nx + alias_x];
            }
        }
    }

    private func generate_distribution(distribution: inout [Complex<Float>],
                                       size: SIMD2<Float>,
                                       amplitude: Float,
                                       max_l: Float) {

        // Modifier to find spatial frequency
        let mod = SIMD2<Float>(repeating: 2.0 * Float.pi) / size

        for z in 0..<Nz {
            for x in 0..<Nx {

                let k = mod * SIMD2<Float>(x: Float(alias(x, N: Nx)), y: Float(alias(z, N: Nz)))
                let dist: Complex<Float> = Complex(normal_distribution.gausRandom(), normal_distribution.gausRandom())
                
//                let phillips = philliphs(k: k, max_l: max_l)
                let phillips: Float = normal_distribution.phillips(
                    Float(k.x),
                    y: Float(k.y),
                    g: Water.G,
                    a: amplitude,
                    dir: wind_velocity
                )
                let idx = z * Nx + x

                if distribution.indices.contains(idx){
                    distribution[idx] = (dist |*| amplitude) |*| phillips
                }
            }
        }
    }

    private func philliphs(k: SIMD2<Float>, max_l: Float) -> Float {
        // might have to do this on gpu
        let k_len = simd_length(k)
        if k_len < 0.000001 {
            return 0
        }

        let kL = k_len * L
        let k_dir = simd_normalize(k)
        let kw = simd_dot(k_dir, wind_dir)

        return
            pow(kw * kw, 1.0) *
            exp(-1.0 * k_len * k_len * max_l * max_l) *
            exp(-1.0 / (kL * kL)) *
            pow(k_len, -4.0)
    }

    private func alias(_ x: Int, N: Int) -> Int {
        var value = x
        if x > (N / 2) {
            value -= N
        }

        return value
    }
}
