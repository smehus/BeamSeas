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

extension Int {
    var float: Float {
        return Float(self)
    }

    var unsigned: uint {
        return uint(self)
    }
}

class BasicFFT: Node {


    static let imgSize: Int = 256

    private var signalCount: Int = 0

    var distribution_real: MTLBuffer
    var distribution_imag: MTLBuffer

    var distribution_displacement_real: MTLBuffer
    var distribution_displacement_imag: MTLBuffer


    private let pipelineState: MTLComputePipelineState
    private let mainPipelineState: MTLRenderPipelineState

    static var drawTexture: MTLTexture!

    private var dataBuffer: MTLBuffer!
    private var displacementBuffer: MTLBuffer!


    private let fft: vDSP.FFT<DSPSplitComplex>
    private let model: MTKMesh
    private let testTexture: MTLTexture

    private let distributionPipelineState: MTLComputePipelineState
    private let displacementPipelineState: MTLComputePipelineState
    private var source: Water!
    private var seed: Int32 = 0

    override init() {
        testTexture = Self.loadTexture(imageName: "gaussian_noise_5", path: "png")

        let allocator = MTKMeshBufferAllocator(device: Renderer.device)
        let prim = MDLMesh(planeWithExtent: [0.5, 0.5, 0], segments: [4, 4], geometryType: .triangles, allocator: allocator)
        model = try! MTKMesh(mesh: prim, device: Renderer.device)

        let log2n = vDSP_Length(log2(Float((BasicFFT.imgSize * BasicFFT.imgSize))))
        fft = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self)!

        let texDesc = MTLTextureDescriptor()
        texDesc.width = BasicFFT.imgSize
        texDesc.height = BasicFFT.imgSize
        texDesc.pixelFormat = .rg11b10Float
        texDesc.usage = [.shaderRead, .shaderWrite]
        //        texDesc.mipmapLevelCount = Int(log2(Double(max(Terrain.normalMapTexture.width, Terrain.normalMapTexture.height))) + 1);
        texDesc.storageMode = .private
        Self.drawTexture = Renderer.device.makeTexture(descriptor: texDesc)!

        pipelineState = Self.buildComputePipelineState(shader: "fft_kernel")
        distributionPipelineState = Self.buildComputePipelineState(shader: "generate_distribution")
        displacementPipelineState = Self.buildComputePipelineState(shader: "generate_displacement")

        let mainPipeDescriptor = MTLRenderPipelineDescriptor()
        mainPipeDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        mainPipeDescriptor.depthAttachmentPixelFormat = .depth32Float
        mainPipeDescriptor.vertexFunction = Renderer.library.makeFunction(name: "fft_vertex")
        mainPipeDescriptor.fragmentFunction = Renderer.library.makeFunction(name: "fft_fragment")
        mainPipeDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(model.vertexDescriptor)

        mainPipelineState = try! Renderer.device.makeRenderPipelineState(descriptor: mainPipeDescriptor)

        source = Water(
                 amplitude: 10000,
                 wind_velocity: float2(x: 0, y: -20),
                 resolution: SIMD2<Int>(x: BasicFFT.imgSize, y: BasicFFT.imgSize),
                 size: float2(x: BasicFFT.imgSize.float, y: BasicFFT.imgSize.float),
                 normalmap_freq_mod: float2(repeating: 7.3),
                 max_l: 4.0
        )

        guard
            let real = Renderer.device.makeBuffer(length: MemoryLayout<Float>.stride * source.distribution_real.count, options: .storageModeShared),
            let imag  = Renderer.device.makeBuffer(length: MemoryLayout<Float>.stride * source.distribution_imag.count, options: .storageModeShared),
            let displacement_real  = Renderer.device.makeBuffer(length: MemoryLayout<Float>.stride * source.distribution_displacement_real.count, options: .storageModeShared),
            let displacement_imag  = Renderer.device.makeBuffer(length: MemoryLayout<Float>.stride * source.distribution_displacement_imag.count, options: .storageModeShared)
        else {
            fatalError()
        }

        distribution_real = real
        distribution_imag = imag
        distribution_displacement_real = displacement_real
        distribution_displacement_imag = displacement_imag

//        let randomSource = Distributions.Normal(m: 0, v: 1)
//        var randos = (0..<n).map { _ in
//            float2(x: Float(randomSource.random()), y: Float(randomSource.random()))
//        }

//        randomBuffer = Renderer.device.makeBuffer(bytes: &randos, length: MemoryLayout<float2>.stride * Int(n), options: .storageModeShared)!

