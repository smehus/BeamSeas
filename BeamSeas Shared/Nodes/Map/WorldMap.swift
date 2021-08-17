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
    private var lookAtMatrix: float4x4 = .identity()
    private var forwardRotation: Float = 0
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
    
    override var modelMatrix: float4x4 {
        let translationMatrix = float4x4(translation: position)
        let rotationMatrix = float4x4(rotation: rotation)
        let scaleMatrix = float4x4(scaling: scale)

        return translationMatrix * lookAtMatrix * scaleMatrix
    }
    
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
        rotation.x = Float(-10).degreesToRadians
        lookAtMatrix *= float4x4(simd_quatf(float4x4(rotation: rotation)))
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
//        let fps = (1.float / Renderer.metalView.preferredFramesPerSecond.float)
//
//        let rules = [
//            leftRule(),
//            rightRule(),
//            forwardRule(),
//            backwardRule()
//        ]
//
//        for rule in rules {
//            guard let ruleRotation = rule(player, fps) else { continue }
//
//
//            rotation += ruleRotation
//        }
  
//        print("""
//            X: \(180 * player.forwardVector.x)
//            """)
//        return normalize([sin(rotation.y), 0, cos(rotation.y)])
//        self.rotation = SIMD3<Float>(
//            asin(player.forwardVector.x),
//            0,
//            acos(player.forwardVector.z)
//        )
//        self.rotation.z = (self.forwardVector)
        
//        // Look up forwardVector to rotation....
//        self.rotation = SIMD3<Float>(
//            (360 * player.forwardVector.z).degreesToRadians,
//            (360 * player.forwardVector.x).degreesToRadians,
//            (360 * player.forwardVector.y).degreesToRadians
//        )
        
//        rotation.z = player.rotation.y

        
//        if player.moveStates.contains(.forward) {
//            rotation.x -= 0.01
//        }
        
        // Inverse the current rotation?
        // Then apply map rotation & then re-apply rotation?
//
//        let currentRotationMat = float4x4(quaternion)
//        let inversedCurrentMat = currentRotationMat.inverse
//
//        let initiatedQuaternion = simd_quatf(float4x4(rotation:float3(forwardRotation, 0, player.rotation.y)))
//        let initiatedRotation = float4x4(initiatedQuaternion)

//        lookAtMatrix = currentRotationMat * initiatedRotation * inversedCurrentMat
        
//        lookAtMatrix = float4x4(eye: player.forwardVector, center: position, up: float3(0, 1, 0))
        
        
        // ******
        // Maybe don't try to rotate the actual sphere.
        // Rotate the camera around the sphere.....
        
        
//        let current = float4x4(rotation: rotation)

//        let yRot = float4x4(rotation:float3(forwardRotation, -sin(Float(degRot).degreesToRadians), cos(Float(degRot).degreesToRadians)))
//        lookAtMatrix =  current * yRot * current.inverse
        
        
        // have to use quaternions for rotation around arbitruary axes
        

        let current = float4x4(simd_quatf(float4x4(rotation: rotation)))
        let rotateLeftRight = float4x4(simd_quatf(float4x4(rotation: float3(
                                                            Float(0).degreesToRadians,
                                                            Float(0).degreesToRadians,
                                                            player.rotation.y))))
        
        var moveRot: float4x4 = .identity()
        if player.moveStates.contains(.forward) {
            forwardRotation += 0.001
            

            moveRot = float4x4(simd_quatf(float4x4(rotation: float3(
                                                            Float(-forwardRotation).degreesToRadians,
                                                            Float(0).degreesToRadians,
                                                            Float(0).degreesToRadians))))
            
            
        }
        
        // idk..
        lookAtMatrix = current * rotateLeftRight * (lookAtMatrix * current.inverse)
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
