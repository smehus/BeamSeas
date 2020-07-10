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
    var far: Float = 500

    var projectionMatrix: float4x4 {
        return float4x4(perspectiveProjectionFov: fovRadians, aspectRatio: aspect, nearZ: near, farZ: far)
//        return float4x4(projectionFov: fovRadians, near: near, far: far, aspect: aspect)
    }

    var viewMatrix: float4x4 {
        let translateMatrix = float4x4(translationBy: position)
        let rotateMatrix = float4x4(rotation: rotation)//float4x4(rotationAbout: [1, 0, 0], by: rotation.x) * float4x4(rotationAbout: [0, 1, 0], by: rotation.y) * float4x4(rotationAbout: [0, 0, 1], by: rotation.z)
        let scaleMatrix = matrix_identity_float4x4

        // move camera to the right means everything else in world should move left
        return (translateMatrix * rotateMatrix * scaleMatrix).inverse
    }

    func zoom(delta: Float) {
        position.z -= delta
    }
    func rotate(delta: float2) {
        let sensitivity: Float = 0.005
        let y = rotation.y + delta.x * sensitivity
        var x = rotation.x + delta.y * sensitivity
        x = max(-Float.pi/2, min((x), Float.pi/2))
        rotation = [x, y, 0]
    }
}

class ThirdPersonCamera: Camera {

    var focus: Node!
    var focusDistance: Float = 3
    var focusHeight: Float = 10
    var yRotation: Float = 90

    // the rotation is is all 0's because its never actually set

    override init() {
        super.init()
    }

    init(focus: Node) {
        self.focus = focus
        super.init()
    }

    override var viewMatrix: float4x4 {
        setRotatingCamera()
        return float4x4(lookAtRHEye: position, target: focus.position, up: [0, 1, 0]) * float4x4(rotationAbout: [0, 1, 0], by: Float(yRotation).radiansToDegrees)
//        return float4x4(eye: position, center: focus.position, up: [0, 1, 0])

//        setNonRotatingCamera()
//        return super.viewMatrix
    }

    private func setNonRotatingCamera() {
        position = float3(focus.position.x, focus.position.y - focusDistance, focus.position.z - focusDistance)
        position.y = 3
    }

    private func setRotatingCamera() {
        position = focus.position - focusDistance * focus.forwardVector
        position.y = focus.position.y + focusHeight
        rotation.y = focus.rotation.y
    }

    override func rotate(delta: float2) {
        let sensitivity: Float = 0.001
        let y = rotation.y + delta.x * sensitivity
        var x = rotation.x + delta.y * sensitivity
        x = max(-Float.pi/2, min((x), Float.pi/2))
        print("*** x \(x)  *** y \(y)")
        yRotation += y
//        rotation = [0, Float(y).radiansToDegrees, 0]
    }

    override func zoom(delta: Float) {
        let sensitivity: Float = 0.05
        focusDistance -= delta * sensitivity
//        if focusHeight > 0 {
//            focusHeight -= delta * sensitivity
//        }
    }
}

class ArcballCamera: Camera {

    var minDistance: Float = 0.5
    var maxDistance: Float = 10
    var target: float3 = [0, 0, 0] {
        didSet {
            _viewMatrix = updateViewMatrix()
        }
    }

    var distance: Float = 0 {
        didSet {
            _viewMatrix = updateViewMatrix()
        }
    }

    override var rotation: float3 {
        didSet {
            _viewMatrix = updateViewMatrix()
        }
    }

    override var viewMatrix: float4x4 {
        return _viewMatrix
    }
    private var _viewMatrix = float4x4.identity()

    override init() {
        super.init()
        _viewMatrix = updateViewMatrix()
    }

    private func updateViewMatrix() -> float4x4 {
        let translateMatrix = float4x4(translation: [target.x, target.y + 3, target.z - distance])
        let rotateMatrix = float4x4(rotationYXZ: [-rotation.x,
                                                  rotation.y,
                                                  0])
        let matrix = (rotateMatrix * translateMatrix)
        position = rotateMatrix.upperLeft * -matrix.columns.3.xyz
        return matrix
    }

    override func zoom(delta: Float) {
        let sensitivity: Float = 0.05
        distance -= delta * sensitivity
        _viewMatrix = updateViewMatrix()
    }

    override func rotate(delta: float2) {
        let sensitivity: Float = 0.005
        let y = rotation.y + delta.x * sensitivity
        var x = rotation.x + delta.y * sensitivity
        x = max(-Float.pi/2, min((x), Float.pi/2))
        rotation = [x, y, 0]
        _viewMatrix = updateViewMatrix()
    }
}