        super.init()

    } // init

    func runfft(phase: Float) {
        let recreatedSignal = runfft(real: distribution_real, imag: distribution_imag, count: source.distribution_real.count)
        dataBuffer = Renderer.device.makeBuffer(bytes: recreatedSignal, length: MemoryLayout<Float>.stride * recreatedSignal.count, options: [])

        // TODO: - Need to downsample this...
        // Taking toooo much gpu time
        let displacementSignal = runfft(real: distribution_displacement_real, imag: distribution_displacement_imag, count: source.distribution_displacement_real.count)
        displacementBuffer = Renderer.device.makeBuffer(bytes: displacementSignal, length: MemoryLayout<Float>.stride * displacementSignal.count, options: [])
    }

    private func runfft(real: MTLBuffer, imag: MTLBuffer, count: Int)  -> [Float] {

//        let halfN = Int((BasicFFT.imgSize * BasicFFT.imgSize) / 2)

        var inverseOutputReal = [Float](repeating: 0, count: count)
        var inverseOutputImag = [Float](repeating: 0, count: count)

        var inputReal = [Float](repeating: 0, count: count)
        var inputImag = [Float](repeating: 0, count: count)

        var realPointer = real.contents().bindMemory(to: Float.self, capacity: count)
        var imagPointer = imag.contents().bindMemory(to: Float.self, capacity: count)


        for index in 0..<(count) {

            inputReal[index] = realPointer.pointee
            inputImag[index] = imagPointer.pointee

            realPointer = realPointer.advanced(by: 1)
            imagPointer = imagPointer.advanced(by: 1)
        }

        let recreatedSignal: [Float] =
            inputReal.withUnsafeMutableBufferPointer { forwardOutputRealPtr in
                inputImag.withUnsafeMutableBufferPointer { forwardOutputImagPtr in
                    inverseOutputReal.withUnsafeMutableBufferPointer { inverseOutputRealPtr in
                        inverseOutputImag.withUnsafeMutableBufferPointer { inverseOutputImagPtr in

                            // 1: Create a `DSPSplitComplex` that contains the frequency domain data.
                            let forwardOutput = DSPSplitComplex(realp: forwardOutputRealPtr.baseAddress!,
                                                                imagp: forwardOutputImagPtr.baseAddress!)

                            // 2: Create a `DSPSplitComplex` structure to receive the FFT result.
                            var inverseOutput = DSPSplitComplex(realp: inverseOutputRealPtr.baseAddress!,
                                                                imagp: inverseOutputImagPtr.baseAddress!)

                            // 3: Perform the inverse FFT.
                            fft.inverse(input: forwardOutput, output: &inverseOutput)

                            // 4: Return an array of real values from the FFT result.
                            let scale = 1 / Float((count) * 2)
                            return [Float](fromSplitComplex: inverseOutput,
                                           scale: scale,
                                           count: Int(count))
                        }
                    }
                }
            }


        return recreatedSignal
    }


    static func buildComputePipelineState(shader: String) -> MTLComputePipelineState {
        guard let kernelFunction = Renderer.library?.makeFunction(name: shader) else {
            fatalError("fft shader function not found")
        }

        return try! Renderer.device.makeComputePipelineState(function: kernelFunction)
    }
}

extension BasicFFT: Renderable {

    // Modify the rando's created by 'water'
    func generateDistributions(computeEncoder: MTLComputeCommandEncoder, uniforms: Uniforms) {
        computeEncoder.pushDebugGroup("FFT-Distribution")
        var gausUniforms = GausUniforms(
            dataLength: Int32(BasicFFT.imgSize * BasicFFT.imgSize),
            amplitude: 1,
            wind_velocity: vector_float2(x: 10, y: -10),
            resolution: vector_uint2(x: BasicFFT.imgSize.unsigned, y: BasicFFT.imgSize.unsigned),
            size: vector_float2(x: BasicFFT.imgSize.float, y: BasicFFT.imgSize.float),
            normalmap_freq_mod: vector_float2(repeating: 7.3),
            seed: seed
        )

        var uniforms = uniforms
        computeEncoder.setComputePipelineState(distributionPipelineState)
        computeEncoder.setBytes(&gausUniforms, length: MemoryLayout<GausUniforms>.stride, index: BufferIndex.gausUniforms.rawValue)
        computeEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: BufferIndex.uniforms.rawValue)

