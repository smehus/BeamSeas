//
//  Camera.swift
//  BeamSeas
//
//  Created by Scott Mehus on 6/17/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

import MetalKit

class Camera: Node {

    var fovDegrees: Float = 70
    var fovRadians: Float {
        return fovDegrees.degreesToRadians
    }

    var aspect: Float = 1
    var near: Float = 0.001
    var far: Float = 5000

//    var projectionMatrix: float4x4 {
//        return float4x4(perspectiveProjectionFov: fovRadians, aspectRatio: aspect, nearZ: near, farZ: far)
//    }
    
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
        // Should this be inversed??
        return (translateMatrix * rotateMatrix * scaleMatrix).inverse
    }

    func zoom(delta: Float) { }
    func rotate(delta: float2) { }
}

class ArcballCamera: Camera {

    var minDistance: Float = 0.001
    var maxDistance: Float = 1000
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
        let translateMatrix = float4x4(translation: [target.x, target.y, target.z - distance])
        let rotateMatrix = float4x4(rotationYXZ: [-rotation.x,
                                                  rotation.y,
                                                  0])
        let matrix = (rotateMatrix * translateMatrix).inverse
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



// My F'ed up one
class ThirdPersonScaffoldingCamera: Camera {

    var focus: Node!
    var focusDistance: Float = 3
    var focusHeight: Float = 3

    // the rotation is is all 0's because its never actually set

    override init() {
        super.init()
    }

    init(focus: Node) {
        self.focus = focus
        super.init()
    }

    override var viewMatrix: float4x4 {
        let terrainToScaffolding = focus.worldTransform.columns.3.xyz - focus.parent!.position
        let inversedTransform = terrainToScaffolding / 3
 
        position = focus.worldTransform.columns.3.xyz + inversedTransform
        
//        let x: Float = focus.worldTransform.columns.3.x * focus.forwardVector.x
//        let y: Float = focus.worldTransform.columns.3.y * focus.forwardVector.y
//        let z: Float = focus.worldTransform.columns.3.z * focus.forwardVector.z
//        position = float3(x, y, z)
        // Setting the center to 0, 0 ,0 prevents the camera from adjusting rotation.
        // This is good because if the camera moves with the player rotation
        // the world map will move around the screen
//        let worldRot = focus.parent!.rotation * focus.rotation
        let fwrdVector: SIMD3<Float> = [0, 1, 0]//normalize([sin(worldRot.y), 0, cos(worldRot.y)])
        return float4x4(eye: position, center: focus.worldTransform.columns.3.xyz, up: fwrdVector)
    }
}

class ThirdPersonCamera: Camera {

    var focusDistance: Float = 3
    var focusHeight: Float = 3
    
    private let focus: Node
    private let scaffolding: WorldMapScaffolding

    // the rotation is is all 0's because its never actually set

    init(focus: Node, scaffolding: WorldMapScaffolding) {
        self.focus = focus
        self.scaffolding = scaffolding
        super.init()
    }

    override var viewMatrix: float4x4 {
        position = focus.position - focusDistance * focus.forwardVector
        position.y = focusHeight
        
        return float4x4(eye: position, center: focus.worldTransform.columns.3.xyz, up: [0, 1, 0])
    }
}
//
class ClassicThirdPersonCamera: Camera {
  var focus: Node
  var focusDistance: Float = 3
  var focusHeight: Float = 1.2
  
  override var viewMatrix: float4x4 {
    position = focus.position - focusDistance * focus.forwardVector
    position.y = focusHeight
    rotation.y = focus.rotation.y
    return super.viewMatrix
  }
  
  init(focus: Node) {
    self.focus = focus
    super.init()
  }
}


class BaseThirdPersonCamera: Camera {

    var focus: Node!
    var focusDistance: Float = 3
    var focusHeight: Float = 3
    var shouldRotate = true

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
        return float4x4(eye: position, center: focus.parent!.position, up: [0, 1, 0])
//        return float4x4(lookAtLHEye: position, target: focus.position, up: [0, 1, 0])


//        setNonRotatingCamera()
//        return super.viewMatrix
    }

    private func setNonRotatingCamera() {
//        position = float3(focus.position.x, focus.position.y - focusDistance, focus.position.z - focusDistance)
//        position.y = 3
    }

    private func setRotatingCamera() {
        let playerPosition = focus.parent!.position
        position = playerPosition - focusDistance * focus.forwardVector
        position.y = playerPosition.y + focusHeight
        rotation.y = focus.rotation.y
    }
}
