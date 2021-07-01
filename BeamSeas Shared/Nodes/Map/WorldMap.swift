//
//  WorldMap.swift
//  BeamSeas
//
//  Created by Scott Mehus on 6/28/21.
//  Copyright © 2021 Scott Mehus. All rights reserved.
//

import Foundation
import MetalKit

final class WorldMap: Node {
    
    private let model: MTKMesh
    private let mesh: MDLMesh
    private let pipelineState: MTLRenderPipelineState
    
    private lazy var depthStencilState: MTLDepthStencilState = {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .always
        descriptor.isDepthWriteEnabled = true
        return Renderer.device.makeDepthStencilState(descriptor: descriptor)!
    }()
    
    init(vertexName: String, fragmentName: String) {
        
        let allocator = MTKMeshBufferAllocator(device: Renderer.device)
        mesh = MDLMesh(
            sphereWithExtent: [15, 15, 15],
            segments: [15, 15],
            inwardNormals: false,
            geometryType: .triangles,
            allocator: allocator
        )
        
        model = try! MTKMesh(mesh: mesh, device: Renderer.device)
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.colorAttachments[0].pixelFormat = Renderer.metalView.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        pipelineDescriptor.vertexFunction = Renderer.library.makeFunction(name: vertexName)
        pipelineDescriptor.fragmentFunction = Renderer.library.makeFunction(name: fragmentName)
        pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(model.vertexDescriptor)
        
        do {
            pipelineState = try Renderer.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("*** ERROR: \(error)")
            fatalError()
        }
        
        super.init()
        
//        scale = [0.3, 0.3, 0.3]
    }
}

extension WorldMap: Renderable {
    
    func update(with deltaTime: Float, uniforms: Uniforms, fragmentUniforms: FragmentUniforms, camera: Camera) {
        
        let size = mesh.boundingBox.maxBounds - mesh.boundingBox.minBounds
        position.y = fragmentUniforms.camera_position.y - (size.y / 2)
        // Need to offset the rotation of the camera somehow...
//        position.x = -camera.forwardVector.x.radiansToDegrees
        rotation.y = camera.rotation.y
        
        
        print("*** camera \(camera.forwardVector.x.radiansToDegrees) self: \(position)")
    }

    func draw(
        renderEncoder: MTLRenderCommandEncoder,
        uniforms: inout Uniforms,
        fragmentUniforms: inout FragmentUniforms
    ) {
        renderEncoder.pushDebugGroup("World Map")
        uniforms.modelMatrix = modelMatrix
        
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthStencilState)
        
        renderEncoder.setVertexBytes(
            &uniforms,
            length: MemoryLayout<Uniforms>.stride,
            index: BufferIndex.uniforms.rawValue
        )
        
        var viewPort = SIMD2<Float>(
            x: Float(Renderer.metalView.drawableSize.width),
            y: Float(Renderer.metalView.drawableSize.height)
        )
        renderEncoder.setVertexBytes(
            &viewPort,
            length: MemoryLayout<SIMD2<Float>>.stride,
            index: BufferIndex.viewport.rawValue
        )
        
        let mesh = model.submeshes.first!
        renderEncoder.setVertexBuffer(
            model.vertexBuffers.first!.buffer,
            offset: 0,
            index: BufferIndex.vertexBuffer.rawValue
        )
        
        renderEncoder.setTriangleFillMode(.lines)
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
