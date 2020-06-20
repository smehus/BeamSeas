//
//  Submesh.swift
//  BeamSeas
//
//  Created by Scott Mehus on 6/17/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

import MetalKit


class Submesh {

    struct Textures {
        let baseColor: MTLTexture?
        let normal: MTLTexture?
    }

    let textures: Textures
    var mtkSubmesh: MTKSubmesh
    let pipelineState: MTLRenderPipelineState
    
    init(mdlSubmesh: MDLSubmesh, mtkSubmesh: MTKSubmesh) {
        self.mtkSubmesh = mtkSubmesh
        textures = Textures(material: mdlSubmesh.material)
        pipelineState = Self.buildPipelineState()
    }

    private static func buildPipelineState() -> MTLRenderPipelineState {
        let library = Renderer.library
        let vertexFunction = library?.makeFunction(name: "vertex_main")
        let fragmentFunction = library?.makeFunction(name: "fragment_main")

        var pipelineState: MTLRenderPipelineState
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(Model.vertexDescriptor)
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float

        do {
            pipelineState = try Renderer.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch let error {
            fatalError(error.localizedDescription)
        }
        return pipelineState
    }
}

extension Submesh: Texturable {}

private extension Submesh.Textures {
    init(material: MDLMaterial?) {
        func property(with semantic: MDLMaterialSemantic) -> MTLTexture? {
            guard
                let property = material?.property(with: semantic),
                property.type == .string,
                let fileName = property.stringValue
            else { return nil }

            return Submesh.loadTexture(imageName: fileName)
        }

        baseColor = property(with: .baseColor)
        normal = property(with: .tangentSpaceNormal)
    }
}