        computeEncoder.setBuffer(distribution_real, offset: 0, index: 12)
        computeEncoder.setBuffer(distribution_imag, offset: 0, index: 13)
        
        computeEncoder.setBuffer(source.distribution_real_buffer, offset: 0, index: 14)
        computeEncoder.setBuffer(source.distribution_imag_buffer, offset: 0, index: 15)

        computeEncoder.setTexture(BasicFFT.drawTexture, index: 0)

        let w = pipelineState.threadExecutionWidth
        let h = pipelineState.maxTotalThreadsPerThreadgroup / w
        let threadGroupSize = MTLSizeMake(16, 16, 1)

        var threadgroupCount = MTLSizeMake(1, 1, 1)
        threadgroupCount.width = BasicFFT.imgSize//(BasicFFT.imgSize + threadGroupSize.width - 1) / threadGroupSize.width
        threadgroupCount.height = BasicFFT.imgSize//(BasicFFT.imgSize + threadGroupSize.height - 1) / threadGroupSize.height

        computeEncoder.dispatchThreads(threadgroupCount,
                                       threadsPerThreadgroup: threadGroupSize)
        computeEncoder.popDebugGroup()


        computeEncoder.pushDebugGroup("FFT-Displacement")

        computeEncoder.setComputePipelineState(displacementPipelineState)
        computeEncoder.setBuffer(distribution_displacement_real, offset: 0, index: 12)
        computeEncoder.setBuffer(distribution_displacement_imag, offset: 0, index: 13)

        computeEncoder.setBuffer(source.distribution_displacement_real_buffer, offset: 0, index: 14)
        computeEncoder.setBuffer(source.distribution_displacement_imag_buffer, offset: 0, index: 15)

//        threadgroupCount.width = 8
//        threadgroupCount.height = 8
        computeEncoder.dispatchThreads(threadgroupCount,
                                       threadsPerThreadgroup: threadGroupSize)

        computeEncoder.popDebugGroup()
    }

    // Not used for normals but i'm creating a texture so what the hell
    func generateTerrainNormals(computeEncoder: MTLComputeCommandEncoder, uniforms: inout Uniforms) {
        guard dataBuffer != nil else { return }
        computeEncoder.pushDebugGroup("FFT-Drawing")
        // Apple example
        let threadGroupSize = MTLSizeMake(16, 16, 1)
        var threadgroupCount = MTLSizeMake(16, 16, 1)
        threadgroupCount.width = (Self.drawTexture.width + threadGroupSize.width - 1) / threadGroupSize.width
        threadgroupCount.height = (Self.drawTexture.height + threadGroupSize.height - 1) / threadGroupSize.height



        computeEncoder.setComputePipelineState(pipelineState)
        computeEncoder.setTexture(Self.drawTexture, index: 0)
        computeEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 3)
        computeEncoder.setBuffer(dataBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(displacementBuffer, offset: 0, index: 1)

        // threadsPerGrid determines the thread_posistion dimensions
        computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.popDebugGroup()
    }

    func draw(renderEncoder: MTLRenderCommandEncoder, uniforms: inout Uniforms, fragmentUniforms: inout FragmentUniforms) {
        renderEncoder.pushDebugGroup("FFT")
        renderEncoder.setRenderPipelineState(mainPipelineState)

        position.x = -0.75
        position.y = 0.75
        //        rotation = [Float(90).degreesToRadians, 0, 0]

        uniforms.modelMatrix = modelMatrix
        renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: BufferIndex.uniforms.rawValue)
        //        renderEncoder.setVertexBytes(&viewPort, length: MemoryLayout<SIMD2<Float>>.stride, index: 22)

        var viewPort = SIMD2<Float>(x: Float(Renderer.metalView.drawableSize.width / 4), y: Float(Renderer.metalView.drawableSize.height / 4))
        renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: BufferIndex.uniforms.rawValue)
        renderEncoder.setFragmentTexture(Self.drawTexture, index: 0)
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
