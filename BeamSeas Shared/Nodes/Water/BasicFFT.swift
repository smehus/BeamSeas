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
    static let distributionSize: Int = 128

    private var signalCount: Int = 0

    var distribution_real: MTLBuffer
    var distribution_imag: MTLBuffer

    var distribution_displacement_real: MTLBuffer
    var distribution_displacement_imag: MTLBuffer


    private let fftPipelineState: MTLComputePipelineState
    private let mainPipelineState: MTLRenderPipelineState

    static var heightDisplacementMap: MTLTexture!
    static var gradientMap: MTLTexture!

    private var dataBuffer: MTLBuffer!
    private var displacementBuffer: MTLBuffer!


    private let fft: vDSP.FFT<DSPSplitComplex>
    private let model: MTKMesh

    private let distributionPipelineState: MTLComputePipelineState
    private let displacementPipelineState: MTLComputePipelineState
    private let gradientPipelineState: MTLComputePipelineState

    private var source: Water!
    private var seed: Int32 = 0

    // Use these in the main fft_kernel draw method
    // Then in generate gradient create the heightDisplacementMap from sampling these two textures and mix.
    private var heightMap: MTLTexture!
    private var displacementMap: MTLTexture!

    override init() {

        let allocator = MTKMeshBufferAllocator(device: Renderer.device)
        let prim = MDLMesh(planeWithExtent: [0.5, 0.5, 0], segments: [4, 4], geometryType: .triangles, allocator: allocator)
        model = try! MTKMesh(mesh: prim, device: Renderer.device)

        let log2n = vDSP_Length(log2(Float((BasicFFT.distributionSize * BasicFFT.distributionSize))))
        fft = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self)!

        let texDesc = MTLTextureDescriptor()
        texDesc.width = BasicFFT.imgSize
        texDesc.height = BasicFFT.imgSize
        texDesc.pixelFormat = .rg11b10Float
        texDesc.usage = [.shaderRead, .shaderWrite]
        //        texDesc.mipmapLevelCount = Int(log2(Double(max(Terrain.normalMapTexture.width, Terrain.normalMapTexture.height))) + 1);
        texDesc.storageMode = .private

        Self.heightDisplacementMap = Renderer.device.makeTexture(descriptor: texDesc)!
        Self.gradientMap = Renderer.device.makeTexture(descriptor: texDesc)!
        heightMap = Renderer.device.makeTexture(descriptor: texDesc)!
        displacementMap = Renderer.device.makeTexture(descriptor: texDesc)!

        fftPipelineState = Self.buildComputePipelineState(shader: "fft_kernel")
        distributionPipelineState = Self.buildComputePipelineState(shader: "generate_distribution_map_values")
        displacementPipelineState = Self.buildComputePipelineState(shader: "generate_displacement_map_values")
        gradientPipelineState = Self.buildComputePipelineState(shader: "compute_height_graident")

        let mainPipeDescriptor = MTLRenderPipelineDescriptor()
        mainPipeDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        mainPipeDescriptor.depthAttachmentPixelFormat = .depth32Float
        mainPipeDescriptor.vertexFunction = Renderer.library.makeFunction(name: "fft_vertex")
        mainPipeDescriptor.fragmentFunction = Renderer.library.makeFunction(name: "fft_fragment")
        mainPipeDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(model.vertexDescriptor)

        mainPipelineState = try! Renderer.device.makeRenderPipelineState(descriptor: mainPipeDescriptor)

        source = Water(
                 amplitude: 5000,
                 wind_velocity: float2(x: 10, y: -10),
                 resolution: SIMD2<Int>(x: BasicFFT.distributionSize, y: BasicFFT.distributionSize),
                 size: float2(x: Float(BasicFFT.distributionSize), y: Float(BasicFFT.distributionSize)),
                 normalmap_freq_mod: float2(repeating: 1),
                 max_l: 2.0
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


    // This runs after 'generate_distributions' - so we get updated distribution_real / imag buffer values.
    // The source buffer values will all remain the same (Buffers in water.swift)
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
            dataLength: Int32(BasicFFT.distributionSize * BasicFFT.distributionSize),
            amplitude: 1,
            wind_velocity: vector_float2(x: 10, y: -10),
            resolution: vector_uint2(x: BasicFFT.distributionSize.unsigned, y: BasicFFT.distributionSize.unsigned),
            size: vector_float2(x: BasicFFT.distributionSize.float, y: BasicFFT.distributionSize.float),
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
        computeEncoder.setTexture(BasicFFT.heightDisplacementMap, index: 0)
        let w = distributionPipelineState.threadExecutionWidth
        let h = distributionPipelineState.maxTotalThreadsPerThreadgroup / w
        var threadGroupSize = MTLSizeMake(16, 16, 1)
        var threadgroupCount = MTLSizeMake(1, 1, 1)
        threadgroupCount.width = BasicFFT.imgSize//(BasicFFT.imgSize + threadGroupSize.width - 1) / threadGroupSize.width
        threadgroupCount.height = BasicFFT.imgSize//(BasicFFT.imgSize + threadGroupSize.height - 1) / threadGroupSize.height
        computeEncoder.dispatchThreads(threadgroupCount, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.popDebugGroup()


        computeEncoder.pushDebugGroup("FFT-Displacement")
        computeEncoder.setComputePipelineState(displacementPipelineState)
        computeEncoder.setBuffer(distribution_displacement_real, offset: 0, index: 12)
        computeEncoder.setBuffer(distribution_displacement_imag, offset: 0, index: 13)
        computeEncoder.setBuffer(source.distribution_displacement_real_buffer, offset: 0, index: 14)
        computeEncoder.setBuffer(source.distribution_displacement_imag_buffer, offset: 0, index: 15)
        computeEncoder.dispatchThreads(threadgroupCount, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.popDebugGroup()
    }



    func generateMaps(computeEncoder: MTLComputeCommandEncoder, uniforms: inout Uniforms) {
        // Create diplacement & height maps
        
        computeEncoder.pushDebugGroup("FFT-Drawing")
        // Apple example
        let w = fftPipelineState.threadExecutionWidth
        let h = fftPipelineState.maxTotalThreadsPerThreadgroup / w
        var threadGroupSize = MTLSizeMake(16, 16, 1)
        var threadgroupCount = MTLSizeMake(1, 1, 1)
        threadgroupCount.width = BasicFFT.imgSize//(BasicFFT.imgSize + threadGroupSize.width - 1) / threadGroupSize.width
        threadgroupCount.height = BasicFFT.imgSize//(BasicFFT.imgSize + threadGroupSize.height - 1) / threadGroupSize.height

        computeEncoder.setComputePipelineState(fftPipelineState)
        computeEncoder.setTexture(heightMap, index: 0)
        computeEncoder.setTexture(displacementMap, index: 1)
        computeEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 3)
        computeEncoder.setBuffer(dataBuffer, offset: 0, index: 0)
        computeEncoder.setBuffer(displacementBuffer, offset: 0, index: 1)
        
        // threadsPerGrid determines the thread_posistion dimensions
        computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.popDebugGroup()
    }

    func generateGradient(computeEncoder: MTLComputeCommandEncoder, uniforms: inout Uniforms) {
        // Bake height gradient - Combine displacement and height maps
        // Create final map to use for tessellation

        let w = gradientPipelineState.threadExecutionWidth
        let h = gradientPipelineState.maxTotalThreadsPerThreadgroup / w
        var threadGroupSize = MTLSizeMake(16, 16, 1)
        var threadgroupCount = MTLSizeMake(1, 1, 1)
        threadgroupCount.width = BasicFFT.imgSize//(BasicFFT.imgSize + threadGroupSize.width - 1) / threadGroupSize.width
        threadgroupCount.height = BasicFFT.imgSize//(BasicFFT.imgSize + threadGroupSize.height - 1) / threadGroupSize.height

        computeEncoder.pushDebugGroup("FFT-Gradient")
        computeEncoder.setComputePipelineState(gradientPipelineState)

        //        compute_height_graident will generate the draw texture used for terrain vertex
        computeEncoder.setTexture(heightMap, index: 0)
        computeEncoder.setTexture(displacementMap, index: 1)
        computeEncoder.setTexture(Self.heightDisplacementMap, index: 2)
        computeEncoder.setTexture(Self.gradientMap, index: 3)


        // InvSize parameter
        //        GL_CHECK(glUniform4f(0,
        //                1.0f / Nx, 1.0f / Nz,
        //                1.0f / (Nx >> displacement_downsample),
        //                1.0f / (Nz >> displacement_downsample)));

        // When i end up downsampling the displacement, I'll need to do the implemetnation above
        var invSize = float4(repeating: 1.0 / Float(BasicFFT.imgSize))
        computeEncoder.setBytes(&invSize, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)

        // uScale
        //        GL_CHECK(glUniform4f(1,
        //                Nx / size.x, Nz / size.y,
        //                (Nx >> displacement_downsample) / size.x,
        //                (Nz >> displacement_downsample) / size.y));
        // do the same as invsize
        var uScale = float4(repeating: Float(BasicFFT.imgSize) / Float(BasicFFT.imgSize))
        computeEncoder.setBytes(&uScale, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
        computeEncoder.dispatchThreads(threadgroupCount, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.popDebugGroup()
    }

    func generateTerrainNormals(computeEncoder: MTLComputeCommandEncoder, uniforms: inout Uniforms) {
        guard dataBuffer != nil else { return }

    }


    // This is used to draw the height map in the top left
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
        renderEncoder.setFragmentTexture(Self.heightDisplacementMap, index: 0)
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
