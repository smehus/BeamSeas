//
//  Node.swift
//  BeamSeas
//
//  Created by Scott Mehus on 6/17/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

import MetalKit

protocol Renderable {

    func update(with deltaTime: Float, uniforms: Uniforms, fragmentUniforms: FragmentUniforms, camera: Camera)

    func compute(
        computeEncoder: MTLComputeCommandEncoder,
        uniforms: inout Uniforms,
        fragmentUniforms: inout FragmentUniforms
    )

    func computeHeight(
        computeEncoder: MTLComputeCommandEncoder,
        uniforms: inout Uniforms,
        controlPoints: MTLBuffer,
        terrainParams: inout TerrainParams
    )

    func draw(
        renderEncoder: MTLRenderCommandEncoder,
        uniforms: inout Uniforms,
        fragmentUniforms: inout FragmentUniforms
    )

    func generateTerrainNormals(
        computeEncoder: MTLComputeCommandEncoder,
        uniforms: inout Uniforms
    )
}

extension Renderable {
    func compute(
        computeEncoder: MTLComputeCommandEncoder,
        uniforms: inout Uniforms,
        fragmentUniforms: inout FragmentUniforms
    ) {
        // Override
    }

    func computeHeight(
        computeEncoder: MTLComputeCommandEncoder,
        uniforms: inout Uniforms,
        controlPoints: MTLBuffer,
        terrainParams: inout TerrainParams
    ) {
        // Override
    }

    func generateTerrainNormals(
        computeEncoder: MTLComputeCommandEncoder,
        uniforms: inout Uniforms
    ) {
        // Override
    }
}

class Node {
    var name = "untitled"
    var position: float3 = [0, 0, 0]
    var rotation: float3 = [0, 0, 0] {
        didSet {
            let rotationMatrix = float4x4(rotation: rotation)
            quaternion = simd_quatf(rotationMatrix)
        }
    }
    var scale: float3 = [1, 1, 1]
    
    var quaternion = simd_quatf()

    var modelMatrix: float4x4 {
        let translationMatrix = float4x4(translation: position)
        let rotationMatrix = float4x4(quaternion)
        let scaleMatrix = float4x4(scaling: scale)

        return translationMatrix * rotationMatrix * scaleMatrix
    }
    
    var forwardVector: SIMD3<Float> {
        return normalize([sin(rotation.y), 0, cos(rotation.y)])
    }
    
    var rightVector: SIMD3<Float> {
        return [forwardVector.z, forwardVector.y, -forwardVector.x]
    }
}
