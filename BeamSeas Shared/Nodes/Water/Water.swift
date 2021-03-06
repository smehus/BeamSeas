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

    var distribution_displacement_real: [Float]
    var distribution_displacement_imag: [Float]
    var distribution_displacement_real_buffer: MTLBuffer!
    var distribution_displacement_imag_buffer: MTLBuffer!


//    var distribution_normal_real: [Float]
//    var distribution_normal_imag: [Float]
//    var distribution_normal_real_buffer: MTLBuffer!
//    var distribution_normal_imag_buffer: MTLBuffer!

    private let wind_velocity: SIMD2<Float>
    private let wind_dir: SIMD2<Float>
    private let Nx: Int
    private let Nz: Int
    private let size: SIMD2<Float>
    private let size_normal: SIMD2<Float>


    private let L: Float
    static var G: Float = 9.81

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

        let n = vDSP_Length(Nx * Nz)
        var newamplitude = amplitude
//        newamplitude *= 0.3 / sqrt(size.x * size.y)

        // Factor in phillips spectrum
        L = simd_dot(wind_velocity, wind_velocity) / Self.G;

        distribution_real = [Float](repeating: 0, count: Int(n))
        distribution_imag = [Float](repeating: 0, count: Int(n))

        // TODO: - Downsampling was breaking fft for some reason
        let displacementLength = (Nx * Nz) >> (displacement_downsample * 2)
        distribution_displacement_real = [Float](repeating: 0, count: Int(displacementLength))
        distribution_displacement_imag = [Float](repeating: 0, count: Int(displacementLength))


        // Distribution
        generate_distribution(
            distribution_real: &distribution_real,
            distribution_imag: &distribution_imag,
            size: size,
            amplitude: newamplitude
        )

        distribution_real_buffer = Renderer.device.makeBuffer(
            bytes: &distribution_real,
            length: MemoryLayout<Float>.stride * Int(n),
            options: .storageModeShared
        )!

        distribution_imag_buffer = Renderer.device.makeBuffer(
            bytes: &distribution_imag,
            length: MemoryLayout<Float>.stride * Int(n),
            options: .storageModeShared
        )!


        // Displacement
        downsample_distribution(
            displacement_real: &distribution_displacement_real,
            displacement_img: &distribution_displacement_imag,
            in_real: distribution_real,
            in_imag: distribution_imag,
            rate_log2: displacement_downsample
        )

        distribution_displacement_real_buffer = Renderer.device.makeBuffer(
            bytes: &distribution_displacement_real,
            length: MemoryLayout<Float>.stride * Int(displacementLength),
            options: .storageModeShared
        )!

        distribution_displacement_imag_buffer = Renderer.device.makeBuffer(
            bytes: &distribution_displacement_imag,
            length: MemoryLayout<Float>.stride * Int(displacementLength),
            options: .storageModeShared
        )!
    }


    private func downsample_distribution(displacement_real: inout [Float], displacement_img: inout [Float], in_real: [Float], in_imag: [Float], rate_log2: Int)
    {

        
        // Pick out the lower frequency samples only which is the same as downsampling "perfectly".
        let out_width: Int = Nx >> rate_log2;
        let out_height: Int = Nz >> rate_log2;

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

                displacement_real[z * out_width + x] = in_real[alias_z * Nx + alias_x];
                displacement_img[z * out_width + x] = in_imag[alias_z * Nx + alias_x];


//                let index = z * Nx + x
//                let kxx: Float = Float.pi * (2.0 * Float(x) - Float(Nx))
//                let kzz: Float = 2.0 * Float(z) - Float(Nz)
//
//                let kx: Float = kxx / Float(BasicFFT.distributionSize)
//                let kz: Float = kzz / Float(BasicFFT.distributionSize)
//                let len = sqrt(kx * kx + kz * kz)
//
//                displacement_real[z * out_width + x] = in_real[index] * -kx/len;
//                displacement_img[z * out_width + x] = in_imag[index] * -kz/len;
            }
        }
    }

    private func generate_distribution(distribution_real: inout [Float],
                                       distribution_imag: inout [Float],
                                       size: SIMD2<Float>,
                                       amplitude: Float,
                                       max_l: Float = 0.02) {

        // Modifier to find spatial frequency
        let mod = SIMD2<Float>(repeating: 2.0 * Float.pi) / size

        for z in 0..<Nz {
            for x in 0..<Nx {

                let k = mod * SIMD2<Float>(x: Float(alias(x, N: Nx)), y: Float(alias(z, N: Nz)))
                let gaus = normal_distribution.gausRandom()
                let realRand = Float(gaus.x)
                let imagRand = Float(gaus.y)

                let phillips = philliphs(k: k, max_l: max_l)
//                let phillips = normal_distribution.phillips(Float(k.x), y: Float(k.y))
                let newReal = realRand * amplitude * sqrt(0.5 * phillips)
                let newImag = imagRand * amplitude * sqrt(0.5 * phillips)


                let idx = z * Nx + x

                if distribution_real.indices.contains(idx), distribution_imag.indices.contains(idx) {
                    distribution_real[idx] = newReal
                    distribution_imag[idx] = newImag
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
