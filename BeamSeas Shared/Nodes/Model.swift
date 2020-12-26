//
//  Model.swift
//  BeamSeas
//
//  Created by Scott Mehus on 6/17/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

import MetalKit
import Foundation
import simd

enum ModelMoveState {
    case forward
    case stopped
}

class Model: Node {
    
//    override var modelMatrix: float4x4 {
//        let translationMatrix = float4x4(translation: position)
//        let scaleMatrix = float4x4(scaling: scale)
//
//        return translationMatrix * rotationMatarix * scaleMatrix
//    }

    static var vertexDescriptor: MDLVertexDescriptor = .defaultVertexDescriptor
    
    weak var renderer: Renderer!

    let meshes: [Mesh]
    var tiling: UInt32 = 1
    let samplerState: MTLSamplerState?
    var heightBuffer: MTLBuffer
    var normalBuffer: MTLBuffer
    
    var moveState: ModelMoveState = .stopped
    var rotationMatarix: float4x4 = .identity()

    private let heightComputePipelineState: MTLComputePipelineState

    init(name: String, fragment: String) {
        guard let assetURL = Bundle.main.url(forResource: name, withExtension: "obj") else { fatalError("Model: \(name) not found")  }

        let allocator = MTKMeshBufferAllocator(device: Renderer.device)
        let asset = MDLAsset(
            url: assetURL,
            vertexDescriptor: .defaultVertexDescriptor,
            bufferAllocator: allocator
        )

        asset.loadTextures()

        //        let (mdlMeshes, mtkMeshes) = try! MTKMesh.newMeshes(asset: asset, device: Renderer.device)
        var mtkMeshes: [MTKMesh] = []
        let mdlMeshes = asset.childObjects(of: MDLMesh.self) as! [MDLMesh]
        _ = mdlMeshes.map { mdlMesh in
            mdlMesh.addTangentBasis(
                forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate,
                tangentAttributeNamed: MDLVertexAttributeTangent,
                bitangentAttributeNamed: MDLVertexAttributeBitangent
            )

            Model.vertexDescriptor = mdlMesh.vertexDescriptor
            mtkMeshes.append(try! MTKMesh(mesh: mdlMesh, device: Renderer.device))
        }

        meshes = zip(mdlMeshes, mtkMeshes).map { Mesh(mdlMesh: $0, mtkMesh: $1, fragment: fragment) }
        samplerState = Self.buildSamplerState()

        var startingHeight: Float = 0
        heightBuffer = Renderer.device.makeBuffer(bytes: &startingHeight, length: MemoryLayout<Float>.size, options: .storageModeShared)!

        var normalValue = 0
        normalBuffer = Renderer.device.makeBuffer(bytes: &normalValue, length: MemoryLayout<SIMD3<Float>>.size, options: .storageModeShared)!

        let heightKernel = Renderer.library.makeFunction(name: "compute_height")!
        heightComputePipelineState = try! Renderer.device.makeComputePipelineState(function: heightKernel)

        super.init()

        self.name = name
    }

    private static func buildSamplerState() -> MTLSamplerState {
        let descriptor = MTLSamplerDescriptor()
        descriptor.sAddressMode = .repeat
        descriptor.tAddressMode = .repeat
        descriptor.mipFilter = .linear
        descriptor.maxAnisotropy = 8
        return Renderer.device.makeSamplerState(descriptor: descriptor)!
    }
}

extension Model: Renderable {

    func update(with deltaTime: Float) {
        let heightValue = heightBuffer.contents().bindMemory(to: Float.self, capacity: 1).pointee
        assert(meshes.count == 1)
        let size = meshes.first!.mdlMesh.boundingBox.maxBounds - meshes.first!.mdlMesh.boundingBox.minBounds
        position.y = heightValue //+ (size.y * 0.3)

        // TODO: - Transfer all this over to gpu

        let (tangent0, tangent1, normalMapValue) = getRotationFromNormal()
        
        renderer.normalMapValue = (position, tangent0, tangent1, normalMapValue)
        
        var rotMat = float4x4.identity()
        rotMat.columns.0.xyz = tangent0
        rotMat.columns.1.xyz = normalMapValue
        rotMat.columns.2.xyz = tangent1
        
        let normalQuat = simd_quatf(rotMat)
        let slerp = simd_slerp(quaternion, normalQuat, 1.0)
        rotationMatarix = rotMat//float4x4(slerp)
  
        
//        let rot = float4x4(rotation: float3(normalMapValue.x, rotation.y, normalMapValue.z))
//        let quat = simd_quatf(rot)
//        rotationMatarix = float4x4(quat)
        
        
//        let center = normalMapValue
//        let lookAt = float4x4(eye: forwardVector, center: center, up: [0, 1, 0])
//        rotationMatarix = lookAt

//        var currentDegreeRotation = float2(rotation.x, rotation.z)
//
//        let delta = max(currentDegreeRotation,
//                        float2(normalMapValue.x.radiansToDegrees, normalMapValue.z.radiansToDegrees)) -
//                        min(currentDegreeRotation, float2(normalMapValue.x.radiansToDegrees, normalMapValue.z.radiansToDegrees))
//
//
//        currentDegreeRotation = float2(normalMapValue.x.radiansToDegrees, normalMapValue.z.radiansToDegrees)
//
//
//
//        rotation = float3(currentDegreeRotation.x.degreesToRadians, rotation.y, currentDegreeRotation.y.degreesToRadians)
    }
    
