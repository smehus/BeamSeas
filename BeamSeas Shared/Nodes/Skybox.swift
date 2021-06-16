//
//  Skybox.swift
//  BeamSeas
//
//  Created by Scott Mehus on 6/16/21.
//  Copyright © 2021 Scott Mehus. All rights reserved.
//

import MetalKit

class Skybox {
    
    let mesh: MTKMesh
    var texture: MTLTexture?
    let pipelineState: MTLRenderPipelineState
    let depthStencilState: MTLDepthStencilState?
    
    init(textureName: String?) {
        
        let allocator = MTKMeshBufferAllocator(device: Renderer.device)
        let cube = MDLMesh(
            boxWithExtent: [1, 1, 1],
            segments: [1, 1, 1],
            inwardNormals: true,
            geometryType: .triangles,
            allocator: allocator
        )
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.colorAttachments[0].pixelFormat = Renderer.metalView.colorPixelFormat
        descriptor.depthAttachmentPixelFormat = .depth32Float
        descriptor.vertexFunction = Renderer.library.makeFunction(name: "vertexSkybox")
        descriptor.fragmentFunction = Renderer.library.makeFunction(name: "fragmentSkybox")
        descriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(cube.vertexDescriptor)
        
        do {
            mesh = try MTKMesh(mesh: cube, device: Renderer.device)
            pipelineState = try Renderer.device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            fatalError("Failed to initialize skybox mesh")
        }
        
        let stencilDescriptor = MTLDepthStencilDescriptor()
        stencilDescriptor.depthCompareFunction = .lessEqual
        stencilDescriptor.isDepthWriteEnabled = true
        depthStencilState = Renderer.device.makeDepthStencilState(descriptor: stencilDescriptor)
    }
}

extension Skybox: Renderable {
    
    func update(with deltaTime: Float) {
        
    }
    
    func draw(renderEncoder: MTLRenderCommandEncoder, uniforms: inout Uniforms, fragmentUniforms: inout FragmentUniforms) {
        renderEncoder.pushDebugGroup("Skybox")
        
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setVertexBuffer(
            mesh.vertexBuffers.first!.buffer,
            offset: 0,
            index: 0
        )
        
        var viewMatrix = uniforms.viewMatrix
        viewMatrix.columns.3 = [0, 0, 0, 1]
        var viewProjectionMatrix = uniforms.projectionMatrix * viewMatrix
        renderEncoder.setVertexBytes(&viewProjectionMatrix, length: MemoryLayout<float4x4>.stride, index: 1)
        
        
        let submesh = mesh.submeshes[0]
        renderEncoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: submesh.indexCount,
            indexType: submesh.indexType,
            indexBuffer: submesh.indexBuffer.buffer,
            indexBufferOffset: 0
        )
        
        renderEncoder.popDebugGroup()
    }
}
