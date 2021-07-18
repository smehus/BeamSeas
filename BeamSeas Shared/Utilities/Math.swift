//
//  Math.swift
//  BeamSeas
//
//  Created by Scott Mehus on 6/15/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

import Foundation

typealias float2 = SIMD2<Float>
typealias float3 = SIMD3<Float>
typealias float4 = SIMD4<Float>

let π = Float.pi

extension Float {
    var radiansToDegrees: Float {
        (self / π) * 180
    }
    var degreesToRadians: Float {
        (self / 180) * π
    }
}

//infix operator |=
//func |=(lhs: Float, rhs: Float, max: Float) -> Float {
//
//
//    return 0
//}


// MARK:- float4
extension float4x4 {
    // MARK:- Translate
    init(translation: float3) {
        let matrix = float4x4(
            [            1,             0,             0, 0],
            [            0,             1,             0, 0],
            [            0,             0,             1, 0],
            [translation.x, translation.y, translation.z, 1]
        )
        self = matrix
    }

    // MARK:- Scale
    init(scaling: float3) {
        let matrix = float4x4(
            [scaling.x,         0,         0, 0],
            [        0, scaling.y,         0, 0],
            [        0,         0, scaling.z, 0],
            [        0,         0,         0, 1]
        )
        self = matrix
    }

    init(scaling: Float) {
        self = matrix_identity_float4x4
        columns.3.w = 1 / scaling
    }

    // MARK:- Rotate
    init(rotationX angle: Float) {
        let matrix = float4x4(
            [1,           0,          0, 0],
            [0,  cos(angle), sin(angle), 0],
            [0, -sin(angle), cos(angle), 0],
            [0,           0,          0, 1]
        )
        self = matrix
    }

    init(rotationY angle: Float) {
        let matrix = float4x4(
            [cos(angle), 0, -sin(angle), 0],
            [         0, 1,           0, 0],
            [sin(angle), 0,  cos(angle), 0],
            [         0, 0,           0, 1]
        )
        self = matrix
    }

    init(rotationZ angle: Float) {
        let matrix = float4x4(
            [ cos(angle), sin(angle), 0, 0],
            [-sin(angle), cos(angle), 0, 0],
            [          0,          0, 1, 0],
            [          0,          0, 0, 1]
        )
        self = matrix
    }

    init(rotation angle: float3) {
        let rotationX = float4x4(rotationX: angle.x)
        let rotationY = float4x4(rotationY: angle.y)
        let rotationZ = float4x4(rotationZ: angle.z)
        self = rotationX * rotationY * rotationZ
    }

    init(rotationYXZ angle: float3) {
        let rotationX = float4x4(rotationX: angle.x)
        let rotationY = float4x4(rotationY: angle.y)
        let rotationZ = float4x4(rotationZ: angle.z)
        self = rotationY * rotationX * rotationZ
    }

    // MARK:- Identity
    static func identity() -> float4x4 {
        matrix_identity_float4x4
    }

    // MARK:- Upper left 3x3
    var upperLeft: float3x3 {
        let x = columns.0.xyz
        let y = columns.1.xyz
        let z = columns.2.xyz
        return float3x3(columns: (x, y, z))
    }

    
    /// Left Hand Projection (correct)
    init(perspectiveProjectionFov fovRadians: Float, aspectRatio aspect: Float, nearZ: Float, farZ: Float) {
        let yScale = 1 / tan(fovRadians * 0.5)
        let xScale = yScale / aspect
        let zRange = farZ - nearZ
        let zScale = (farZ + nearZ) / zRange
        let wzScale = -2 * farZ * nearZ / zRange

        let xx = xScale
        let yy = yScale
        let zz = zScale
        let zw = Float(1)
        let wz = wzScale

        self.init(float4(xx,  0,  0,  0),
                  float4( 0, yy,  0,  0),
                  float4( 0,  0, zz, zw),
                  float4( 0,  0, wz,  1))
    }
    
    
    /// Projection - Configurable
    init(projectionFov fov: Float, near: Float, far: Float, aspect: Float, lhs: Bool = true) {
      let y = 1 / tan(fov * 0.5)
      let x = y / aspect
      let z = lhs ? far / (far - near) : far / (near - far)
      let X = float4( x,  0,  0,  0)
      let Y = float4( 0,  y,  0,  0)
      let Z = lhs ? float4( 0,  0,  z, 1) : float4( 0,  0,  z, -1)
      let W = lhs ? float4( 0,  0,  z * -near,  0) : float4( 0,  0,  z * near,  0)
      self.init()
      columns = (X, Y, Z, W)
    }

