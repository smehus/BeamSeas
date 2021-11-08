//
//  WorldMapScaffolding.swift
//  BeamSeas
//
//  Created by Scott Mehus on 9/6/21.
//  Copyright © 2021 Scott Mehus. All rights reserved.
//

extension MapRotationHandler {
    func getRotation(player: Model, degRot: Float) -> float3 {
        // maybe i need to use the player forwardVector to figure out the forwards backwards vectors / rotation for scaffolding
        
        // One solution (maybe) is to have the terrain not move at all except with the scaffolding.
        // Don't rotate the scaffolding unless the player moves and only rotate / move forward by the forward vector?
        
        // Another solution is to scrap the scaffolding and figure out a way to sample just the texture? Or maybe say screw it to the world map and just use a 2d texture?
        
        // Another solution - just rotate the scaffolding & do an offscreen draw of the scaffolding to a color texture from the point of view of top down.
        // So the camera would be above the scaffolding & terrain pointing downards. Then sample that texture for the color & height of the terrain?
        
        let rotDiff = player.rotation.y - degRot
        var newRot = float3(0, rotDiff, 0)
        if player.moveStates.contains(.forward) {
            newRot.x = -0.005
        } else if player.moveStates.contains(.backwards) {
            newRot.x = 0.005
        }
        
        return newRot
    }
}

import MetalKit

/// Used to help create the vector for sampling world map texture cube
final class WorldMapScaffolding: Node, Texturable, RendererContianer {
    
    weak var renderer: Renderer!
    
    private let mesh: MDLMesh
    private let model: MTKMesh
    private let pipelineState: MTLRenderPipelineState
    private var texture: MTLTexture!
    private var mapUniforms = Uniforms()
    private var degRot: Float = 0
    private let samplerState: MTLSamplerState?
    
//    private lazy var mapCamera: Camera = {
////        let camera = Camera()
////        camera.near = 0.0001
////        camera.far = 1000
//
//        let camera = ThirdPersonCamera()
//        camera.far = 2000
//        camera.focus = self
//        camera.focusDistance = 150
//        camera.focusHeight = 100
//        return camera
//    }()
    
    init(extent: vector_float3, segments: vector_uint2) {
        let allocator = MTKMeshBufferAllocator(device: Renderer.device)
        mesh = MDLMesh(
            sphereWithExtent: extent,
            segments: segments,
            inwardNormals: false,
            geometryType: .triangles,
            allocator: allocator
        )
        
        do {
            model = try MTKMesh(mesh: mesh, device: Renderer.device)

            let constants = MTLFunctionConstantValues()
            var property = false
            constants.setConstantValue(&property, type: .bool, index: 0) // texture
            constants.setConstantValue(&property, type: .bool, index: 1) // normal texture
            constants.setConstantValue(&property, type: .bool, index: 2) // roughness texture
            constants.setConstantValue(&property, type: .bool, index: 3) // metal texture
            constants.setConstantValue(&property, type: .bool, index: 4) // AO Texture

            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.colorAttachments[0].pixelFormat = Renderer.metalView.colorPixelFormat
            pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
            pipelineDescriptor.vertexFunction = Renderer.library.makeFunction(name: "worldMap_vertex")
            pipelineDescriptor.fragmentFunction = Renderer.library.makeFunction(name: "worldMap_fragment")
            pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(mesh.vertexDescriptor)
            
            pipelineState = try Renderer.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            
        } catch { fatalError(error.localizedDescription) }
        
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerState = Renderer.device.makeSamplerState(descriptor: samplerDescriptor)
        
        super.init()
        
        boundingBox = mesh.boundingBox
        texture = worldMapTexture(options: nil)
        
        let rot: float4x4 = .identity()
        let initialRotation = simd_quatf(rot)
        quaternion = initialRotation
    }
    
    private lazy var depthStencilState: MTLDepthStencilState = {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .lessEqual
        descriptor.isDepthWriteEnabled = true
        return Renderer.device.makeDepthStencilState(descriptor: descriptor)!
    }()
}


extension WorldMapScaffolding: AspectRatioUpdateable {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
//        mapCamera.aspect = Float(size.width) / Float(size.height)
    }
}

