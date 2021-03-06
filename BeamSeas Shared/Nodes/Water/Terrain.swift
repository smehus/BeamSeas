//
//  Terrain.swift
//  BeamSeas
//
//  Created by Scott Mehus on 6/30/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

import MetalKit
import MetalPerformanceShaders

class Terrain: Node {


    static var heightMapName = "simuwater"
    static var alterHeightMapName = "Heightmap_Plateau"
//    static var secondaryNormalMapTexture: MTLTexture!
    static var primarySlopeMap: MTLTexture!
    static var secondarySlopeMap: MTLTexture!

    static let terrainSize: Float = 300
    
    static var terrainParams = TerrainParams(
        size: [Terrain.terrainSize, Terrain.terrainSize],
        height: 50,
        maxTessellation: UInt32(Terrain.maxTessellation),
        numberOfPatches: UInt32(Terrain.patchNum * Terrain.patchNum)
    )

    static let maxTessellation = 16
    private static var patchNum = 4

    let patches = (horizontal: Terrain.patchNum, vertical: Terrain.patchNum)
    var patchCount: Int {
        return patches.horizontal * patches.vertical
    }
    
    static let edgeFactors: Float = 4
    static let insideFactors: Float = 2

    var edgeFactors: [Float] = [Terrain.edgeFactors]
    var insideFactors: [Float] = [Terrain.insideFactors]
    var allPatches: [Patch] = []
    var waterNormalTexture: MTLTexture?

    lazy var tessellationFactorsBuffer: MTLBuffer? = {
        let count = patchCount * Int(Terrain.edgeFactors + Terrain.insideFactors)
        let size = count * MemoryLayout<Float>.size / 2
        return Renderer.device.makeBuffer(length: size, options: .storageModePrivate)
    }()

    private let renderPipelineState: MTLRenderPipelineState
    private let computePipelineState: MTLComputePipelineState

    static var controlPointsBuffer: MTLBuffer!
//    private let heightMap: MTLTexture
//    private let altHeightMap: MTLTexture

    override init() {

//        heightMap = Self.loadTexture(imageName: Terrain.heightMapName, path: "jpg")
//        altHeightMap = Self.loadTexture(imageName: Self.alterHeightMapName)

        let controlPoints = Self.createControlPoints(
            patches: patches,
            size: (width: Terrain.terrainParams.size.x,
                   height: Terrain.terrainParams.size.y)
        )

        // Transform array of control points in to groups of 4 points to a patch
        // Instead of doing this on the cpu, i should just find the patch on the gpu
        allPatches = stride(from: controlPoints.startIndex, to: controlPoints.endIndex, by: 4).map {
            Patch(values: Array(controlPoints[$0..<min($0 + 4, controlPoints.count)]))
        }

        Self.controlPointsBuffer = Renderer.device.makeBuffer(
            bytes: controlPoints,
            length: MemoryLayout<float3>.stride * controlPoints.count
        )

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.colorAttachments[0].pixelFormat = Renderer.metalView.colorPixelFormat//.bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float
        descriptor.vertexFunction = Renderer.library.makeFunction(name: "vertex_terrain")
        descriptor.fragmentFunction = Renderer.library.makeFunction(name: "fragment_terrain")
        descriptor.tessellationFactorStepFunction = .perPatch
        descriptor.maxTessellationFactor = Self.maxTessellation
//        descriptor.tessellationPartitionMode = .fractionalEven
        descriptor.tessellationPartitionMode = .pow2
        descriptor.isTessellationFactorScaleEnabled = false
        descriptor.tessellationFactorFormat = .half
        descriptor.tessellationControlPointIndexType = .none
        descriptor.tessellationFactorStepFunction = .constant
        descriptor.tessellationOutputWindingOrder = .clockwise
        

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.layouts[0].stepFunction = .perPatchControlPoint
        vertexDescriptor.layouts[0].stride = MemoryLayout<float3>.stride
        

        descriptor.vertexDescriptor = vertexDescriptor

        renderPipelineState = try! Renderer.device.makeRenderPipelineState(descriptor: descriptor)

        let kernelFunction = Renderer.library.makeFunction(name: "tessellation_main")!
        computePipelineState = try! Renderer.device.makeComputePipelineState(function: kernelFunction)
        
        waterNormalTexture = Self.loadTexture(imageName: "normal-water-rotated.png")

//        texDesc.width = altHeightMap.width
//        texDesc.height = altHeightMap.height
//        texDesc.mipmapLevelCount = Int(log2(Double(max(altHeightMap.width, altHeightMap.height))) + 1);
//        Self.secondaryNormalMapTexture = Renderer.device.makeTexture(descriptor: texDesc)!

//        let primarySlopeDescriptor: MTLTextureDescriptor = .texture2DDescriptor(
//            pixelFormat: heightMap.pixelFormat,
//            width: heightMap.width,
//            height: heightMap.height,
//            mipmapped: false
//        )
//        primarySlopeDescriptor.usage = [.shaderRead, .shaderWrite]
//
//        Self.primarySlopeMap = Renderer.device.makeTexture(descriptor: primarySlopeDescriptor)!
//        Self.secondarySlopeMap = Renderer.device.makeTexture(descriptor: primarySlopeDescriptor)!
//
//        let commandBuffer = Renderer.commandQueue.makeCommandBuffer()!
//        let slopeShader = MPSImageSobel(device: Renderer.device)

//        slopeShader.encode(
//            commandBuffer: commandBuffer,
//            sourceTexture: heightMap,
//            destinationTexture: Self.primarySlopeMap
//        )
//
//        slopeShader.encode(
//            commandBuffer: commandBuffer,
//            sourceTexture: altHeightMap,
//            destinationTexture: Self.secondarySlopeMap
//        )

//        commandBuffer.commit()

        super.init()
        
        
    }
}

