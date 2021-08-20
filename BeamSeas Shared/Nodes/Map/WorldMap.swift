//
//  WorldMap.swift
//  BeamSeas
//
//  Created by Scott Mehus on 6/28/21.
//  Copyright © 2021 Scott Mehus. All rights reserved.
//

import Foundation
import MetalKit

final class WorldMap: Node, Meshable, Texturable, DepthStencilStateBuilder {
    
    private(set) var mesh: MDLMesh
    private let model: MTKMesh
    private let pipelineState: MTLRenderPipelineState
    private var mapUniforms = Uniforms()
    private var texture: MTLTexture?
    private let samplerState: MTLSamplerState?
    private var degRot: Float = 0
    var first = true
    
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
        descriptor.depthCompareFunction = .less
        descriptor.isDepthWriteEnabled = true
        return Renderer.device.makeDepthStencilState(descriptor: descriptor)!
    }()
    
//    override var modelMatrix: float4x4 {
//        let translationMatrix = float4x4(translation: position)
//        let rotationMatrix = float4x4(rotation: rotation)
//        let scaleMatrix = float4x4(scaling: scale)
//
//        return translationMatrix * lookAtMatrix * scaleMatrix
//    }
    
    init(vertexName: String, fragmentName: String) {
        
        let allocator = MTKMeshBufferAllocator(device: Renderer.device)
        mesh = MDLMesh(
            sphereWithExtent: [15, 15, 15],
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
        
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerState = Renderer.device.makeSamplerState(descriptor: samplerDescriptor)
        
        super.init()
        
        texture = loadSkyboxTexture(names: ["posx.jpg",
                                            "negx.jpg",
                                            "posy.jpg",
                                            "negy.jpg",
                                            "posz.jpg",
                                            "negz.jpg"])

        let rot = float4x4(rotation: float3(Float(90).degreesToRadians, 0, 0))
        let initialRotation = simd_quatf(rot)
        quaternion = initialRotation
        
    }
}

extension WorldMap: AspectRatioUpdateable {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        mapCamera.aspect = Float(size.width) / Float(size.height)
    }
}

extension WorldMap: Renderable, MoveStateNavigatable {
    
    func update(
        deltaTime: Float,
        uniforms: Uniforms,
        fragmentUniforms: FragmentUniforms,
        camera: Camera,
        player: Model
    ) {
        // The players rotation will always be on the y axis
        let rotDiff = player.rotation.y - degRot
        var newRot = float3(0, 0, rotDiff)
        if player.moveStates.contains(.forward) {
            newRot.x = -0.007
        }
        
        let rotMat = float4x4(rotation: newRot)
        let newRotQuat = simd_quatf(rotMat)
        quaternion = newRotQuat * quaternion

        degRot = player.rotation.y
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
        mapUniforms.viewMatrix = mapCamera.viewMatrix
        mapUniforms.projectionMatrix = mapCamera.projectionMatrix// float4x4(projectionFov: 70, near: 0.001, far: 100, aspect: mapCamera.aspect, lhs: true)
            
        
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthStencilState)
        
        renderEncoder.setVertexBytes(
            &mapUniforms,
            length: MemoryLayout<Uniforms>.stride,
            index: BufferIndex.uniforms.rawValue
        )
        
        let drawableWidth = Renderer.metalView.drawableSize.width.double / 4
        let drawableHeight = Renderer.metalView.drawableSize.height.double / 4
        
        renderEncoder.setViewport(
            MTLViewport(originX: Renderer.metalView.drawableSize.width.double - drawableWidth,
                        originY: 0,
                        width: drawableWidth,
                        height: drawableHeight,
                        znear: 0.0001,
                        zfar: 1)
        )
        
        
        let mesh = model.submeshes.first!
        renderEncoder.setVertexBuffer(
            model.vertexBuffers.first!.buffer,
            offset: 0,
            index: BufferIndex.vertexBuffer.rawValue
        )
        
        renderEncoder.setFragmentTexture(
            texture,
            index: TextureIndex.color.rawValue
        )
        
        renderEncoder.setFragmentSamplerState(samplerState, index: 0)
        
//        renderEncoder.setTriangleFillMode(.lines)
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