extension WorldMapScaffolding: Renderable, MapRotationHandler {
    
    
    func update(
        deltaTime: Float,
        uniforms: inout Uniforms,
        fragmentUniforms: inout FragmentUniforms,
        camera: Camera,
        player: Model
    ) {
        // The players rotation will always be on the y axis
//        let rotMat = float4x4(rotation: getRotation(player: player, degRot: degRot))
//        let newRotQuat = simd_quatf(rotMat)
//        // Not rotating because the quat is zero?
//        quaternion = newRotQuat * quaternion
//
//        degRot = player.rotation.y
//
////        fragmentUniforms.scaffoldingModelMatrix = worldTransform
//
//        // CURRENT TASK - TRYING TO GET TEXTURE SAMPLING TO WORK
//        // WHILE THE TERRAIN IS A CHILD TO SCAFFOLDING AND WILL ROTATE WITH THE PARENT COORDINATE SPACE
        fragmentUniforms.scaffoldingPosition = float4(position, 1)
//
        
        
        guard renderer.playerRotation != nil else { return }
        
        let fwrdVec: float3 = {
            var value = player.forwardVector
            value.x = round(value.x * 1000) / 1000
            value.y = round(value.y * 1000) / 1000
            value.z = round(value.z * 1000) / 1000
            return value
        }()
        
        let normalMapTangent: float3 = {
            var value = renderer.playerRotation.tangent1
            value.x = round(value.x * 1000) / 1000
            value.y = round(value.y * 1000) / 1000
            value.z = round(value.z * 1000) / 1000
            return value
        }()
        
        let modelForwardVector: float3 = {
            var value = normalize(player.modelMatrix.inverse.columns.2.xyz)
            value.x = -value.x
            value.x = round(value.x * 1000) / 1000
            value.y = round(value.y * 1000) / 1000
            value.z = round(value.z * 1000) / 1000
            return value
        }()
        
        let worldForwardVector: float3 = {
            var value = normalize(player.worldTransform.inverse.columns.2.xyz)
            value.x = -value.x
            value.x = round(value.x * 1000) / 1000
            value.y = round(value.y * 1000) / 1000
            value.z = round(value.z * 1000) / 1000
            return value
        }()
        
        print("""
               ==================================================================
               forwardVector:       \(fwrdVec)
               normalMapTangent:    \(normalMapTangent)
               modelForwardVector:  \(modelForwardVector)
               worldForwardVector:  \(worldForwardVector)
               ==================================================================
               """)
        
        if player.moveStates.contains(.forward) {
            // worldForwardVector apperas to be correct
            // The other three are all the same. the vectors in local spaceg
            let vec = modelForwardVector * -0.003
            let rotMat = float4x4(rotation: vec)
            let quat = simd_quatf(rotMat)
            quaternion = quaternion * quat
        }
        
    }
    
    func draw(renderEncoder: MTLRenderCommandEncoder, uniforms: inout Uniforms, fragmentUniforms: inout FragmentUniforms) {
//        return
        defer {
            renderEncoder.popDebugGroup()
        }
        
        renderEncoder.pushDebugGroup("WorldMap Scaffolding")

        // Using the same camera as scene will mess up the rotation for some reason.
//        mapUniforms = uniforms
//        mapUniforms.modelMatrix = worldTransform
//        mapUniforms.viewMatrix = mapCamera.viewMatrix
//        mapUniforms.projectionMatrix = mapCamera.projectionMatrix
        
        uniforms.modelMatrix = float4x4(translation: position) * .identity() * float4x4(scaling: scale)//worldTransform
  
//        uniforms.modelMatrix = modelMatrix
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthStencilState)
        
        let mesh = model.submeshes.first!
        renderEncoder.setVertexBuffer(
            model.vertexBuffers.first!.buffer,
            offset: 0,
            index: BufferIndex.vertexBuffer.rawValue
        )
        
        renderEncoder.setVertexBytes(
            &uniforms,
            length: MemoryLayout<Uniforms>.stride,
            index: BufferIndex.uniforms.rawValue
        )
        
        renderEncoder.setFragmentTexture(
            texture,
            index: TextureIndex.color.rawValue
        )

        renderEncoder.setFragmentSamplerState(samplerState, index: 0)
        
        renderEncoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: mesh.indexCount,
            indexType: mesh.indexType,
            indexBuffer: mesh.indexBuffer.buffer,
            indexBufferOffset: mesh.indexBuffer.offset
        )
    }
}
