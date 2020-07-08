//
//  Extensions.swift
//  BeamSeas
//
//  Created by Scott Mehus on 6/17/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

import MetalKit

extension MDLVertexDescriptor {
    static var defaultVertexDescriptor: MDLVertexDescriptor = {
        let vertexDescriptor = MDLVertexDescriptor()

        var offset = 0
        // position attribute
        vertexDescriptor.attributes[Int(VertexAttribute.position.rawValue)]
            = MDLVertexAttribute(name: MDLVertexAttributePosition,
                                 format: .float3,
                                 offset: 0,
                                 bufferIndex: Int(BufferIndex.vertexBuffer.rawValue))
        offset += MemoryLayout<SIMD3<Float>>.stride

        // normal attribute
        vertexDescriptor.attributes[Int(VertexAttribute.normal.rawValue)] =
            MDLVertexAttribute(name: MDLVertexAttributeNormal,
                               format: .float3,
                               offset: offset,
                               bufferIndex: Int(BufferIndex.vertexBuffer.rawValue))
        offset += MemoryLayout<SIMD3<Float>>.stride

        // add the uv attribute here
        vertexDescriptor.attributes[Int(VertexAttribute.UV.rawValue)] =
            MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate,
                               format: .float2,
                               offset: offset,
                               bufferIndex: Int(BufferIndex.vertexBuffer.rawValue))
        offset += MemoryLayout<SIMD2<Float>>.stride

        vertexDescriptor.attributes[Int(VertexAttribute.tangent.rawValue)] =
            MDLVertexAttribute(name: MDLVertexAttributeTangent,
                               format: .float3,
                               offset: 0,
                               bufferIndex: 1)

        vertexDescriptor.attributes[Int(VertexAttribute.bitangent.rawValue)] =
            MDLVertexAttribute(name: MDLVertexAttributeBitangent,
                               format: .float3,
                               offset: 0,
                               bufferIndex: 2)

        // color attribute
        vertexDescriptor.attributes[Int(VertexAttribute.color.rawValue)] =
            MDLVertexAttribute(name: MDLVertexAttributeColor,
                               format: .float3,
                               offset: offset,
                               bufferIndex: Int(BufferIndex.vertexBuffer.rawValue))

        offset += MemoryLayout<SIMD3<Float>>.stride

        // joints attribute
//        vertexDescriptor.attributes[Int(Joints.rawValue)] =
//            MDLVertexAttribute(name: MDLVertexAttributeJointIndices,
//                               format: .uShort4,
//                               offset: offset,
//                               bufferIndex: Int(BufferIndexVertices.rawValue))
//        offset += MemoryLayout<ushort>.stride * 4
//
//        vertexDescriptor.attributes[Int(Weights.rawValue)] =
//            MDLVertexAttribute(name: MDLVertexAttributeJointWeights,
//                               format: .float4,
//                               offset: offset,
//                               bufferIndex: Int(BufferIndexVertices.rawValue))
//        offset += MemoryLayout<SIMD4<Float>>.stride

        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: offset)
        vertexDescriptor.layouts[1] =
            MDLVertexBufferLayout(stride: MemoryLayout<SIMD3<Float>>.stride)
        vertexDescriptor.layouts[2] =
            MDLVertexBufferLayout(stride: MemoryLayout<SIMD3<Float>>.stride)
        return vertexDescriptor

    }()
}
