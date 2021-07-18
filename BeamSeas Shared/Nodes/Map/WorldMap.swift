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
    private var mapUniforms = Uniforms()
    
    private lazy var mapCamera: Camera = {
        let camera = Camera()
        camera.near = 0.0001
        camera.far = 500
        
        return camera
    }()
    
    struct Constant {
        static let rotationModifier: Float = 0.1
    }
    
    private lazy var depthStencilState: MTLDepthStencilState = {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .always
        descriptor.isDepthWriteEnabled = true
        return Renderer.device.makeDepthStencilState(descriptor: descriptor)!
    }()
    
    init(vertexName: String, fragmentName: String) {
        
        let allocator = MTKMeshBufferAllocator(device: Renderer.device)
        mesh = MDLMesh(
            sphereWithExtent: [20, 20, 20],
            segments: [30, 30],
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
        
        position = float3(0, 0, 30)
        scale = float3(0.1, 0.1, 0.1)
        
    }
}

extension WorldMap: AspectRatioUpdateable {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        mapCamera.aspect = Float(size.width) / Float(size.height)
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

        switch player.moveState {
        case .rotateLeft, .rotateRight:
            // This resets it yo
//            rotation.y = camera.rotation.y
        break
        case .forward:
            let fps = (1.float / Renderer.metalView.preferredFramesPerSecond.float)
            rotation.y += (fps * player.forwardVector.x) //* Constant.rotationModifier
        fallthrough
        case .stopped:
            break
        }
        
////        print(uniforms.playerMovement)
//        print(player.forwardVector)
    }

    func draw(
        renderEncoder: MTLRenderCommandEncoder,
        uniforms: inout Uniforms,
        fragmentUniforms: inout FragmentUniforms
    ) {
        defer {
            renderEncoder.popDebugGroup()
        }
        
        renderEncoder.pushDebugGroup("World Map")
        mapUniforms = uniforms
//        let translation = float4x4(translation: [0, 0, 30])
//        let rotation = float4x4(rotation: [0, 0, 0])
//        let scale = float4x4(scaling: 0.1)
        mapUniforms.modelMatrix = modelMatrix//(translation * rotation * scale)
        mapUniforms.viewMatrix = mapCamera.viewMatrix// float4x4(translation: [0, 0, 0]).inverse
        mapUniforms.projectionMatrix = mapCamera.projectionMatrix// float4x4(projectionFov: 70, near: 0.001, far: 100, aspect: mapCamera.aspect, lhs: true)
            
        
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthStencilState)
        
        renderEncoder.setVertexBytes(
            &mapUniforms,
            length: MemoryLayout<Uniforms>.stride,
            index: BufferIndex.uniforms.rawValue
        )
        
//        let drawableWidth = Renderer.metalView.drawableSize.width.double / 4
//        let drawableHeight = Renderer.metalView.drawableSize.height.double / 4
        
//        renderEncoder.setViewport(
//            MTLViewport(originX: 0,//Renderer.metalView.drawableSize.width.double - drawableWidth,
//                        originY: 0,
//                        width: Renderer.metalView.drawableSize.width.double,// drawableWidth,
//                        height: Renderer.metalView.drawableSize.height.double,// drawableHeight,
//                        znear: 0.0001,
//                        zfar: 1)
//        )
        
        
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
    }
}

extension CGFloat {
    
    var double: Double {
        Double(self)
    }
}
