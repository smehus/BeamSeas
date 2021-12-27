//
//  BasicShape.swift
//  BeamSeas
//
//  Created by Scott Mehus on 12/27/21.
//  Copyright © 2021 Scott Mehus. All rights reserved.
//

import Foundation
import MetalKit

class BasicShape: Node {
    
    enum Shape {
        case sphere(extent: vector_float3, segments: vector_uint2, inwardNormals: Bool, geometryType: MDLGeometryType, material: Material)
        
        var material: Material {
            guard case let .sphere(_, _, _, _, material) = self else { fatalError() }
            
            return material
        }
    }
    
    private let shape: Shape
    private let mdlMesh: MDLMesh
    private let mesh: MTKMesh
    private let pipelineState: MTLRenderPipelineState
    
    init(shape: Shape) {
        self.shape = shape
        self.mdlMesh = Self.createShape(with: shape)
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.colorAttachments[0].pixelFormat = Renderer.metalView.colorPixelFormat
        descriptor.depthAttachmentPixelFormat = .depth32Float
        descriptor.vertexFunction = Renderer.library.makeFunction(name: "basicShape_vertex")
        descriptor.fragmentFunction = Renderer.library.makeFunction(name: "basicShape_fragment")
        descriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(self.mdlMesh.vertexDescriptor)
        
        mesh = try! MTKMesh(mesh: self.mdlMesh, device: Renderer.device)
        pipelineState = try! Renderer.device.makeRenderPipelineState(descriptor: descriptor)
        
        super.init()
    }
    
    static func createShape(with shape: Shape) -> MDLMesh {
        guard case let .sphere(extent, segments, inwardNormals, geometryType, _) = shape else { fatalError() }
        
        let allocator = MTKMeshBufferAllocator(device: Renderer.device)
        let sphere = MDLMesh(
            sphereWithExtent: extent,
            segments: segments,
            inwardNormals: inwardNormals,
            geometryType: geometryType,
            allocator: allocator
        )
        
        return sphere
    }
}

extension BasicShape: Renderable {
    
    func update(
        deltaTime: Float,
        uniforms: inout Uniforms,
        fragmentUniforms: inout FragmentUniforms,
        camera: Camera,
        scaffolding: WorldMapScaffolding,
        player: Model
    ) {

    }
    
    func draw(renderEncoder: MTLRenderCommandEncoder, uniforms: inout Uniforms, fragmentUniforms: inout FragmentUniforms) {
        defer { renderEncoder.popDebugGroup() }
        
        renderEncoder.pushDebugGroup("BasicShape")

        uniforms.modelMatrix = worldTransform//position.rotationMatrix * .identity() * scale.rotationMatrix

        renderEncoder.setRenderPipelineState(pipelineState)

        let submesh = mesh.submeshes.first!
        renderEncoder.setVertexBuffer(
            mesh.vertexBuffers.first!.buffer,
            offset: 0,
            index: BufferIndex.vertexBuffer.rawValue
        )
        
        renderEncoder.setVertexBytes(
            &uniforms,
            length: MemoryLayout<Uniforms>.stride,
            index: BufferIndex.uniforms.rawValue
        )

        var material = shape.material
        renderEncoder.setFragmentBytes(&material, length: MemoryLayout<Material>.stride, index: BufferIndex.materials.rawValue)

        renderEncoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: submesh.indexCount,
            indexType: submesh.indexType,
            indexBuffer: submesh.indexBuffer.buffer,
            indexBufferOffset: submesh.indexBuffer.offset
        )
    }
}

