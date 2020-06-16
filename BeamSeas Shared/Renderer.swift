//
//  Renderer.swift
//  BeamSeas Shared
//
//  Created by Scott Mehus on 6/15/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

// Our platform independent renderer class

import Metal
import MetalKit
import simd

class Renderer: NSObject {

    static var device: MTLDevice!
    static var commandQueue: MTLCommandQueue!
    var mesh: MTKMesh!
    var vertexBuffer: MTLBuffer!
    var pipelineState: MTLRenderPipelineState!

    init?(metalView: MTKView) {
        Self.device = metalView.device!
        Self.commandQueue = Renderer.device.makeCommandQueue()!

        mesh = Self.loadTrain()
        vertexBuffer = mesh.vertexBuffers[0].buffer

        let library = Self.device.makeDefaultLibrary()!
        let vertexFunction = library.makeFunction(name: "vertex_main")
        let fragmentFunction = library.makeFunction(name: "fragment_main")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(mesh.vertexDescriptor)
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat

        pipelineState = try! Self.device.makeRenderPipelineState(descriptor: pipelineDescriptor)

        super.init()

        metalView.clearColor = MTLClearColor(
            red: 1.0,
            green: 1.0,
            blue: 0.8,
            alpha: 1.0
        )

        metalView.delegate = self

    }

    static func loadTrain() -> MTKMesh {
        let allocator = MTKMeshBufferAllocator(device: Self.device)
        let assetURL = Bundle.main.url(forResource: "train", withExtension: "obj")!

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0

        vertexDescriptor.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride
        let meshDescriptor = MTKModelIOVertexDescriptorFromMetal(vertexDescriptor)
        (meshDescriptor.attributes[0] as! MDLVertexAttribute).name = MDLVertexAttributePosition

        let asset = MDLAsset(
            url: assetURL,
            vertexDescriptor: meshDescriptor,
            bufferAllocator: allocator
        )

        let mdlMesh = asset.childObjects(of: MDLMesh.self).first! as! MDLMesh
        return try! MTKMesh(mesh: mdlMesh, device: Self.device)
    }

    static func cube() -> MTKMesh {
        let allocator = MTKMeshBufferAllocator(device: Renderer.device)
        let mesh = MDLMesh(
            boxWithExtent: [1, 1, 1],
            segments: [1, 1, 1],
            inwardNormals: false,
            geometryType: .triangles,
            allocator: allocator
        )

        return try! MTKMesh(mesh: mesh, device: Renderer.device)
    }
}

extension Renderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {

    }

    func draw(in view: MTKView) {
        guard
            let descriptor = view.currentRenderPassDescriptor,
            let commandBuffer = Self.commandQueue.makeCommandBuffer(),
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else {
            return
        }

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        for submesh in mesh.submeshes {
            renderEncoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: submesh.indexCount,
                indexType: submesh.indexType,
                indexBuffer: submesh.indexBuffer.buffer,
                indexBufferOffset: submesh.indexBuffer.offset
            )
        }


        renderEncoder.endEncoding()
        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }
}
