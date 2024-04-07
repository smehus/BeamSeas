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
import Numerics

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

    var distribution: MTLBuffer
    var displacement: MTLBuffer
    var normal: MTLBuffer

    private let fftPipelineState: MTLComputePipelineState
    private let normalDrawingPipepline: MTLComputePipelineState
    private let secondaryNormalPipeline: MTLComputePipelineState
    private let mainPipelineState: MTLRenderPipelineState

    static var heightDisplacementMap: MTLTexture!
    static var gradientMap: MTLTexture!
    static var normalMapTexture: MTLTexture!
    static var secondaryNormalMapTexture: MTLTexture!

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
    

    override init() {

        let allocator = MTKMeshBufferAllocator(device: Renderer.device)
        let prim = MDLMesh(planeWithExtent: [0.5, 0.5, 0], segments: [4, 4], geometryType: .triangles, allocator: allocator)
        model = try! MTKMesh(mesh: prim, device: Renderer.device)

        let log2n = vDSP_Length(log2(Float((Terrain.K.SIZE * Terrain.K.SIZE))))
        distributionFFT = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self)!

        let s = (Terrain.K.SIZE * Terrain.K.SIZE) >> (1 * 2)
        let downdSampledLog2n = vDSP_Length(log2(Float(s)))
        downsampledFFT = vDSP.FFT(log2n: downdSampledLog2n, radix: .radix5, ofType: DSPSplitComplex.self)!

        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, // <---- This thing sucks
            width: Terrain.K.textureSize,
            height: Terrain.K.textureSize,
            mipmapped: false
        )

        texDesc.usage = [.shaderRead, .shaderWrite]
        texDesc.storageMode = .private

        // Final textures for main pass
        Self.heightDisplacementMap = Renderer.device.makeTexture(descriptor: texDesc)!
        Self.gradientMap = Renderer.device.makeTexture(descriptor: texDesc)!
        heightMap = Renderer.device.makeTexture(descriptor: texDesc)!
        displacementMap = Renderer.device.makeTexture(descriptor: texDesc)!


