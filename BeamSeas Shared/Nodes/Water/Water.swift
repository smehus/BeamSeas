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
import Accelerate

struct Complex<T: FloatingPoint> {
    let real: T
    let imaginary: T

    static func +(lhs: Complex<T>, rhs: Complex<T>) -> Complex<T> {
        return Complex(real: lhs.real + rhs.real, imaginary: lhs.imaginary + rhs.imaginary)
    }

    static func -(lhs: Complex<T>, rhs: Complex<T>) -> Complex<T> {
        return Complex(real: lhs.real - rhs.real, imaginary: lhs.imaginary - rhs.imaginary)
    }

    static func *(lhs: Complex<T>, rhs: Complex<T>) -> Complex<T> {
        return Complex(real: lhs.real * rhs.real - lhs.imaginary * rhs.imaginary,
                       imaginary: lhs.imaginary * rhs.real + lhs.real * rhs.imaginary)
    }
}

// you can print it any way you want, but I'd probably do:

extension Complex: CustomStringConvertible {
    var description: String {
        switch (real, imaginary) {
        case (_, 0):
            return "\(real)"
        case (0, _):
            return "\(imaginary)i"
        case (_, let b) where b < 0:
            return "\(real) - \(abs(imaginary))i"
        default:
            return "\(real) + \(imaginary)i"
        }
    }
}

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
    private var distribution: [Complex<Float>]

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

        // Normalize amplitude a bit based on the hightmap size
        var amplitude = amplitude
        amplitude *=  0.3 / sqrt(size.x * size.y)

        generate_distribution(distribution: &distribution, size: size, amplitude: amplitude, max_l: 0.02)


    }



    func generate_distribution(
        distribution: inout [Float],
        size: SIMD2<Float>,
        amplitude: Float,
        max_l: Float
    ) {
        // Modifier to find spatial frequency
        let mod = SIMD2<Float>(repeating: 2.0 * Float.pi) / size


        let engine = MyGaussianDistribution(randomSource: GKRandomSource(), mean: 0, deviation: 1)
        for z in 0..<Nz {
            var inoutZ = z
            for x in 0..<Nx {
                var inoutX = x
                let k: SIMD2<Float> = mod * SIMD2<Float>(Float(alias(x: &inoutX, N: Nx)), Float(alias(x: &inoutZ, N: Nz)))

                // Needs to get ported over differently??
                // Gaussian distributed noise with unit variance
                // Theres posts indicting gameplay kit is not right to use here. Lets try it though.
                let nextDist = engine.nextFloat()
                print("*** \(nextDist)")
                distribution[z * Nx + x] = nextDist * amplitude * sqrt(0.5 * phillips(k: k, max_l: max_l))
            }
        }
    }

    func phillips(k: SIMD2<Float>, max_l: Float) -> Float {

        // See Tessendorf paper for details
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
        if x > (N / 2) {
            x -= N
        }

        return x
    }
}

class MyGaussianDistribution {
    private let randomSource: GKRandomSource
    let mean: Float
    let deviation: Float

    init(randomSource: GKRandomSource, mean: Float, deviation: Float) {
        precondition(deviation >= 0)
        self.randomSource = randomSource
        self.mean = mean
        self.deviation = deviation
    }

    func nextFloat() -> Float {
        guard deviation > 0 else { return mean }

        let x1 = randomSource.nextUniform() // a random number between 0 and 1
        let x2 = randomSource.nextUniform() // a random number between 0 and 1
        let z1 = sqrt(-2 * log(x1)) * cos(2 * Float.pi * x2) // z1 is normally distributed

        // Convert z1 from the Standard Normal Distribution to our Normal Distribution
        return z1 * deviation + mean
    }
}
