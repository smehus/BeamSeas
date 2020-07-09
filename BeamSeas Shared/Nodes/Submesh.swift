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
    let material: Material
    
    init(mdlSubmesh: MDLSubmesh, mtkSubmesh: MTKSubmesh, fragmentName: String) {
        self.mtkSubmesh = mtkSubmesh
        textures = Textures(material: mdlSubmesh.material)
        material = Material(material: mdlSubmesh.material)
        pipelineState = Self.buildPipelineState(textures: textures, fragmentName: fragmentName)
    }

    private static func buildPipelineState(textures: Textures, fragmentName: String) -> MTLRenderPipelineState {
        let library = Renderer.library!

        let functionConstants = Self.makeFunctionConstants(textures: textures)
        let vertexFunction = library.makeFunction(name: "vertex_main")
        let fragmentFunction = try! library.makeFunction(name: fragmentName, constantValues: functionConstants)

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

    private static func makeFunctionConstants(textures: Textures) -> MTLFunctionConstantValues {
        let constants = MTLFunctionConstantValues()
        var property = textures.baseColor != nil
        constants.setConstantValue(&property, type: .bool, index: 0)

        property = textures.normal != nil
        constants.setConstantValue(&property, type: .bool, index: 1)

        return constants
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
            else {
                if let property = material?.property(with: semantic),
                    property.type == .texture,
                    let mdlTexture = property.textureSamplerValue?.texture,
                    let texture = try? Submesh.loadTexture(texture: mdlTexture){
                    return texture
                }

                return nil
            }

            return Submesh.loadTexture(imageName: fileName)
        }

        baseColor = property(with: .baseColor)
        normal = property(with: .tangentSpaceNormal)
    }
}

private extension Material {
    init(material: MDLMaterial?) {
        self.init()

        if let baseColor = material?.property(with: .baseColor), baseColor.type == .float3 {
            self.baseColor = baseColor.float3Value
        }

        if let specular = material?.property(with: .specular), specular.type == .float3 {
            self.specularColor = specular.float3Value
        }

        if let shininess = material?.property(with: .specularExponent), shininess.type == .float {
            self.shininess = shininess.floatValue
        }
    }
}
