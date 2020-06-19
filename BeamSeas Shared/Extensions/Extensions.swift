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
        vertexDescriptor.attributes[VertexAttribute.position.rawValue] = MDLVertexAttribute(name: MDLVertexAttributePosition,
                                                            format: .float3,
                                                            offset: 0,
                                                            bufferIndex: BufferIndex.vertexBuffer.rawValue)
        offset += MemoryLayout<float3>.stride

        vertexDescriptor.attributes[VertexAttribute.normal.rawValue] = MDLVertexAttribute(name: MDLVertexAttributeNormal,
                                                            format: .float3,
                                                            offset: offset,
                                                            bufferIndex: BufferIndex.vertexBuffer.rawValue)

        offset += MemoryLayout<float3>.stride

        vertexDescriptor.attributes[VertexAttribute.UV.rawValue] = MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate,
                                                                                      format: .float2,
                                                                                      offset: offset,
                                                                                      bufferIndex: BufferIndex.vertexBuffer.rawValue)
        offset += MemoryLayout<float2>.stride


        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: offset)
        return vertexDescriptor
    }()
}