    func getRotationFromNormal() -> (tangent0: float3, tangent1: float3, normalMap: float3)  {
        var normalMapValue = normalBuffer.contents().bindMemory(to: SIMD3<Float>.self, capacity: 1).pointee

        // transform normal values from between 0 - 1 to -1 - 1
//        normalMapValue = normalize((normalMapValue * 2 - 1)) // y
        normalMapValue.x = normalMapValue.x * 2 - 1
        normalMapValue.y = normalMapValue.y * 2 - 1
        normalMapValue.z = normalMapValue.z * 2 - 1
        normalMapValue = normalize(normalMapValue)
        
        
  
        // need to add the right angle somehow?
        var crossVec = normalize(float3(0, 1, 0))
    
//        if abs(normalMapValue.x) <= abs(normalMapValue.y) {
//            crossVec.x = 1
//        } else if abs(normalMapValue.y) <= abs(normalMapValue.z) {
//            crossVec.y = 1
//        } else if abs(normalMapValue.z) <= abs(normalMapValue.x) {
//            crossVec.z = 1
//        } else {
//            assertionFailure()
//        }
        
        var tangent0 = normalize(cross(normalMapValue, crossVec)) // x
        let tangent1 = normalize(cross(normalMapValue, tangent0)) // z
        
        // google "normal to rotation matrix"
        
        return (tangent0, tangent1, normalMapValue)
    }

    func computeHeight(computeEncoder: MTLComputeCommandEncoder,
                       uniforms: inout Uniforms,
                       controlPoints: MTLBuffer,
                       terrainParams: inout TerrainParams) {
        
        var currentPosition = modelMatrix.columns.3.xyz

        computeEncoder.setComputePipelineState(heightComputePipelineState)
        computeEncoder.setBytes(&currentPosition, length: MemoryLayout<float3>.size, index: 0)
        computeEncoder.setBuffer(controlPoints, offset: 0, index: 1)
        computeEncoder.setBytes(&terrainParams, length: MemoryLayout<TerrainParams>.stride, index: 2)
        computeEncoder.setBuffer(heightBuffer, offset: 0, index: 3)
        computeEncoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 4)
        computeEncoder.setTexture(BasicFFT.heightDisplacementMap, index: 0)
        computeEncoder.setTexture(BasicFFT.normalMapTexture, index: 2)
        computeEncoder.setBuffer(normalBuffer, offset: 0, index: 5)
        computeEncoder.dispatchThreads(MTLSizeMake(1, 1, 1),
                                       threadsPerThreadgroup: MTLSizeMake(1, 1, 1))
    }

    func draw(renderEncoder: MTLRenderCommandEncoder, uniforms: inout Uniforms, fragmentUniforms: inout FragmentUniforms) {
        renderEncoder.pushDebugGroup("Model")

        fragmentUniforms.tiling = tiling
        uniforms.modelMatrix = modelMatrix
        uniforms.normalMatrix = modelMatrix.upperLeft

        renderEncoder.setFragmentSamplerState(samplerState, index: 0)
        renderEncoder.setVertexBytes(
            &uniforms,
            length: MemoryLayout<Uniforms>.stride,
            index: BufferIndex.uniforms.rawValue
        )

        renderEncoder.setFragmentBytes(
            &fragmentUniforms,
            length: MemoryLayout<FragmentUniforms>.stride,
            index: BufferIndex.fragmentUniforms.rawValue
        )

        renderEncoder.setVertexBytes(
            &Terrain.terrainParams,
            length: MemoryLayout<TerrainParams>.stride,
            index: BufferIndex.terrainParams.rawValue
        )
        
        renderEncoder.setVertexBytes(
            &rotationMatarix,
            length: MemoryLayout<float4x4>.size,
            index: 30
        )
        
        let rot = float4x4(rotation: forwardVector)
        let quat = simd_quatf(rot)
        var forwardMatrix = float4x4(quat)

        renderEncoder.setVertexBytes(
            &forwardMatrix,
            length: MemoryLayout<float4x4>.size,
            index: 29
        )
        
        renderEncoder.setVertexTexture(
            Terrain.primarySlopeMap,
            index: TextureIndex.primarySlope.rawValue
        )

        renderEncoder.setVertexTexture(
            Terrain.secondarySlopeMap,
            index: TextureIndex.secondarySlope.rawValue
        )

        renderEncoder.setVertexTexture(
            BasicFFT.normalMapTexture,
            index: TextureIndex.normal.rawValue
        )

        renderEncoder.setVertexTexture(BasicFFT.heightDisplacementMap, index: 20)

        renderEncoder.setTriangleFillMode(.fill)
        for mesh in meshes {

            for (index, vertexBuffer) in mesh.mtkMesh.vertexBuffers.enumerated() {
                renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: index)
            }

            for submesh in mesh.submeshes {
                let mtkMesh = submesh.mtkSubmesh

                renderEncoder.setRenderPipelineState(submesh.pipelineState)
                renderEncoder.setVertexTexture(BasicFFT.normalMapTexture, index: TextureIndex.normal.rawValue)
                renderEncoder.setFragmentTexture(submesh.textures.baseColor, index: TextureIndex.color.rawValue)
                renderEncoder.setFragmentTexture(submesh.textures.normal, index: TextureIndex.normal.rawValue)
                var material = submesh.material
                renderEncoder.setFragmentBytes(&material, length: MemoryLayout<Material>.stride, index: BufferIndex.materials.rawValue)

                renderEncoder.drawIndexedPrimitives(
                    type: .triangle,
                    indexCount: mtkMesh.indexCount,
                    indexType: mtkMesh.indexType,
                    indexBuffer: mtkMesh.indexBuffer.buffer,
                    indexBufferOffset: mtkMesh.indexBuffer.offset
                )
            }
        }
        
        renderEncoder.popDebugGroup()
    }
}


