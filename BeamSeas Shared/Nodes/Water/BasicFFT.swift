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

    private var signalCount: Int = 0

    // Used to run ifft
    var distribution_real: MTLBuffer
    var distribution_imag: MTLBuffer
    var distribution_displacement_real: MTLBuffer
    var distribution_displacement_imag: MTLBuffer
    var distribution_normal_real: MTLBuffer
    var distribution_normal_imag: MTLBuffer

    private let fftPipelineState: MTLComputePipelineState
    private let mainPipelineState: MTLRenderPipelineState

    static var heightDisplacementMap: MTLTexture!
    static var gradientMap: MTLTexture!
    static var normalMapTexture: MTLTexture!

    // Output of FFT
    private var dataBuffer: MTLBuffer!
    private var normalBuffer: MTLBuffer!
    private var displacementBuffer: MTLBuffer!


    private let distributionFFT: vDSP.FFT<DSPSplitComplex>
    private let downsampledFFT: vDSP.FFT<DSPSplitComplex>
    private let model: MTKMesh

    private let distributionPipelineState: MTLComputePipelineState
    private let displacementPipelineState: MTLComputePipelineState
    private let heightDisplacementGradientPipelineState: MTLComputePipelineState
    private let normalPipelineState: MTLComputePipelineState

    private var source: Water!
    private var seed: Int32 = 0

    // Use these in the main fft_kernel draw method
    // Then in generate gradient create the heightDisplacementMap from sampling these two textures and mix.
    private var heightMap: MTLTexture!
    private var displacementMap: MTLTexture!


    static let distributionSize: Int = 128
    static let textureSize: Int = 256
    static var wind_velocity = float2(x: -23, y: 30)
    static var amplitude = 1000
    static let NORMALMAP_FREQ_MOD: Float = 7.3

    override init() {

        let allocator = MTKMeshBufferAllocator(device: Renderer.device)
        let prim = MDLMesh(planeWithExtent: [0.5, 0.5, 0], segments: [4, 4], geometryType: .triangles, allocator: allocator)
        model = try! MTKMesh(mesh: prim, device: Renderer.device)

        let log2n = vDSP_Length(log2(Float((BasicFFT.distributionSize * BasicFFT.distributionSize))))
        distributionFFT = vDSP.FFT(log2n: log2n, radix: .radix5, ofType: DSPSplitComplex.self)!

        let s = (BasicFFT.distributionSize * BasicFFT.distributionSize) >> (1 * 2)
        let downdSampledLog2n = vDSP_Length(log2(Float(s)))
        downsampledFFT = vDSP.FFT(log2n: downdSampledLog2n, radix: .radix5, ofType: DSPSplitComplex.self)!

        let texDesc = MTLTextureDescriptor()
        texDesc.width = BasicFFT.textureSize
        texDesc.height = BasicFFT.textureSize
        // ooohhhh my god - it was the fucking pixel format
        // Second time! Changing from 32 bit to 16 bit fixed phone choppiness when moving texture coordinates.
        texDesc.pixelFormat = .rgba16Float
        texDesc.usage = [.shaderRead, .shaderWrite]
        
        texDesc.storageMode = .private

        // Final textures for main pass
        Self.heightDisplacementMap = Renderer.device.makeTexture(descriptor: texDesc)!
        Self.gradientMap = Renderer.device.makeTexture(descriptor: texDesc)!
        heightMap = Renderer.device.makeTexture(descriptor: texDesc)!
        displacementMap = Renderer.device.makeTexture(descriptor: texDesc)!

//
//        MTLTextureDescriptor* texDesc = [[MTLTextureDescriptor alloc] init];
//        texDesc.width = heightMapWidth;
//        texDesc.height = heightMapHeight;
//        texDesc.pixelFormat = MTLPixelFormatRG11B10Float;
//        texDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
//        texDesc.mipmapLevelCount = std::log2(MAX(heightMapWidth, heightMapHeight)) + 1;
//        texDesc.storageMode = MTLStorageModePrivate;
//        _terrainNormalMap = [device newTextureWithDescriptor:texDesc];
        
        texDesc.mipmapLevelCount = Int(log2(Double(max(BasicFFT.textureSize, BasicFFT.textureSize))) + 1);
        texDesc.pixelFormat = .rg11b10Float
        texDesc.storageMode = .private
        Self.normalMapTexture = Renderer.device.makeTexture(descriptor: texDesc)!

        // Drawing distribution & displacement values onto textures
        fftPipelineState = Self.buildComputePipelineState(shader: "fft_kernel")
        
        // Generate distribution values
        distributionPipelineState = Self.buildComputePipelineState(shader: "generate_distribution_map_values")
        
        // Generate displacement values
        displacementPipelineState = Self.buildComputePipelineState(shader: "generate_displacement_map_values")
        
        // Combining displacement teuxture & height texture onto one combined texture
        heightDisplacementGradientPipelineState = Self.buildComputePipelineState(shader: "compute_height_displacement_graident")
        
        // Generate normal values from height texture & draw onto normal texture
        normalPipelineState = Self.buildComputePipelineState(shader: "TerrainKnl_ComputeNormalsFromHeightmap")

        let mainPipeDescriptor = MTLRenderPipelineDescriptor()
        mainPipeDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        mainPipeDescriptor.depthAttachmentPixelFormat = .depth32Float
        mainPipeDescriptor.vertexFunction = Renderer.library.makeFunction(name: "fft_vertex")
        mainPipeDescriptor.fragmentFunction = Renderer.library.makeFunction(name: "fft_fragment")
        mainPipeDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(model.vertexDescriptor)

        mainPipelineState = try! Renderer.device.makeRenderPipelineState(descriptor: mainPipeDescriptor)

        source = Water(
            amplitude: Float(BasicFFT.amplitude),
            wind_velocity: BasicFFT.wind_velocity,
            resolution: SIMD2<Int>(x: BasicFFT.distributionSize, y: BasicFFT.distributionSize), // Determines the amount of random numbers
            size: float2(x: Terrain.terrainSize, y: Terrain.terrainSize), // Size is used for amplitude modifiers
            normalmap_freq_mod: float2(repeating: Self.NORMALMAP_FREQ_MOD) // @TODO: -- FUCK I NEED THIS!!!!!
        )

        // Creating buffers to fill up with distribution_real(etc) -> FFT -> Our buffer here
        guard
            let real = Renderer.device.makeBuffer(length: MemoryLayout<Float>.stride * source.distribution_real.count, options: .storageModeShared),
            let imag  = Renderer.device.makeBuffer(length: MemoryLayout<Float>.stride * source.distribution_imag.count, options: .storageModeShared),
            let normal_real = Renderer.device.makeBuffer(length: MemoryLayout<Float>.stride * source.distribution_normal_real.count, options: .storageModeShared),
            let normal_imag = Renderer.device.makeBuffer(length: MemoryLayout<Float>.stride * source.distribution_normal_imag.count, options: .storageModeShared),
            let displacement_real  = Renderer.device.makeBuffer(length: MemoryLayout<Float>.size * source.distribution_displacement_real.count, options: .storageModeShared),
            let displacement_imag  = Renderer.device.makeBuffer(length: MemoryLayout<Float>.size * source.distribution_displacement_imag.count, options: .storageModeShared)
        else {
            fatalError()
        }

        distribution_real = real
        distribution_imag = imag
        distribution_displacement_real = displacement_real
        distribution_displacement_imag = displacement_imag
        distribution_normal_real = normal_real
        distribution_normal_imag = normal_imag

        super.init()

    } // init

    
    // This runs after 'generate_distributions' - so we get updated distribution_real / imag buffer values.
    // The source buffer values will all remain the same (Buffers in water.swift)
    func runfft(phase: Float) {
        let recreatedSignal = runfft(
            real: distribution_real,
            imag: distribution_imag,
            count: source.distribution_real.count + source.distribution_imag.count,
            fft: distributionFFT
        )
        
        // I think this count is wrong yo. Should be 16k instead of 32.
        // Do i need to get rid of the imageinary numbers? Cause thats whats happening
        dataBuffer = Renderer.device.makeBuffer(
            bytes: recreatedSignal,
            length: MemoryLayout<Float>.stride * recreatedSignal.count,
            options: []
        )
        
        let normalSignal = runfft(
            real: distribution_normal_real,
            imag: distribution_normal_imag,
            count: source.distribution_normal_real.count + source.distribution_normal_imag.count,
            fft: distributionFFT
        )

        normalBuffer = Renderer.device.makeBuffer(
            bytes: normalSignal,
            length: MemoryLayout<Float>.stride * normalSignal.count
        )

        let displacementSignal = runfft(
            real: distribution_displacement_real,
            imag: distribution_displacement_imag,
            count: source.distribution_displacement_real.count + source.distribution_displacement_imag.count,
            fft: distributionFFT// use this for downsampling - downsampledFFT
        )
        
        displacementBuffer = Renderer.device.makeBuffer(
            bytes: displacementSignal,
            length: MemoryLayout<Float>.stride * displacementSignal.count,
            options: []
        )
    }

    private func runfft(real: MTLBuffer, imag: MTLBuffer, count: Int, fft transformer: vDSP.FFT<DSPSplitComplex>)  -> [Float] {

//        let halfN = Int((BasicFFT.imgSize * BasicFFT.imgSize) / 2)

        var inverseOutputReal = [Float](repeating: 0, count: count / 2)
        var inverseOutputImag = [Float](repeating: 0, count: count / 2)

        var inputReal = [Float](repeating: 0, count: count / 2)
        var inputImag = [Float](repeating: 0, count: count / 2)

        var realPointer = real.contents().bindMemory(to: Float.self, capacity: count / 2)
        var imagPointer = imag.contents().bindMemory(to: Float.self, capacity: count / 2)


        for index in 0..<(count / 2) {

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
                            transformer.inverse(input: forwardOutput, output: &inverseOutput)


                            // 4: Return an array of real values from the FFT result.
                            let scale = 1 / Float((count * 2))
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

    func update(deltaTime: Float,
                uniforms: inout Uniforms,
                fragmentUniforms: inout FragmentUniforms,
                camera: Camera,
                scaffolding: WorldMapScaffolding,
                player: Model) {
        
    }

    // Modify the rando's created by 'water'
    func generateDistributions(computeEncoder: MTLComputeCommandEncoder, uniforms: Uniforms) {
        computeEncoder.pushDebugGroup("FFT-Distribution")
        var gausUniforms = GausUniforms(
            dataLength: Int32(BasicFFT.distributionSize * BasicFFT.distributionSize),
            amplitude: Float(BasicFFT.amplitude),
//            wind_velocity: vector_float2(x: BasicFFT.wind_velocity.x, y: BasicFFT.wind_velocity.y),
            resolution: vector_uint2(x: BasicFFT.distributionSize.unsigned, y: BasicFFT.distributionSize.unsigned),
            size: vector_float2(x: Terrain.terrainSize, y: Terrain.terrainSize),
            normalmap_freq_mod: vector_float2(repeating: Self.NORMALMAP_FREQ_MOD),
            seed: seed
        )

        var uniforms = uniforms
        computeEncoder.setComputePipelineState(distributionPipelineState)
        computeEncoder.setBytes(&gausUniforms, length: MemoryLayout<GausUniforms>.stride, index: BufferIndex.gausUniforms.rawValue)
        computeEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: BufferIndex.uniforms.rawValue)
        // Output
        // TODO: -- arrrgggghh do I need to do all this for the normal distributions?? yeahhhhhhh
        // Orrrrr how do I calculate these normals....
        computeEncoder.setBuffer(distribution_real, offset: 0, index: 12)
        computeEncoder.setBuffer(distribution_imag, offset: 0, index: 13)

        // Input
        computeEncoder.setBuffer(source.distribution_real_buffer, offset: 0, index: 14)
        computeEncoder.setBuffer(source.distribution_imag_buffer, offset: 0, index: 15)
        computeEncoder.setTexture(BasicFFT.heightDisplacementMap, index: 0)

        let w = distributionPipelineState.threadExecutionWidth
        let h = distributionPipelineState.maxTotalThreadsPerThreadgroup / w
        var threadGroupSize = MTLSizeMake(w, h, 1)
        var threadgroupCount = MTLSizeMake(BasicFFT.distributionSize, BasicFFT.distributionSize, 1)

        computeEncoder.dispatchThreads(threadgroupCount, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.popDebugGroup()


        
        // TODO: -- NORMAL DISTRIBUTIONS
        
        
        
        // :(
        
        
        
        
        

//        threadGroupSize.width = 64
//        threadGroupSize.height = 1
//        threadgroupCount.width = (BasicFFT.distributionSize >> 1)// / 64
//        threadgroupCount.height = BasicFFT.distributionSize >> 1

        computeEncoder.pushDebugGroup("FFT-Displacement")
        computeEncoder.setComputePipelineState(displacementPipelineState)
        // output
        computeEncoder.setBuffer(distribution_displacement_real, offset: 0, index: 12)
        computeEncoder.setBuffer(distribution_displacement_imag, offset: 0, index: 13)

        // Input
        computeEncoder.setBuffer(source.distribution_displacement_real_buffer, offset: 0, index: 14)
        computeEncoder.setBuffer(source.distribution_displacement_imag_buffer, offset: 0, index: 15)

        computeEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: BufferIndex.uniforms.rawValue)
        computeEncoder.dispatchThreads(threadgroupCount, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.popDebugGroup()
    }



    func generateMaps(computeEncoder: MTLComputeCommandEncoder, uniforms: inout Uniforms) {
        // Create diplacement & height maps

        computeEncoder.pushDebugGroup("FFT-Drawing-Height")
//        let w = fftPipelineState.threadExecutionWidth
//        let h = fftPipelineState.maxTotalThreadsPerThreadgroup / w

        computeEncoder.setComputePipelineState(fftPipelineState)
        computeEncoder.setTexture(heightMap, index: 0)
        computeEncoder.setBuffer(dataBuffer, offset: 0, index: 0)
        uniforms.distrubtionSize = UInt32(Self.distributionSize)
        computeEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: BufferIndex.uniforms.rawValue)
        computeEncoder.dispatchThreadgroups(
            MTLSizeMake(1, BasicFFT.textureSize, 1), // Adds up to the amount of values in ROWS (512)
            threadsPerThreadgroup: MTLSizeMake(BasicFFT.textureSize, 1, 1) // Add up to amount of values in COLUMNS (512)
        )
        computeEncoder.popDebugGroup()

        computeEncoder.pushDebugGroup("FFT-Drawing-Displacement")
        computeEncoder.setComputePipelineState(fftPipelineState)
        computeEncoder.setTexture(displacementMap, index: 0)
        computeEncoder.setBuffer(displacementBuffer, offset: 0, index: 0)

        computeEncoder.dispatchThreadgroups(
            MTLSizeMake(1, BasicFFT.textureSize, 1), // Adds up to the amount of values in ROWS (512)
            threadsPerThreadgroup: MTLSizeMake(BasicFFT.textureSize, 1, 1) // Add up to amount of values in COLUMNS (512)
        )
        
        computeEncoder.popDebugGroup()
    }
    
    // Bake height gradient - Combine displacement and height maps
    // Create final map to use for tessellation
    func generateGradient(computeEncoder: MTLComputeCommandEncoder, uniforms: inout Uniforms) {
        let threadsPerGroup = MTLSizeMake(BasicFFT.textureSize, 1, 1)
        let threadgroupCount = MTLSizeMake(1, BasicFFT.textureSize, 1)

        computeEncoder.pushDebugGroup("FFT-Gradient")
        computeEncoder.setComputePipelineState(heightDisplacementGradientPipelineState)

        //        compute_height_graident will generate the draw texture used for terrain vertex
        computeEncoder.setTexture(heightMap, index: 0)
        computeEncoder.setTexture(displacementMap, index: 1)
        computeEncoder.setTexture(Self.heightDisplacementMap, index: 2)
        computeEncoder.setTexture(Self.gradientMap, index: 3)

        var invSize = float4(
            x: 1.0 / Float(BasicFFT.textureSize),
            y: 1.0 / Float(BasicFFT.textureSize),
            z: 1.0 / Float(BasicFFT.textureSize >> 1),
            w: 1.0 / Float(BasicFFT.textureSize >> 1)
        )

        computeEncoder.setBytes(&invSize, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)

        var uScale = float4(
            x: Float(BasicFFT.distributionSize) / Terrain.terrainSize,
            y: Float(BasicFFT.distributionSize) / Terrain.terrainSize,
            z: (Float(BasicFFT.distributionSize >> 1)) / Terrain.terrainSize,
            w: (Float(BasicFFT.distributionSize >> 1)) / Terrain.terrainSize
        )

        computeEncoder.setBytes(&uScale, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)


        computeEncoder.dispatchThreadgroups(
            MTLSizeMake(1, BasicFFT.textureSize, 1), // Adds up to the amount of values in ROWS (512)
            threadsPerThreadgroup: MTLSizeMake(BasicFFT.textureSize, 1, 1) // Add up to amount of values in COLUMNS (512)
        )
        computeEncoder.popDebugGroup()
    }

    func generateTerrainNormals(computeEncoder: MTLComputeCommandEncoder, uniforms: inout Uniforms) {

        var xz_scale: Float = 0.09
        var y_scale: Float = 10.0
        
        computeEncoder.pushDebugGroup("Generate Terrain Normals")
        computeEncoder.setComputePipelineState(normalPipelineState)
        computeEncoder.setTexture(heightMap, index: 0)
        computeEncoder.setTexture(Self.normalMapTexture, index: 2)
        computeEncoder.setBytes(&Terrain.terrainParams, length: MemoryLayout<TerrainParams>.size, index: 3)
        computeEncoder.setBytes(&xz_scale, length: MemoryLayout<Float>.stride, index: 4)
        computeEncoder.setBytes(&y_scale, length: MemoryLayout<Float>.stride, index: 5)
        computeEncoder.setBytes(
            &uniforms,
            length: MemoryLayout<Uniforms>.stride,
            index: BufferIndex.uniforms.rawValue
        )
        
        computeEncoder.dispatchThreadgroups(
            MTLSizeMake(1, BasicFFT.textureSize, 1),
            threadsPerThreadgroup: MTLSizeMake(BasicFFT.textureSize, 1, 1)
        )
        computeEncoder.popDebugGroup()
    }


    // This is used to draw the height map in the top left
    func draw(renderEncoder: MTLRenderCommandEncoder, uniforms: inout Uniforms, fragmentUniforms: inout FragmentUniforms) {
        renderEncoder.setRenderPipelineState(mainPipelineState)

        renderEncoder.pushDebugGroup("Tiny Map - Height")
        position.x = -0.75
        position.y = 0.75
        //        rotation = [Float(90).degreesToRadians, 0, 0]

        uniforms.modelMatrix = modelMatrix
        renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: BufferIndex.uniforms.rawValue)
        //        renderEncoder.setVertexBytes(&viewPort, length: MemoryLayout<SIMD2<Float>>.stride, index: 22)

        var viewPort = SIMD2<Float>(x: Float(Renderer.metalView.drawableSize.width), y: Float(Renderer.metalView.drawableSize.height))
        renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: BufferIndex.uniforms.rawValue)
        renderEncoder.setFragmentTexture(heightMap, index: 0)
        renderEncoder.setFragmentBytes(&viewPort, length: MemoryLayout<SIMD2<Float>>.stride, index: BufferIndex.viewport.rawValue)

        let mesh = model.submeshes.first!
        // forgot to add this
        renderEncoder.setVertexBuffer(model.vertexBuffers.first!.buffer, offset: 0, index: BufferIndex.vertexBuffer.rawValue)
        renderEncoder.setTriangleFillMode(.fill)
        renderEncoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: mesh.indexCount,
            indexType: mesh.indexType,
            indexBuffer: mesh.indexBuffer.buffer,
            indexBufferOffset: mesh.indexBuffer.offset
        )

        renderEncoder.popDebugGroup()




//        renderEncoder.pushDebugGroup("Tiny Map - Displacement")
//        position.x = -0.75
//        position.y = 0.25
//
//        uniforms.modelMatrix = modelMatrix
//        renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: BufferIndex.uniforms.rawValue)
//        renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: BufferIndex.uniforms.rawValue)
//        renderEncoder.setFragmentTexture(Self.normalMapTexture, index: 0)
////        renderEncoder.setVertexBuffer(model.vertexBuffers.first!.buffer, offset: 0, index: BufferIndex.vertexBuffer.rawValue)
//        renderEncoder.setTriangleFillMode(.fill)
//        renderEncoder.drawIndexedPrimitives(
//            type: .triangle,
//            indexCount: mesh.indexCount,
//            indexType: mesh.indexType,
//            indexBuffer: mesh.indexBuffer.buffer,
//            indexBufferOffset: mesh.indexBuffer.offset
//        )
//
//        renderEncoder.popDebugGroup()
    }

}

extension BasicFFT: Texturable { }