//        texDesc.pixelFormat = .rg11b10Float
        Self.normalMapTexture = Renderer.device.makeTexture(descriptor: texDesc)!
        Self.secondaryNormalMapTexture = Renderer.device.makeTexture(descriptor: texDesc)!

        // Drawing distribution & displacement values onto textures
        fftPipelineState = Self.buildComputePipelineState(shader: "fft_kernel")
        
        // Drawing (non apple) generated normals. Need separate because val = (val - -1) / (1 - -1); ! needs to change to scale down. Or maybe the distribution?
        normalDrawingPipepline = Self.buildComputePipelineState(shader: "normal_draw_kernel")
        
        // Generate distribution values
        distributionPipelineState = Self.buildComputePipelineState(shader: "generate_distribution_map_values")
        
        // Generate displacement values
        displacementPipelineState = Self.buildComputePipelineState(shader: "generate_displacement_map_values")
        
        // Combining displacement teuxture & height texture onto one combined texture
        heightDisplacementGradientPipelineState = Self.buildComputePipelineState(shader: "compute_height_displacement_graident")
        
        // Generate normal values from height texture & draw onto normal texture
        normalPipelineState = Self.buildComputePipelineState(shader: "TerrainKnl_ComputeNormalsFromHeightmap")
        
        // Instead of ^ - generate normal distributions with the other distribtuions
        secondaryNormalPipeline = Self.buildComputePipelineState(shader: "generate_normal_map_values")

        let mainPipeDescriptor = MTLRenderPipelineDescriptor()
        mainPipeDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        mainPipeDescriptor.depthAttachmentPixelFormat = .depth32Float
        mainPipeDescriptor.vertexFunction = Renderer.library.makeFunction(name: "fft_vertex")
        mainPipeDescriptor.fragmentFunction = Renderer.library.makeFunction(name: "fft_fragment")
        mainPipeDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(model.vertexDescriptor)

        mainPipelineState = try! Renderer.device.makeRenderPipelineState(descriptor: mainPipeDescriptor)
        
        source = Water(
            amplitude: Float(Terrain.K.amplitude), // 1.0
            wind_velocity: Terrain.K.wind_velocity, // 26, -22
            resolution: SIMD2<Int>(x: Terrain.K.SIZE, y: Terrain.K.SIZE), // Determines the amount of random numbers // 128
            size: float2(x: Terrain.K.DIST, y: Terrain.K.DIST), // Size is used for amplitude modifiers // 128
            normalmap_freq_mod: float2(repeating: Terrain.K.NORMALMAP_FREQ_MOD) // @TODO: -- FUCK I NEED THIS!!!!! // 7.3
        )

        // Creating buffers to fill up with distribution_real(etc) -> FFT -> Our buffer here
        guard
            let dist = Renderer.device.makeBuffer(length: MemoryLayout<Float>.stride * source.distribution.count, options: .storageModeShared),
            let norm = Renderer.device.makeBuffer(length: MemoryLayout<Float>.stride * source.distribution_normal.count, options: .storageModeShared),
            let disp  = Renderer.device.makeBuffer(length: MemoryLayout<Float>.size * source.distribution_displacement.count, options: .storageModeShared)
        else {
            fatalError()
        }

        distribution = dist
        displacement = disp
        normal = norm

        super.init()

    } // init

    
    // This runs after 'generate_distributions' - so we get updated distribution_real / imag buffer values.
    // The source buffer values will all remain the same (Buffers in water.swift)
    func runfft(phase: Float) {
        let recreatedSignal = runfft(
            dist: distribution,
            count: source.distribution.count + source.distribution.count,
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
            dist: normal,
            count: source.distribution_normal.count + source.distribution_normal.count,
            fft: distributionFFT
        )

        normalBuffer = Renderer.device.makeBuffer(
            bytes: normalSignal,
            length: MemoryLayout<Float>.stride * normalSignal.count
        )

        let displacementSignal = runfft(
            dist: displacement,
            count: source.distribution_displacement.count + source.distribution_displacement.count,
            fft: distributionFFT// use this for downsampling - downsampledFFT
        )
        
        displacementBuffer = Renderer.device.makeBuffer(
            bytes: displacementSignal,
            length: MemoryLayout<Float>.stride * displacementSignal.count,
            options: []
        )
    }

    private func runfft(dist: MTLBuffer, count: Int, fft transformer: vDSP.FFT<DSPSplitComplex>)  -> [Float] {
        var inverseOutputReal = [Float](repeating: 0, count: count / 2)
        var inverseOutputImag = [Float](repeating: 0, count: count / 2)

        var inputReal = [Float](repeating: 0, count: count / 2)
        var inputImag = [Float](repeating: 0, count: count / 2)

        var pointer = dist.contents().bindMemory(to: Complex<Float>.self, capacity: count / 2)

        for index in 0..<(count / 2) {
            inputReal[index] = pointer.pointee.real
            inputImag[index] = pointer.pointee.imaginary

            pointer = pointer.advanced(by: 1)
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
        var gausUniforms = GausUniforms(
            dataLength: Int32(Terrain.K.SIZE * Terrain.K.SIZE),
            amplitude: Float(Terrain.K.amplitude),
//            wind_velocity: vector_float2(x: BasicFFT.wind_velocity.x, y: BasicFFT.wind_velocity.y),
            resolution: vector_uint2(x: Terrain.K.SIZE.unsigned, y: Terrain.K.SIZE.unsigned),
            size: vector_float2(x: Terrain.K.DIST, y: Terrain.K.DIST),
            normalmap_freq_mod: vector_float2(repeating: Terrain.K.NORMALMAP_FREQ_MOD),
            seed: seed
        )
        
        
        let makeThreadGroup: ((MTLComputePipelineState) -> (count: MTLSize, size: MTLSize)) = { pipeline in
            let w = pipeline.threadExecutionWidth
            let h = pipeline.maxTotalThreadsPerThreadgroup / w
            
            let threadGroupSize = MTLSizeMake(w, h, 1)
            let threadGrpCount = MTLSizeMake(Terrain.K.SIZE, Terrain.K.SIZE, 1)
            
            return (threadGrpCount, threadGroupSize)
        }

        var uniforms = uniforms
        
        

        computeEncoder.pushDebugGroup("FFT-Distribution")
        var threadGroup = makeThreadGroup(distributionPipelineState)
        computeEncoder.setComputePipelineState(distributionPipelineState)
        computeEncoder.setBytes(&gausUniforms, length: MemoryLayout<GausUniforms>.stride, index: BufferIndex.gausUniforms.rawValue)
        computeEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: BufferIndex.uniforms.rawValue)
        // Output
        computeEncoder.setBuffer(distribution_real, offset: 0, index: 12)
        computeEncoder.setBuffer(distribution_imag, offset: 0, index: 13)

        // Input
        computeEncoder.setBuffer(source.distribution_real_buffer, offset: 0, index: 14)
        computeEncoder.setBuffer(source.distribution_imag_buffer, offset: 0, index: 15)
        computeEncoder.setTexture(BasicFFT.heightDisplacementMap, index: 0)

        computeEncoder.dispatchThreads(threadGroup.count, threadsPerThreadgroup: threadGroup.size)
        computeEncoder.popDebugGroup()
        
        
        // Create normals the non apple way
        computeEncoder.pushDebugGroup("FFT-Normal_Distributions")
        computeEncoder.setComputePipelineState(secondaryNormalPipeline)
//        threadGroup = makeThreadGroup(secondaryNormalPipeline)
        computeEncoder.setBytes(&gausUniforms, length: MemoryLayout<GausUniforms>.stride, index: BufferIndex.gausUniforms.rawValue)
        computeEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: BufferIndex.uniforms.rawValue)
        // Output
        computeEncoder.setBuffer(distribution_normal_real, offset: 0, index: 12)
        computeEncoder.setBuffer(distribution_normal_imag, offset: 0, index: 13)

        // Input
        computeEncoder.setBuffer(source.distribution_normal_real_buffer, offset: 0, index: 14)
        computeEncoder.setBuffer(source.distribution_normal_imag_buffer, offset: 0, index: 15)
        computeEncoder.setTexture(BasicFFT.heightDisplacementMap, index: 0)


        computeEncoder.dispatchThreads(threadGroup.count, threadsPerThreadgroup: threadGroup.size)
        computeEncoder.popDebugGroup()
        

        computeEncoder.pushDebugGroup("FFT-Displacement")
        computeEncoder.setComputePipelineState(displacementPipelineState)
        threadGroup = makeThreadGroup(displacementPipelineState)
        // output
        computeEncoder.setBuffer(distribution_displacement_real, offset: 0, index: 12)
        computeEncoder.setBuffer(distribution_displacement_imag, offset: 0, index: 13)

        // Input
        computeEncoder.setBuffer(source.distribution_displacement_real_buffer, offset: 0, index: 14)
        computeEncoder.setBuffer(source.distribution_displacement_imag_buffer, offset: 0, index: 15)

        computeEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: BufferIndex.uniforms.rawValue)
        computeEncoder.dispatchThreads(threadGroup.count, threadsPerThreadgroup: threadGroup.size)
        computeEncoder.popDebugGroup()
    }



    func generateMaps(computeEncoder: MTLComputeCommandEncoder, uniforms: inout Uniforms) {
        // Create diplacement & height maps

        computeEncoder.pushDebugGroup("FFT-Drawing-Height")

        computeEncoder.setComputePipelineState(fftPipelineState)
        computeEncoder.setTexture(heightMap, index: 0)
        computeEncoder.setBuffer(dataBuffer, offset: 0, index: 0)
        uniforms.distrubtionSize = UInt32(Terrain.K.SIZE)
        computeEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: BufferIndex.uniforms.rawValue)
        computeEncoder.dispatchThreadgroups(
            MTLSizeMake(1, Terrain.K.textureSize, 1), // Adds up to the amount of values in ROWS (512)
            threadsPerThreadgroup: MTLSizeMake(Terrain.K.textureSize, 1, 1) // Add up to amount of values in COLUMNS (512)
        )
        computeEncoder.popDebugGroup()
        
        
        computeEncoder.pushDebugGroup("FFT-Drawing-Normal")

        computeEncoder.setComputePipelineState(normalDrawingPipepline)
        computeEncoder.setTexture(Self.secondaryNormalMapTexture, index: 0)
        computeEncoder.setBuffer(normalBuffer, offset: 0, index: 0)
        computeEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: BufferIndex.uniforms.rawValue)
        computeEncoder.dispatchThreadgroups(
            MTLSizeMake(1, Terrain.K.textureSize, 1), // Adds up to the amount of values in ROWS (512)
            threadsPerThreadgroup: MTLSizeMake(Terrain.K.textureSize, 1, 1) // Add up to amount of values in COLUMNS (512)
        )
        computeEncoder.popDebugGroup()
        

        computeEncoder.pushDebugGroup("FFT-Drawing-Displacement")
        computeEncoder.setComputePipelineState(fftPipelineState)
        computeEncoder.setTexture(displacementMap, index: 0)
        computeEncoder.setBuffer(displacementBuffer, offset: 0, index: 0)

        computeEncoder.dispatchThreadgroups(
            MTLSizeMake(1, Terrain.K.textureSize, 1), // Adds up to the amount of values in ROWS (512)
            threadsPerThreadgroup: MTLSizeMake(Terrain.K.textureSize, 1, 1) // Add up to amount of values in COLUMNS (512)
        )
        
        computeEncoder.popDebugGroup()
    }
    
    // Bake height gradient - Combine displacement and height maps
    // Create final map to use for tessellation
    func generateGradient(computeEncoder: MTLComputeCommandEncoder, uniforms: inout Uniforms) {
        computeEncoder.pushDebugGroup("FFT-Gradient")
        computeEncoder.setComputePipelineState(heightDisplacementGradientPipelineState)

        //        compute_height_graident will generate the draw texture used for terrain vertex
        computeEncoder.setTexture(heightMap, index: 0)
        computeEncoder.setTexture(displacementMap, index: 1)
        computeEncoder.setTexture(Self.heightDisplacementMap, index: 2) // separate these out?
        computeEncoder.setTexture(Self.gradientMap, index: 3)// what is this?
        // should have
        // - heightdisplacementmap
        // - gradientjacobianmap
        // I guess i have that...

        var invSize = float4(
            x: 1.0 / Float(Terrain.K.textureSize),
            y: 1.0 / Float(Terrain.K.textureSize),
            z: 1.0 / Float(Terrain.K.textureSize >> 1),
            w: 1.0 / Float(Terrain.K.textureSize >> 1)
        )

        computeEncoder.setBytes(&invSize, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)

        var uScale = float4(
            x: Float(Terrain.K.SIZE) / Terrain.K.DIST,
            y: Float(Terrain.K.SIZE) / Terrain.K.DIST,
            z: (Float(Terrain.K.SIZE >> 1)) / Terrain.K.DIST,
            w: (Float(Terrain.K.SIZE >> 1)) / Terrain.K.DIST
        )

        computeEncoder.setBytes(&uScale, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)


        computeEncoder.dispatchThreadgroups(
            MTLSizeMake(1, Terrain.K.textureSize, 1), // Adds up to the amount of values in ROWS (512)
            threadsPerThreadgroup: MTLSizeMake(Terrain.K.textureSize, 1, 1) // Add up to amount of values in COLUMNS (512)
        )
        computeEncoder.popDebugGroup()
    }

    // Going to try and do this in `generateDistributions`
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
            MTLSizeMake(1, Terrain.K.textureSize, 1),
            threadsPerThreadgroup: MTLSizeMake(Terrain.K.textureSize, 1, 1)
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
        renderEncoder.setFragmentTexture(Self.secondaryNormalMapTexture, index: 0)
//        renderEncoder.setFragmentTexture(Self.normalMapTexture, index: 0)
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




        renderEncoder.pushDebugGroup("Tiny Map - Normal")
        position.x = -0.75
        position.y = 0.25

        uniforms.modelMatrix = modelMatrix
        renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: BufferIndex.uniforms.rawValue)
        renderEncoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: BufferIndex.uniforms.rawValue)
        renderEncoder.setFragmentTexture(Self.normalMapTexture, index: 0)
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
    }

}

extension BasicFFT: Texturable { }