extension Terrain: Renderable {

    func update(
        deltaTime: Float,
        uniforms: Uniforms,
        fragmentUniforms: FragmentUniforms,
        camera: Camera,
        player: Model
    ) {
        
    }

    // tesellate plane into a bunch of vertices
    func compute(
        computeEncoder: MTLComputeCommandEncoder,
        uniforms: inout Uniforms,
        fragmentUniforms: inout FragmentUniforms
    ) {

        uniforms.modelMatrix = modelMatrix

        computeEncoder.setComputePipelineState(computePipelineState)
        computeEncoder.setBytes(
            &edgeFactors,
            length: MemoryLayout<Float>.size * edgeFactors.count,
            index: 0
        )

        computeEncoder.setBytes(
            &insideFactors,
            length: MemoryLayout<Float>.size * insideFactors.count,
            index: 1
        )

        computeEncoder.setBuffer(
            tessellationFactorsBuffer,
            offset: 0,
            index: 2
        )

        computeEncoder.setBuffer(
            Self.controlPointsBuffer,
            offset: 0,
            index: BufferIndex.controlPoints.rawValue
        )

        computeEncoder.setBytes(
            &uniforms,
            length: MemoryLayout<Uniforms>.stride,
            index: BufferIndex.uniforms.rawValue
        )

        computeEncoder.setBytes(
            &Terrain.terrainParams,
            length: MemoryLayout<TerrainParams>.stride,
            index: BufferIndex.terrainParams.rawValue
        )

        let width = min(patchCount, computePipelineState.threadExecutionWidth)
        computeEncoder.dispatchThreadgroups(
            MTLSizeMake(patchCount, 1, 1),
            threadsPerThreadgroup: MTLSizeMake(width, 1, 1)
        )
    }

