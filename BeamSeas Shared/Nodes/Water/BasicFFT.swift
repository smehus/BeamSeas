//
//  BasicFFT.swift
//  BeamSeas
//
//  Created by Scott Mehus on 7/29/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

import Foundation
import Accelerate

class BasicFFT {

    private var signalCount: Int = 0

    private let pipelineState: MTLComputePipelineState
    static var drawTexture: MTLTexture!
    private let dataBuffer: MTLBuffer!

    init() {
        let n = vDSP_Length(2048)

        var frequencies: [Float] = [1, 2, 4, 8, 12, 33, 53, 55, 9, 5, 25, 30, 75, 100,
        300, 500, 512, 1023]


        let tau: Float = .pi * 2
        let signal: [Float] = (0 ... n).map { index in
            frequencies.reduce(0) { accumulator, frequency in
                let normalizedIndex = Float(index) / Float(n)
                return accumulator + sin(normalizedIndex * frequency * tau)
            }
        }
        signalCount = signal.count

        let log2n = vDSP_Length(log2(Float(n)))

        guard let fftSetUp = vDSP.FFT(log2n: log2n,
                                      radix: .radix2,
                                      ofType: DSPSplitComplex.self) else {
                                        fatalError("Can't create FFT Setup.")
        }


        let halfN = Int(n / 2)

        var forwardInputReal = [Float](repeating: 0,
                                       count: halfN)
        var forwardInputImag = [Float](repeating: 0,
                                       count: halfN)
        var forwardOutputReal = [Float](repeating: 0,
                                        count: halfN)
        var forwardOutputImag = [Float](repeating: 0,
                                        count: halfN)

        forwardInputReal.withUnsafeMutableBufferPointer { forwardInputRealPtr in
            forwardInputImag.withUnsafeMutableBufferPointer { forwardInputImagPtr in
                forwardOutputReal.withUnsafeMutableBufferPointer { forwardOutputRealPtr in
                    forwardOutputImag.withUnsafeMutableBufferPointer { forwardOutputImagPtr in

                        // 1: Create a `DSPSplitComplex` to contain the signal.
                        var forwardInput = DSPSplitComplex(realp: forwardInputRealPtr.baseAddress!,
                                                           imagp: forwardInputImagPtr.baseAddress!)

                        // 2: Convert the real values in `signal` to complex numbers.
                        signal.withUnsafeBytes {
                            vDSP.convert(interleavedComplexVector: [DSPComplex]($0.bindMemory(to: DSPComplex.self)),
                                         toSplitComplexVector: &forwardInput)
                        }

                        // 3: Create a `DSPSplitComplex` to receive the FFT result.
                        var forwardOutput = DSPSplitComplex(realp: forwardOutputRealPtr.baseAddress!,
                                                            imagp: forwardOutputImagPtr.baseAddress!)

                        // 4: Perform the forward FFT.
                        fftSetUp.forward(input: forwardInput,
                                         output: &forwardOutput)
                    }
                }
            }
        }


        let componentFrequencies = forwardOutputImag.enumerated().filter {
            $0.element < -1
        }.map {
            return $0.offset
        }

        // Prints "[1, 5, 25, 30, 75, 100, 300, 500, 512, 1023]"
        print(componentFrequencies)


        var inverseOutputReal = [Float](repeating: 0,
                                        count: halfN)
        var inverseOutputImag = [Float](repeating: 0,
                                        count: halfN)

        let recreatedSignal: [Float] =
            forwardOutputReal.withUnsafeMutableBufferPointer { forwardOutputRealPtr in
                forwardOutputImag.withUnsafeMutableBufferPointer { forwardOutputImagPtr in
                    inverseOutputReal.withUnsafeMutableBufferPointer { inverseOutputRealPtr in
                        inverseOutputImag.withUnsafeMutableBufferPointer { inverseOutputImagPtr in

                            // 1: Create a `DSPSplitComplex` that contains the frequency domain data.
                            let forwardOutput = DSPSplitComplex(realp: forwardOutputRealPtr.baseAddress!,
                                                                imagp: forwardOutputImagPtr.baseAddress!)

                            // 2: Create a `DSPSplitComplex` structure to receive the FFT result.
                            var inverseOutput = DSPSplitComplex(realp: inverseOutputRealPtr.baseAddress!,
                                                                imagp: inverseOutputImagPtr.baseAddress!)

                            // 3: Perform the inverse FFT.
                            fftSetUp.inverse(input: forwardOutput,
                                             output: &inverseOutput)

                            // 4: Return an array of real values from the FFT result.
                            let scale = 1 / Float(n * 2)
                            return [Float](fromSplitComplex: inverseOutput,
                                           scale: scale,
                                           count: Int(n))
                        }
                    }
                }
        }


//        print(signl)

        let texDesc = MTLTextureDescriptor()
        texDesc.width = Terrain.normalMapTexture.width
        texDesc.height = Terrain.normalMapTexture.height
        texDesc.pixelFormat = .rg11b10Float
        texDesc.usage = [.shaderRead, .shaderWrite]
        texDesc.mipmapLevelCount = Int(log2(Double(max(Terrain.normalMapTexture.width, Terrain.normalMapTexture.height))) + 1);
        texDesc.storageMode = .private
        Self.drawTexture = Renderer.device.makeTexture(descriptor: texDesc)!

        dataBuffer = Renderer.device.makeBuffer(bytes: signal, length: MemoryLayout<Float>.stride * signal.count, options: [])
        pipelineState = Self.buildPipelineState()

    } // init


    static func buildPipelineState() -> MTLComputePipelineState {
        guard let kernelFunction = Renderer.library?.makeFunction(name: "fft_kernel") else {
            fatalError("fft shader function not found")
        }

        return try! Renderer.device.makeComputePipelineState(function: kernelFunction)
    }
}

extension BasicFFT: Renderable {

//    let w = pipelineState.threadExecutionWidth
//    let h = pipelineState.maxTotalThreadsPerThreadgroup / w
//    let threadsPerGroup = MTLSizeMake(w, h, 1)
//    let threadsPerGrid = MTLSizeMake(Int(view.drawableSize.width),
//                                     Int(view.drawableSize.height), 1)
//    commandEncoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)

    // Not used for normals but i'm creating a texture so what the hell
    func generateTerrainNormals(computeEncoder: MTLComputeCommandEncoder, uniforms: inout Uniforms) {

        computeEncoder.pushDebugGroup("FFT")
        computeEncoder.setComputePipelineState(pipelineState)
        computeEncoder.setTexture(Self.drawTexture, index: 0)
        computeEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 3)
        computeEncoder.setBuffer(dataBuffer, offset: 0, index: 0)
        let w = pipelineState.threadExecutionWidth
        let h = pipelineState.maxTotalThreadsPerThreadgroup / w
        let threadsPerGroup = MTLSizeMake(w, h, 1)
        let threadsPerGrid = MTLSizeMake(Int(16),
                                         Int(16), 1)

        computeEncoder.dispatchThreadgroups(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        computeEncoder.popDebugGroup()
    }

    func draw(renderEncoder: MTLRenderCommandEncoder, uniforms: inout Uniforms, fragmentUniforms: inout FragmentUniforms) {

    }
}
