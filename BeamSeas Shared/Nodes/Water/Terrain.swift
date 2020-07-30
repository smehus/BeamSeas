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

    static let maxTessellation = 64
    static var heightMapName = "simuwater"
    static var alterHeightMapName = "Heightmap_Plateau"
    static var normalMapTexture: MTLTexture!
    static var secondaryNormalMapTexture: MTLTexture!
    static var primarySlopeMap: MTLTexture!
    static var secondarySlopeMap: MTLTexture!

    static var terrainParams = TerrainParams(
        size: [150, 150],
        height: 20,
        maxTessellation: UInt32(Terrain.maxTessellation),
        numberOfPatches: UInt32(Terrain.patchNum * Terrain.patchNum)
    )

    private static var patchNum = 15

    let patches = (horizontal: Terrain.patchNum, vertical: Terrain.patchNum)
    var patchCount: Int {
        return patches.horizontal * patches.vertical
    }

    var edgeFactors: [Float] = [4]
    var insideFactors: [Float] = [4]
    var allPatches: [Patch] = []

    lazy var tessellationFactorsBuffer: MTLBuffer? = {
        let count = patchCount * (4 + 2)
        let size = count * MemoryLayout<Float>.size / 2
        return Renderer.device.makeBuffer(length: size, options: .storageModePrivate)
    }()

    private let renderPipelineState: MTLRenderPipelineState
    private let computePipelineState: MTLComputePipelineState
    private let normalPipelineState: MTLComputePipelineState

    static var controlPointsBuffer: MTLBuffer!
    private let heightMap: MTLTexture
    private let altHeightMap: MTLTexture

    override init() {

        heightMap = Self.loadTexture(imageName: Terrain.heightMapName, path: "jpg")
        altHeightMap = Self.loadTexture(imageName: Self.alterHeightMapName)

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
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float
        descriptor.vertexFunction = Renderer.library.makeFunction(name: "vertex_terrain")
        descriptor.fragmentFunction = Renderer.library.makeFunction(name: "fragment_terrain")
        descriptor.tessellationFactorStepFunction = .perPatch
        descriptor.maxTessellationFactor = Self.maxTessellation
        descriptor.tessellationPartitionMode = .pow2

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

        normalPipelineState = Self.buildNormalMapPipelineState()

        // Taken from apple example
        let texDesc = MTLTextureDescriptor()
        texDesc.width = heightMap.width
        texDesc.height = heightMap.height
        texDesc.pixelFormat = .rg11b10Float
        texDesc.usage = [.shaderRead, .shaderWrite]
        texDesc.mipmapLevelCount = Int(log2(Double(max(heightMap.width, heightMap.height))) + 1);
        texDesc.storageMode = .private
        Self.normalMapTexture = Renderer.device.makeTexture(descriptor: texDesc)!


        texDesc.width = altHeightMap.width
        texDesc.height = altHeightMap.height
        texDesc.mipmapLevelCount = Int(log2(Double(max(altHeightMap.width, altHeightMap.height))) + 1);
        Self.secondaryNormalMapTexture = Renderer.device.makeTexture(descriptor: texDesc)!

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

    static func buildNormalMapPipelineState() -> MTLComputePipelineState {
        guard let kernelFunction = Renderer.library?.makeFunction(name: "TerrainKnl_ComputeNormalsFromHeightmap") else {
            fatalError("Tessellation shader function not found")
        }

        return try! Renderer.device.makeComputePipelineState(function: kernelFunction)
    }
}

extension Terrain: Renderable {

    func generateTerrainNormals(computeEncoder: MTLComputeCommandEncoder, uniforms: inout Uniforms) {
        let threadsPerGroup = MTLSize(width: 16, height: 16, depth: 1)
        computeEncoder.pushDebugGroup("Generate Normals")
        computeEncoder.setComputePipelineState(normalPipelineState)
        computeEncoder.setTexture(heightMap, index: 0)
        computeEncoder.setTexture(Self.normalMapTexture, index: 2)
        computeEncoder.setBytes(&Terrain.terrainParams, length: MemoryLayout<TerrainParams>.size, index: 3)
        computeEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: BufferIndex.uniforms.rawValue)
        computeEncoder.dispatchThreadgroups(MTLSizeMake(heightMap.width, heightMap.height, 1), threadsPerThreadgroup: threadsPerGroup)
        computeEncoder.popDebugGroup()

        // dispatch another call with the altHeightMap with an altNormalMapTexture

        computeEncoder.pushDebugGroup("Generate Normals")
        computeEncoder.setComputePipelineState(normalPipelineState)
        computeEncoder.setTexture(altHeightMap, index: 0)
        computeEncoder.setTexture(Self.secondaryNormalMapTexture, index: 2)
        computeEncoder.setBytes(&Terrain.terrainParams, length: MemoryLayout<TerrainParams>.size, index: 3)
        computeEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: BufferIndex.uniforms.rawValue)
        computeEncoder.dispatchThreadgroups(MTLSizeMake(altHeightMap.width, altHeightMap.height, 1), threadsPerThreadgroup: threadsPerGroup)
        computeEncoder.popDebugGroup()

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
            heightMap,
            index: 0
        )

        renderEncoder.setVertexTexture(
            altHeightMap,
            index: 1
        )

        renderEncoder.setVertexTexture(
            Self.normalMapTexture,
            index: 2
        )

        renderEncoder.setVertexTexture(
            Self.secondaryNormalMapTexture,
            index: 3
        )

        renderEncoder.setVertexBytes(
            &Terrain.terrainParams,
            length: MemoryLayout<TerrainParams>.stride,
            index: BufferIndex.terrainParams.rawValue
        )

        renderEncoder.setFragmentBytes(
            &fragmentUniforms,
            length: MemoryLayout<FragmentUniforms>.stride,
            index: BufferIndex.fragmentUniforms.rawValue
        )

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