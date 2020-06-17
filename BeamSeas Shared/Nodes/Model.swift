//
//  Model.swift
//  BeamSeas
//
//  Created by Scott Mehus on 6/17/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

import MetalKit

extension MDLVertexDescriptor {
    static var defaultVertexDescriptor: MDLVertexDescriptor = {
        let vertexDescriptor = MDLVertexDescriptor()
        var offset = 0
        vertexDescriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition,
                                                            format: .float3,
                                                            offset: 0, bufferIndex: 0)
        offset += MemoryLayout<float3>.stride

        // add the normal attribute here

        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: offset)
        return vertexDescriptor
    }()
}

class Model: Node {

    let pipelineState: MTLRenderPipelineState
    let meshes: [Mesh]

    init(name: String) {
        guard let assetURL = Bundle.main.url(forResource: name, withExtension: nil) else { fatalError("Model: \(name) not found")  }

        let allocator = MTKMeshBufferAllocator(device: Renderer.device)
        let asset = MDLAsset(
            url: assetURL,
            vertexDescriptor: .defaultVertexDescriptor,
            bufferAllocator: allocator
        )

        let (mdlMeshes, mtkMeshes) = try! MTKMesh.newMeshes(asset: asset, device: Renderer.device)

        meshes = zip(mdlMeshes, mtkMeshes).map { Mesh(mdlMesh: $0, mtkMesh: $1) }
        pipelineState = Self.buildPipelineState()

        super.init()

        self.name = name
    }

    private static func buildPipelineState() -> MTLRenderPipelineState {
        let library = Renderer.library
        let vertexFunction = library?.makeFunction(name: "vertex_main")
        let fragmentFunction = library?.makeFunction(name: "fragment_main")

        var pipelineState: MTLRenderPipelineState
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        let vertexDescriptor = MDLVertexDescriptor.defaultVertexDescriptor
        pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(vertexDescriptor)
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        do {
            pipelineState = try Renderer.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch let error {
            fatalError(error.localizedDescription)
        }
        return pipelineState
    }
}
