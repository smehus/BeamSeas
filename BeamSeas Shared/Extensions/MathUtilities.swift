import simd

extension float4 {
    var xyz: float3 {
        return float3(x, y, z)
    }
}

extension float4x4 {

    init(array: [Float]) {
        guard array.count == 16 else {
            fatalError("presented array has \(array.count) elements - a float4x4 needs 16 elements")
        }

        self = matrix_identity_float4x4
        columns = (
            SIMD4<Float>( array[0],  array[1],  array[2],  array[3]),
            SIMD4<Float>( array[4],  array[5],  array[6],  array[7]),
            SIMD4<Float>( array[8],  array[9],  array[10], array[11]),
            SIMD4<Float>( array[12],  array[13],  array[14],  array[15])
        )
    }

    init(scaleBy s: Float) {
        self.init(float4(s, 0, 0, 0),
                  float4(0, s, 0, 0),
                  float4(0, 0, s, 0),
                  float4(0, 0, 0, 1))
    }

    init(lookAtRHEye eye: vector_float3, target: vector_float3, up: vector_float3) {

        // LH: Target - Camera
        // RH: Camera - Target

        let z: vector_float3  = simd_normalize(eye - target);
        let x: vector_float3  = simd_normalize(simd_cross(up, z));
        let y: vector_float3  = simd_cross(z, x);
        let t: vector_float3 = vector_float3(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye));


        self.init(array: [x.x, y.x, z.x, 0,
                          x.y, y.y, z.y, 0,
                          x.z, y.z, z.z, 0,
                          t.x, t.y, t.z, 1])
    }

    init(rotationAbout axis: float3, by angleRadians: Float) {
        let a = normalize(axis)
        let x = a.x, y = a.y, z = a.z
        let c = cosf(angleRadians)
        let s = sinf(angleRadians)
        let t = 1 - c
        self.init(float4( t * x * x + c,     t * x * y + z * s, t * x * z - y * s, 0),
                  float4( t * x * y - z * s, t * y * y + c,     t * y * z + x * s, 0),
                  float4( t * x * z + y * s, t * y * z - x * s,     t * z * z + c, 0),
                  float4(                 0,                 0,                 0, 1))
    }
    
    init(translationBy t: float3) {
        self.init(float4(   1,    0,    0, 0),
                  float4(   0,    1,    0, 0),
                  float4(   0,    0,    1, 0),
                  float4(t[0], t[1], t[2], 1))
    }
    
    init(perspectiveProjectionFov fovRadians: Float, aspectRatio aspect: Float, nearZ: Float, farZ: Float) {
        let yScale = 1 / tan(fovRadians * 0.5)
        let xScale = yScale / aspect
        let zRange = farZ - nearZ
        let zScale = -(farZ + nearZ) / zRange
        let wzScale = -2 * farZ * nearZ / zRange
        
        let xx = xScale
        let yy = yScale
        let zz = zScale
        let zw = Float(-1)
        let wz = wzScale
        
        self.init(float4(xx,  0,  0,  0),
                  float4( 0, yy,  0,  0),
                  float4( 0,  0, zz, zw),
                  float4( 0,  0, wz,  1))
    }
    
    var normalMatrix: float3x3 {
        let upperLeft = float3x3(self[0].xyz, self[1].xyz, self[2].xyz)
        return upperLeft.transpose.inverse
    }
}
