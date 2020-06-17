//
//  Camera.swift
//  BeamSeas
//
//  Created by Scott Mehus on 6/17/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

import Foundation

class Camera: Node {

    var fovDegrees: Float = 70
    var fovRadians: Float {
        return fovDegrees.degreesToRadians
    }

    var aspect: Float = 1
    var near: Float = 0.001
    var far: Float = 100

    var projectionMatrix: float4x4 {
        return float4x4(
            projectionFov: fovRadians,
            near: near,
            far: far,
            aspect: aspect
        )
    }

    var viewMatrix: float4x4 {
        let translateMatrix = float4x4(translation: position)
        let rotateMatrix = float4x4(rotation: rotation)
        let scaleMatrix = float4x4(scaling: scale)

        // move camera to the right means everything else in world should move left
        return (translateMatrix * rotateMatrix * scaleMatrix).inverse
    }

    func zoom(delta: Float) { }
    func rotate(delta: float2) { }
}
