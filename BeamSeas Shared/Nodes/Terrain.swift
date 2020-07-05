//
//  Terrain.swift
//  BeamSeas
//
//  Created by Scott Mehus on 6/30/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

import MetalKit


class Terrain: Node {

    static let maxTessellation = 16

    var terrainParams = TerrainParams(
        size: [8, 8],
        height: 1,
        maxTessellation: UInt32(Terrain.maxTessellation)
    )

    let patches = (horizontal: 6, vertical: 6)
    var patchCount: Int {
        return patches.horizontal * patches.vertical
    }

    var edgeFactors: [Float] = [4]
    var insideFactors: [Float] = [4]

    lazy var tessellationFactorsBuffer: MTLBuffer? = {
        let count = patchCount * (4 + 2)
        let size = count * MemoryLayout<Float>.size / 2
        return Renderer.device.makeBuffer(length: size, options: .storageModePrivate)
    }()

    private let renderPipelineState: MTLRenderPipelineState
    private let computePipelineState: MTLComputePipelineState
    private var controlPointsBuffer: MTLBuffer!
    private let heightMap: MTLTexture
    private var timer: Float = 0

    override init() {

        heightMap = Self.loadTexture(imageName: "mountain")

        let controlPoints = Self.createControlPoints(
            patches: patches,
            size: (width: terrainParams.size.x,
                   height: terrainParams.size.y)
        )

        controlPointsBuffer = Renderer.device.makeBuffer(
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


        super.init()
    }
}

extension Terrain: Renderable {

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
            controlPointsBuffer,
            offset: 0,
            index: BufferIndex.controlPoints.rawValue
        )

        computeEncoder.setBytes(
            &uniforms,
            length: MemoryLayout<Uniforms>.stride,
            index: BufferIndex.uniforms.rawValue
        )

        computeEncoder.setBytes(
            &terrainParams,
            length: MemoryLayout<TerrainParams>.stride,
            index: BufferIndex.terrainParams.rawValue
        )

        let width = min(patchCount, computePipelineState.threadExecutionWidth)
        computeEncoder.dispatchThreadgroups(
            MTLSizeMake(patchCount, 1, 1),
            threadsPerThreadgroup: MTLSizeMake(width, 1, 1)
        )

        computeEncoder.endEncoding()
    }

    func draw(
        renderEncoder: MTLRenderCommandEncoder,
        uniforms: inout Uniforms,
        fragmentUniforms: inout FragmentUniforms
    ) {

        timer += 0.01
        var currentTime = sin(timer)
        renderEncoder.setVertexBytes(
            &currentTime,
            length: MemoryLayout<Float>.stride,
            index: 6
        )

        uniforms.modelMatrix = modelMatrix

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
            controlPointsBuffer,
            offset: 0,
            index: 0
        )

        renderEncoder.setVertexTexture(
            heightMap,
            index: 0
        )

        renderEncoder.setVertexBytes(
            &terrainParams,
            length: MemoryLayout<TerrainParams>.stride,
            index: BufferIndex.terrainParams.rawValue
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

extension Terrain: Texturable { }
