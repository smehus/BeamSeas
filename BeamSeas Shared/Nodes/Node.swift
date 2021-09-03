//
//  Node.swift
//  BeamSeas
//
//  Created by Scott Mehus on 6/17/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

import MetalKit

protocol Renderable {

    func update(
        deltaTime: Float,
        uniforms: inout Uniforms,
        fragmentUniforms: inout FragmentUniforms,
        camera: Camera,
        player: Model
    )

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

protocol Meshable {
    var mesh: MDLMesh { get }
    var size: SIMD3<Float> { get }
}

extension Meshable {
    var size: SIMD3<Float> {
        mesh.boundingBox.maxBounds - mesh.boundingBox.minBounds
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
    var parent: Node?
    var children: [Node] = []

    var modelMatrix: float4x4 {
        let translationMatrix = float4x4(translation: position)
        let rotationMatrix = float4x4(quaternion)
        let scaleMatrix = float4x4(scaling: scale)

        return translationMatrix * rotationMatrix * scaleMatrix
    }
    
    var worldTransform: float4x4 {
        if let parent = parent {
            return parent.worldTransform * modelMatrix
        }
        
        return modelMatrix
    }
    
    var forwardVector: SIMD3<Float> {
        return normalize([sin(rotation.y), 0, cos(rotation.y)])
    }
    
    var rightVector: SIMD3<Float> {
        return [forwardVector.z, forwardVector.y, -forwardVector.x]
    }
}

extension Node {
    final func add(child: Node) {
        children.append(child)
        child.parent = self
    }
    
    final func remove(child: Node) {
        child.children.forEach { grandChild in
            grandChild.parent = self
            children.append(grandChild)
        }
        
        child.children = []
        if let index = children.firstIndex(where: { $0 === child }) {
            children.remove(at: index)
            child.parent = nil
        }
    }
}
