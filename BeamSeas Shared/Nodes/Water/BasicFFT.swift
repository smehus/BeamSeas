//
//  BasicFFT.swift
//  BeamSeas
//
//  Created by Scott Mehus on 7/29/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

import Foundation
import Accelerate
import MetalKit

class BasicFFT: Node {

    private var signalCount: Int = 0

    private let pipelineState: MTLComputePipelineState
    private let mainPipelineState: MTLRenderPipelineState
    static var drawTexture: MTLTexture!
    private var dataBuffer: MTLBuffer!

    private let fft: vDSP.FFT<DSPSplitComplex>
    private let model: MTKMesh
    private let testTexture: MTLTexture
    private let n = vDSP_Length(262144)

    private var source: Water!
    override init() {
        testTexture = Self.loadTexture(imageName: "gaussian_noise_5", path: "png")

        let allocator = MTKMeshBufferAllocator(device: Renderer.device)
        let prim = MDLMesh(planeWithExtent: [0.5, 1, 0], segments: [4, 4], geometryType: .triangles, allocator: allocator)
        model = try! MTKMesh(mesh: prim, device: Renderer.device)

        let log2n = vDSP_Length(log2(Float(n)))
        fft = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self)!

        let texDesc = MTLTextureDescriptor()
        texDesc.width = 512
        texDesc.height = 512
        texDesc.pixelFormat = .rg11b10Float
        texDesc.usage = [.shaderRead, .shaderWrite]
        //        texDesc.mipmapLevelCount = Int(log2(Double(max(Terrain.normalMapTexture.width, Terrain.normalMapTexture.height))) + 1);
        texDesc.storageMode = .private
        Self.drawTexture = Renderer.device.makeTexture(descriptor: texDesc)!
        pipelineState = Self.buildComputePipelineState()

        let mainPipeDescriptor = MTLRenderPipelineDescriptor()
        mainPipeDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        mainPipeDescriptor.depthAttachmentPixelFormat = .depth32Float
        mainPipeDescriptor.vertexFunction = Renderer.library.makeFunction(name: "fft_vertex")
        mainPipeDescriptor.fragmentFunction = Renderer.library.makeFunction(name: "fft_fragment")
        mainPipeDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(model.vertexDescriptor)

        mainPipelineState = try! Renderer.device.makeRenderPipelineState(descriptor: mainPipeDescriptor)


        super.init()

    } // init

    func runfft(phase: Float) {

        source = Water(
            amplitude: 1,
            wind_velocity: float2(x: 10, y: -10),
            resolution: SIMD2<Int>(x: 512, y: 512),
            size: float2(x: 512, y: 512),
            normalmap_freq_mod: float2(repeating: 7.3)
        )

        let halfN = Int(n / 2)

        var inverseOutputReal = [Float](repeating: 0, count: halfN)
        var inverseOutputImag = [Float](repeating: 0, count: halfN)
        // no performance hit here - its in water..
        let recreatedSignal: [Float] =
            source.distribution_real.withUnsafeMutableBufferPointer { forwardOutputRealPtr in
                source.distribution_imag.withUnsafeMutableBufferPointer { forwardOutputImagPtr in
                    inverseOutputReal.withUnsafeMutableBufferPointer { inverseOutputRealPtr in
                        inverseOutputImag.withUnsafeMutableBufferPointer { inverseOutputImagPtr in

                            print("** ** alkjsdlfkj")
                            // 1: Create a `DSPSplitComplex` that contains the frequency domain data.
                            let forwardOutput = DSPSplitComplex(realp: forwardOutputRealPtr.baseAddress!,
                                                                imagp: forwardOutputImagPtr.baseAddress!)

                            // 2: Create a `DSPSplitComplex` structure to receive the FFT result.
                            var inverseOutput = DSPSplitComplex(realp: inverseOutputRealPtr.baseAddress!,
                                                                imagp: inverseOutputImagPtr.baseAddress!)

                            // 3: Perform the inverse FFT.
                            fft.inverse(input: forwardOutput,
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


        dataBuffer = Renderer.device.makeBuffer(bytes: recreatedSignal, length: MemoryLayout<Float>.stride * recreatedSignal.count, options: [])
    }


    static func buildComputePipelineState() -> MTLComputePipelineState {
        guard let kernelFunction = Renderer.library?.makeFunction(name: "fft_kernel") else {
            fatalError("fft shader function not found")
        }

        return try! Renderer.device.makeComputePipelineState(function: kernelFunction)
    }
}

extension BasicFFT: Renderable {

    // Not used for normals but i'm creating a texture so what the hell
    func generateTerrainNormals(computeEncoder: MTLComputeCommandEncoder, uniforms: inout Uniforms) {
        computeEncoder.pushDebugGroup("FFT")

        // Apple example
        let threadGroupSize = MTLSizeMake(16, 16, 1)
        var threadgroupCount = MTLSizeMake(16, 16, 1)
        threadgroupCount.width = (Self.drawTexture.width + threadGroupSize.width - 1) / threadGroupSize.width
        threadgroupCount.height = (Self.drawTexture.height + threadGroupSize.height - 1) / threadGroupSize.height


        computeEncoder.setComputePipelineState(pipelineState)
        computeEncoder.setTexture(Self.drawTexture, index: 0)
        computeEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 3)
        computeEncoder.setBuffer(dataBuffer, offset: 0, index: 0)

        // threadsPerGrid determines the thread_posistion dimensions
        computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.popDebugGroup()
    }

    func draw(renderEncoder: MTLRenderCommandEncoder, uniforms: inout Uniforms, fragmentUniforms: inout FragmentUniforms) {
        renderEncoder.pushDebugGroup("FFT")
        renderEncoder.setRenderPipelineState(mainPipelineState)

        //        position.y = 15
        //        rotation = [Float(90).degreesToRadians, 0, 0]

        uniforms.modelMatrix = modelMatrix
        renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: BufferIndex.uniforms.rawValue)
        renderEncoder.setFragmentTexture(Self.drawTexture, index: 8)
        //        renderEncoder.setVertexBytes(&viewPort, length: MemoryLayout<SIMD2<Float>>.stride, index: 22)

        var viewPort = SIMD2<Float>(x: Float(Renderer.metalView.drawableSize.width), y: Float(Renderer.metalView.drawableSize.height))
        renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: BufferIndex.uniforms.rawValue)
        renderEncoder.setFragmentTexture(Self.drawTexture, index: 8)
        renderEncoder.setFragmentTexture(testTexture, index: 1)
        renderEncoder.setFragmentBytes(&viewPort, length: MemoryLayout<SIMD2<Float>>.stride, index: 22)

        let mesh = model.submeshes.first!
        // forgot to add this
        renderEncoder.setVertexBuffer(model.vertexBuffers.first!.buffer, offset: 0, index: BufferIndex.vertexBuffer.rawValue)
        renderEncoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: mesh.indexCount,
            indexType: mesh.indexType,
            indexBuffer: mesh.indexBuffer.buffer,
            indexBufferOffset: mesh.indexBuffer.offset
        )

        renderEncoder.popDebugGroup()
    }

}

extension BasicFFT: Texturable { }
