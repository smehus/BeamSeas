//
//  Model.swift
//  BeamSeas
//
//  Created by Scott Mehus on 6/17/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

import MetalKit

class Model: Node {

    static var vertexDescriptor: MDLVertexDescriptor = .defaultVertexDescriptor

    let meshes: [Mesh]
    var tiling: UInt32 = 1
    let samplerState: MTLSamplerState?
    var heightBuffer: MTLBuffer

    private let heightMap: MTLTexture
    private let altHeightMap: MTLTexture

    private let heightComputePipelineState: MTLComputePipelineState

    init(name: String) {
        guard let assetURL = Bundle.main.url(forResource: name, withExtension: nil) else { fatalError("Model: \(name) not found")  }

        let allocator = MTKMeshBufferAllocator(device: Renderer.device)
        let asset = MDLAsset(
            url: assetURL,
            vertexDescriptor: .defaultVertexDescriptor,
            bufferAllocator: allocator
        )

//        let (mdlMeshes, mtkMeshes) = try! MTKMesh.newMeshes(asset: asset, device: Renderer.device)
        var mtkMeshes: [MTKMesh] = []
        let mdlMeshes = asset.childObjects(of: MDLMesh.self) as! [MDLMesh]
        _ = mdlMeshes.map { mdlMesh in
            mdlMesh.addTangentBasis(
                forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
                tangentAttributeNamed: MDLVertexAttributeTangent,
                bitangentAttributeNamed: MDLVertexAttributeBitangent
            )

            Model.vertexDescriptor = mdlMesh.vertexDescriptor
            mtkMeshes.append(try! MTKMesh(mesh: mdlMesh, device: Renderer.device))
        }

        meshes = zip(mdlMeshes, mtkMeshes).map { Mesh(mdlMesh: $0, mtkMesh: $1) }
        samplerState = Self.buildSamplerState()

        heightMap = Submesh.loadTexture(imageName: "Heightmap_Plateau")
        altHeightMap = Submesh.loadTexture(imageName: "Heightmap_Billow")

        var startingHeight: Float = 0
        heightBuffer = Renderer.device.makeBuffer(bytes: &startingHeight, length: MemoryLayout<Float>.size, options: .storageModeShared)!

        let heightKernel = Renderer.library.makeFunction(name: "compute_height")!
        heightComputePipelineState = try! Renderer.device.makeComputePipelineState(function: heightKernel)

        super.init()

        self.name = name
    }

    private static func buildSamplerState() -> MTLSamplerState {
        let descriptor = MTLSamplerDescriptor()
        descriptor.sAddressMode = .repeat
        descriptor.tAddressMode = .repeat
        descriptor.mipFilter = .linear
        descriptor.maxAnisotropy = 8
        return Renderer.device.makeSamplerState(descriptor: descriptor)!
    }
}

extension Model: Renderable {

    func computeHeight(computeEncoder: MTLComputeCommandEncoder,
                       uniforms: inout Uniforms,
                       controlPoints: MTLBuffer,
                       terrainParams: inout TerrainParams) {

        var currentPosition = modelMatrix.columns.3.xyz

        computeEncoder.setComputePipelineState(heightComputePipelineState)
        computeEncoder.setBytes(&currentPosition, length: MemoryLayout<float3>.size, index: 0)
        computeEncoder.setBuffer(controlPoints, offset: 0, index: 1)
        computeEncoder.setBytes(&terrainParams, length: MemoryLayout<TerrainParams>.stride, index: 2)
        computeEncoder.setBuffer(heightBuffer, offset: 0, index: 3)

        computeEncoder.setTexture(heightMap, index: 0)
        computeEncoder.setTexture(altHeightMap, index: 1)

        computeEncoder.dispatchThreads(MTLSizeMake(1, 1, 1),
                                       threadsPerThreadgroup: MTLSizeMake(1, 1, 1))
    }

    func draw(renderEncoder: MTLRenderCommandEncoder, uniforms: inout Uniforms, fragmentUniforms: inout FragmentUniforms) {

        fragmentUniforms.tiling = tiling
        uniforms.modelMatrix = modelMatrix
        uniforms.normalMatrix = modelMatrix.upperLeft

        renderEncoder.setFragmentSamplerState(samplerState, index: 0)
         renderEncoder.setVertexBytes(&uniforms,
                                      length: MemoryLayout<Uniforms>.stride,
                                      index: BufferIndex.uniforms.rawValue)
         renderEncoder.setFragmentBytes(&fragmentUniforms,
                                        length: MemoryLayout<FragmentUniforms>.stride,
                                        index: BufferIndex.fragmentUniforms.rawValue)

         for mesh in meshes {

             for (index, vertexBuffer) in mesh.mtkMesh.vertexBuffers.enumerated() {
                 renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: index)
             }


             for submesh in mesh.submeshes {
                 let mtkMesh = submesh.mtkSubmesh

                 renderEncoder.setRenderPipelineState(submesh.pipelineState)
                 renderEncoder.setFragmentTexture(submesh.textures.baseColor, index: TextureIndex.color.rawValue)
                 renderEncoder.setFragmentTexture(submesh.textures.normal, index: TextureIndex.normal.rawValue)
                 var material = submesh.material
                 renderEncoder.setFragmentBytes(&material, length: MemoryLayout<Material>.stride, index: BufferIndex.materials.rawValue)

                 renderEncoder.drawIndexedPrimitives(
                     type: .triangle,
                     indexCount: mtkMesh.indexCount,
                     indexType: mtkMesh.indexType,
                     indexBuffer: mtkMesh.indexBuffer.buffer,
                     indexBufferOffset: mtkMesh.indexBuffer.offset
                 )
             }
         }
    }
}