    // left-handed LookAt
    init(eye: float3, center: float3, up: float3) {
        let z = normalize(center-eye)
        let x = normalize(cross(up, z))
        let y = cross(z, x)

        let X = float4(x.x, y.x, z.x, 0)
        let Y = float4(x.y, y.y, z.y, 0)
        let Z = float4(x.z, y.z, z.z, 0)
        let W = float4(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)

        self.init()
        columns = (X, Y, Z, W)
    }
    
//    init(lookAtLHEye eye: vector_float3, target: vector_float3, up: vector_float3) {
//
//        // LH: Target - Camera
//        // RH: Camera - Target
//
//        let z: vector_float3  = simd_normalize(target - eye);
//        let x: vector_float3  = simd_normalize(simd_cross(up, z));
//        let y: vector_float3  = simd_cross(z, x);
//        let t: vector_float3 = vector_float3(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye));
//
//
//        self.init(array: [x.x, y.x, z.x, 0,
//                          x.y, y.y, z.y, 0,
//                          x.z, y.z, z.z, 0,
//                          t.x, t.y, t.z, 1])
//    }

    // MARK:- Orthographic matrix
    init(orthoLeft left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) {
        let X = float4(2 / (right - left), 0, 0, 0)
        let Y = float4(0, 2 / (top - bottom), 0, 0)
        let Z = float4(0, 0, 1 / (far - near), 0)
        let W = float4((left + right) / (left - right),
                       (top + bottom) / (bottom - top),
                       near / (near - far),
                       1)
        self.init()
        columns = (X, Y, Z, W)
    }

    // convert double4x4 to float4x4
    init(_ m: matrix_double4x4) {
        self.init()
        let matrix: float4x4 = float4x4(float4(m.columns.0),
                                        float4(m.columns.1),
                                        float4(m.columns.2),
                                        float4(m.columns.3))
        self = matrix
    }
}

// MARK:- float3x3
extension float3x3 {
    init(normalFrom4x4 matrix: float4x4) {
        self.init()
        columns = matrix.upperLeft.inverse.transpose.columns
    }
}

// MARK:- float4
extension float4 {
    var xyz: float3 {
        get {
            float3(x, y, z)
        }
        set {
            x = newValue.x
            y = newValue.y
            z = newValue.z
        }
    }

    // convert from double4
    init(_ d: SIMD4<Double>) {
        self.init()
        self = [Float(d.x), Float(d.y), Float(d.z), Float(d.w)]
    }
}



// **** Generated Functions ***** \\


// Generic matrix math utility functions
func matrix4x4_rotation(radians: Float, axis: SIMD3<Float>) -> matrix_float4x4 {
    let unitAxis = normalize(axis)
    let ct = cosf(radians)
    let st = sinf(radians)
    let ci = 1 - ct
    let x = unitAxis.x, y = unitAxis.y, z = unitAxis.z
    return matrix_float4x4.init(columns:(vector_float4(    ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
                                         vector_float4(x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0),
                                         vector_float4(x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0),
                                         vector_float4(                  0,                   0,                   0, 1)))
}

func matrix4x4_translation(_ translationX: Float, _ translationY: Float, _ translationZ: Float) -> matrix_float4x4 {
    return matrix_float4x4.init(columns:(vector_float4(1, 0, 0, 0),
                                         vector_float4(0, 1, 0, 0),
                                         vector_float4(0, 0, 1, 0),
                                         vector_float4(translationX, translationY, translationZ, 1)))
}

func matrix_perspective_right_hand(fovyRadians fovy: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
    let ys = 1 / tanf(fovy * 0.5)
    let xs = ys / aspectRatio
    let zs = farZ / (nearZ - farZ)
    return matrix_float4x4.init(columns:(vector_float4(xs,  0, 0,   0),
                                         vector_float4( 0, ys, 0,   0),
                                         vector_float4( 0,  0, zs, -1),
                                         vector_float4( 0,  0, zs * nearZ, 0)))
}

func radians_from_degrees(_ degrees: Float) -> Float {
    return (degrees / 180) * .pi
}
