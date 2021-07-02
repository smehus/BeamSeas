//
//  WorldMap.swift
//  BeamSeas
//
//  Created by Scott Mehus on 6/28/21.
//  Copyright © 2021 Scott Mehus. All rights reserved.
//

import Foundation
import MetalKit

final class WorldMap: Node, Meshable {
    
    private(set) var mesh: MDLMesh
    private let model: MTKMesh
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
            sphereWithExtent: [100, 100, 100],
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
    
    func update(
        deltaTime: Float,
        uniforms: Uniforms,
        fragmentUniforms: FragmentUniforms,
        camera: Camera,
        player: Model
    ) {
        rotation.y = camera.rotation.y
        
        let tempWorldSize = SIMD2<Float>(x: 3000, y: 3000)
        
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
        
        let drawableWidth = Renderer.metalView.drawableSize.width.double / 4
        let drawableHeight = Renderer.metalView.drawableSize.height.double / 4
        
        renderEncoder.setViewport(
            MTLViewport(originX: Renderer.metalView.drawableSize.width.double - drawableWidth,
                        originY: 0,
                        width: drawableWidth,
                        height: drawableHeight,
                        znear: 0.001,
                        zfar: 1)
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

extension CGFloat {
    
    var double: Double {
        Double(self)
    }
}
