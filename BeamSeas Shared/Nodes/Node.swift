//
//  Node.swift
//  BeamSeas
//
//  Created by Scott Mehus on 6/17/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

import MetalKit

protocol Renderable {
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
}

class Node {
    var name = "untitled"
    var position: float3 = [0, 0, 0]
    var rotation: float3 = [0, 0, 0]
    var scale: float3 = [1, 1, 1]

    var modelMatrix: float4x4 {
        let translationMatrix = float4x4(translation: position)
        let rotationMatrix = float4x4(rotation: rotation)
        let scaleMatrix = float4x4(scaling: scale)

        return translationMatrix * rotationMatrix * scaleMatrix
    }
}