    func draw(
        renderEncoder: MTLRenderCommandEncoder,
        uniforms: inout Uniforms,
        fragmentUniforms: inout FragmentUniforms
    ) {
        renderEncoder.pushDebugGroup("Terrain Vertex")
        uniforms.modelMatrix = modelMatrix
        uniforms.normalMatrix = modelMatrix.upperLeft

        renderEncoder.setTriangleFillMode(.fill)
        renderEncoder.setRenderPipelineState(renderPipelineState)
        renderEncoder.setVertexBytes(
            &uniforms,
            length: MemoryLayout<Uniforms>.stride,
            index: BufferIndex.uniforms.rawValue
        )

        renderEncoder.setTessellationFactorBuffer(
            tessellationFactorsBuffer,
            offset: 0,
            instanceStride: 0
        )

        renderEncoder.setVertexBuffer(
            Self.controlPointsBuffer,
            offset: 0,
            index: 0
        )

        // TODO: - Need to implement argument buffers & resource heaps
        renderEncoder.setVertexTexture(
            BasicFFT.heightDisplacementMap,
            index: 0
        )

        renderEncoder.setVertexBytes(
            &Terrain.terrainParams,
            length: MemoryLayout<TerrainParams>.stride,
            index: BufferIndex.terrainParams.rawValue
        )
        
        renderEncoder.setVertexBytes(
            &fragmentUniforms,
            length: MemoryLayout<FragmentUniforms>.stride,
            index: BufferIndex.fragmentUniforms.rawValue
        )

        
        // Fragment shader \\
        renderEncoder.setFragmentBytes(
            &Terrain.terrainParams,
            length: MemoryLayout<TerrainParams>.stride,
            index: BufferIndex.terrainParams.rawValue
        )

        renderEncoder.setFragmentBytes(
            &fragmentUniforms,
            length: MemoryLayout<FragmentUniforms>.stride,
            index: BufferIndex.fragmentUniforms.rawValue
        )

        renderEncoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<Uniforms>.stride,
            index: BufferIndex.uniforms.rawValue
        )

        renderEncoder.setVertexTexture(BasicFFT.normalMapTexture, index: 1)

        renderEncoder.setFragmentTexture(
            BasicFFT.gradientMap,
            index: 0
        )

        renderEncoder.setFragmentTexture(
            BasicFFT.normalMapTexture,
            index: 2
        )

        renderEncoder.setFragmentTexture(
            waterNormalTexture,
            index: TextureIndex.waterRipple.rawValue
        )


//        renderEncoder.setTriangleFillMode(.lines)
        renderEncoder.drawPatches(
            numberOfPatchControlPoints: 4,
            patchStart: 0,
            patchCount: patchCount,
            patchIndexBuffer: nil,
            patchIndexBufferOffset: 0,
            instanceCount: 1,
            baseInstance: 0
        )

        renderEncoder.popDebugGroup()
    }
}

extension Terrain {
    /**
     Create control points
     - Parameters:
         - patches: number of patches across and down
         - size: size of plane
     - Returns: an array of patch control points. Each group of four makes one patch.
     **/
    static func createControlPoints(patches: (horizontal: Int, vertical: Int),
                                    size: (width: Float, height: Float)) -> [float3] {

        var points: [float3] = []
        // per patch width and height
        let width = 1 / Float(patches.horizontal)
        let height = 1 / Float(patches.vertical)

        for j in 0..<patches.vertical {
            let row = Float(j)
            for i in 0..<patches.horizontal {
                let column = Float(i)

                let left = width * column
                let bottom = height * row
                let right = width * column + width
                let top = height * row + height

                points.append([left, 0, top])
                points.append([right, 0, top])
                points.append([right, 0, bottom])
                points.append([left, 0, bottom])

            }
        }
        // size and convert to Metal coordinates
        // eg. 6 across would be -3 to + 3
        points = points.map {
            [$0.x * size.width - size.width / 2,
             0,
             $0.z * size.height - size.height / 2]
        }

        return points
    }
}

struct Patch {

    let topLeft: float3
    let topRight: float3
    let bottomRight: float3
    let bottomLeft: float3

    init(values: [float3]) {
        topLeft = values[0]
        topRight = values[1]
        bottomRight = values[2]
        bottomLeft = values[3]
    }
}

extension Terrain: Texturable { }
