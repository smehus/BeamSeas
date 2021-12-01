//
//  WorldMapScaffolding.swift
//  BeamSeas
//
//  Created by Scott Mehus on 9/6/21.
//  Copyright © 2021 Scott Mehus. All rights reserved.
//

extension MapRotationHandler where Self: WorldMapScaffolding {
    func getRotation(player: Model, degRot: Float) -> float3 {
        // We're using the difference here
        // And then multiplying it below...
        let rotDiff = player.rotation.y - degRot
        var newRot = float3(0, rotDiff, 0)
        if player.moveStates.contains(.forward) {
            newRot.x = 0.005
        } else if player.moveStates.contains(.backwards) {
            newRot.x = -0.005
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
    private var moveRot: Float = 0
    private let samplerState: MTLSamplerState?
    private var userActionStates: Set<Key> = []
    var shouldDo = true
    var player: Model!
    
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
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }
}

extension WorldMapScaffolding: Renderable, MapRotationHandler {
    
    func didUpdate(keys: Set<Key>) {
        userActionStates = keys
        
        // 1.57
//        let align = Float(90).degreesToRadians
        let align = Float(player.rotation.y - degRot)
        print(align)
        keys.forEach {
            switch $0 {
            case .b:
                quaternion = float3(0, align, 0).simd * quaternion
            case .n:
                quaternion = float3(Float(-10).degreesToRadians, 0, 0).simd * quaternion
            case .h:
                quaternion = float3(Float(10).degreesToRadians, 0, 0).simd * quaternion
            case .m:
                quaternion = float3(0, align, 0).simd * quaternion * float3(Float(-10).degreesToRadians, 0, 0).simd * float3(0, -align, 0).simd * quaternion
                
                degRot = player.rotation.y
            default: break
            }
        }

    }

    func update(
        deltaTime: Float,
        uniforms: inout Uniforms,
        fragmentUniforms: inout FragmentUniforms,
        camera: Camera,
        player: Model
    ) {
        self.player = player
        fragmentUniforms.scaffoldingPosition = float4(position, 1)

//        let delta = Float(5).degreesToRadians * 10
//        let align = float3(0, player.rotation.y - degRot, 0)
//        let delta = Float(player.rotation.y - degRot)
//        var move = float3(0, 0, 0)
//        if !userActionStates.isEmpty { userActionStates.forEach { print("*** states \($0.rawValue)") } }
//        userActionStates.forEach {
//            switch $0 {
//            case .forward:
//                move = float3(Float(5).degreesToRadians, 0, 0)
//
//                if shouldDo { // Getting closer but this doesn't work like above
//                    shouldDo = false
////                    quaternion = align.rotationMatrix.inverse.simd * move.simd * align.simd * quaternion
//                    quaternion = float3(0, -delta, 0).simd * move.simd * float3(0, delta, 0).simd * quaternion
//                }
//            case .backwards:
//                break
//            default: break
//            }
//        }
//
//        degRot = player.rotation.y
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
        
        uniforms.modelMatrix = worldTransform// float4x4(translation: position) * .identity() * float4x4(scaling: scale)
  
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

extension float3 {
    var simd: simd_quatf {
        simd_quatf(float4x4(rotation: self))
    }
    
    var rotationMatrix: float4x4 {
        float4x4(rotation: self)
    }
}

extension float4x4 {
    var simd: simd_quatf {
        simd_quatf(self)
    }
}
