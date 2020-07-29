//
//  Water.swift
//  BeamSeas
//
//  Created by Scott Mehus on 7/28/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

import MetalKit
import simd
import Accelerate

class Water {

    private let wind_velocity: SIMD2<Float>
    private let wind_dir: SIMD2<Float>
    private let Nx: Int
    private let Nz: Int
    private let size: SIMD2<Float>
    private let size_normal: SIMD2<Float>


    private let L: Float
    static var G: Float = 9.81

    private let displacement_downsample: Int
    private var distribution: [Float]
    private var distribution_normal: [Float]

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

        // Factor in Phillips spectrum
        L = simd_dot(wind_velocity, wind_velocity) / Self.G

        // Use half-res for displacemnetmap since its so low resolution
        displacement_downsample = 1

        distribution = Array(repeating: 0, count: Nx * Nz)
        distribution_normal = Array(repeating: 0, count: Nx * Nz)

        // Normalize amplitude a bit based on the hightmap size
        let normalizedAmplitutde = amplitude * 0.3 / sqrt(size.x * size.y)

        generate_distribution(distribution: &distribution, size: size, amplitude: amplitude, max_l: 0.02)
        generate_distribution(distribution: &distribution_normal, size: size_normal, amplitude: amplitude * sqrt(normalmap_freq_mod.x * normalmap_freq_mod.y), max_l: 0.02)
    }


    func generate_distribution(
        distribution: inout [Float],
        size: SIMD2<Float>,
        amplitude: Float,
        max_l: Float
    ) {
        // Modifier to find spatial frequency
        let mod = SIMD2<Float>(repeating: 2.0 * Float.pi) / size

        for var z in 0..<Nz {
            for var x in 0..<Nx {
                let k: SIMD2<Float> = mod * SIMD2<Float>(Float(alias(x: &x, N: Nx)), Float(alias(x: &z, N: Nz)))
                // Needs to get ported over differently??
                let dist = DSPComplex(real: .random(in: 0...1), imag: .random(in: 0...1)).real
                distribution[z * Nx + x] = dist * amplitude * sqrt(0.5 * phillips(k: k, max_l: max_l))
            }
        }
    }

    // Phillips spectrum??
    func phillips(k: SIMD2<Float>, max_l: Float) -> Float {
        let k_len = simd_length(k)
        if k_len == 0 {
            return 0
        }

        let kL = k_len * L
        let k_dir = normalize(k)
        let kw = simd_dot(k_dir, wind_dir)

        return
                pow(kw * kw, 1.0) *                                 // Directional  
                exp(-1.0 * k_len * k_len * max_l * max_l) *         // Suppress small waves at ~max_l
                exp(-1.0 / (kL * kL)) *
                pow(k_len, -4.0)

    }

    func alias(x: inout Int, N: Int) -> Int {
        if x > N / 2 {
            x -= N
        }

        return x
    }
}
