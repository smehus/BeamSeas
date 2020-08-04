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
    var distribution_real: [Float]
    var distribution_imag: [Float]
    var distribution_real_buffer: MTLBuffer!
    var distribution_imag_buffer: MTLBuffer!

    private let wind_velocity: SIMD2<Float>
    private let wind_dir: SIMD2<Float>
    private let Nx: Int
    private let Nz: Int
    private let size: SIMD2<Float>
    private let size_normal: SIMD2<Float>


    private let L: Float
    static var G: Float = 9.81

    private let displacement_downsample: Int = 1


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

        let n = vDSP_Length(Nx * Nz)
        let halfN = Int(n / 2)

        // Factor in phillips spectrum
        L = simd_dot(wind_velocity, wind_velocity) / Self.G;

        distribution_real = [Float](repeating: 0, count: halfN)
        distribution_imag = [Float](repeating: 0, count: halfN)

        var newamplitude = amplitude
        newamplitude *= 0.3 / sqrt(size.x * size.y)

//        let source = Distributions.Normal(m: 0, v: 1)


//        distribution_real = distribution_real.map { _ in return Float(source.random()) }
//        distribution_imag = distribution_imag.map { _ in return Float(source.random()) }

        generate_distribution(distribution_real: &distribution_real, distribution_imag: &distribution_imag, size: size, amplitude: newamplitude, max_l: 0.1)
//        print(distribution_real)

        distribution_real_buffer = Renderer.device.makeBuffer(
            bytes: &distribution_real,
            length: MemoryLayout<Float>.stride * halfN,
            options: .storageModeShared
        )!

        distribution_imag_buffer = Renderer.device.makeBuffer(
            bytes: &distribution_imag,
            length: MemoryLayout<Float>.stride * halfN,
            options: .storageModeShared
        )!
    }


    private func generate_distribution(distribution_real: inout [Float],
                                       distribution_imag: inout [Float],
                                       size: SIMD2<Float>,
                                       amplitude: Float,
                                       max_l: Float) {

        // Modifier to find spatial frequency
        let mod = SIMD2<Float>(repeating: 2.0 * Float.pi) / size

        let normal_distribution = Distributions.Normal(m: 0, v: 1)
        for z in 0..<Nz {
            var ioZ = z
            for x in 0..<Nx {
                var ioX = x

                let k = mod * SIMD2<Float>(x: Float(alias(x: &ioX, N: Nx)), y: Float(alias(x: &ioZ, N: Nz)))
                let realRand = Float(normal_distribution.random())
                let imagRand = Float(normal_distribution.random())

                let phillips = philliphs(k: k, max_l: max_l)
                let newReal = realRand * amplitude * sqrt(0.5 * phillips)
                let newImag = imagRand * amplitude * sqrt(0.5 * phillips)


                let idx = z * Nx + x

                if distribution_real.indices.contains(idx), distribution_imag.indices.contains(idx) {

//                    newReal = (newReal - -1) / (1 - -1) * (1 - 0) + 0
//                    newImag = (newImag - -1) / (1 - -1) * (1 - 0) + 0
//                    print("*** new real \(newReal)")
                    distribution_real[idx] = newReal
                    distribution_imag[idx] = newImag
                }
            }
        }
    }

    private func philliphs(k: SIMD2<Float>, max_l: Float) -> Float {
        // might have to do this on gpu
        let k_len = simd_length(k)
        if k_len == 0 {
            return 0
        }

        let kL = k_len * L
        let k_dir = simd_normalize(k)
        let kw = simd_dot(k_dir, wind_dir)

        return
            pow(kw * kw, 1.0) *
            exp(-1 * k_len * k_len * max_l * max_l) *
            exp(-1 / (kL * kL)) *
            pow(k_len, -4.0)
    }

    private func alias(x: inout Int, N: Int) -> Int {
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
