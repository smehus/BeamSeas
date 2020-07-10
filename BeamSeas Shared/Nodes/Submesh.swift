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
//    let material: Material
    
    init(mdlSubmesh: MDLSubmesh, mtkSubmesh: MTKSubmesh, fragmentName: String) {
        self.mtkSubmesh = mtkSubmesh
        textures = Textures(material: mdlSubmesh.material)
//        material = Material(material: mdlSubmesh.material)
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
        pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(Renderer.vertexDescriptor)
        pipelineDescriptor.colorAttachments[0].pixelFormat = Renderer.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = Renderer.depthStencilFormat
        pipelineDescriptor.sampleCount = Renderer.sampleCount
        do {
            pipelineState = try Renderer.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch let error {
            fatalError(error.localizedDescription)
        }
        return pipelineState
    }

    private static func makeFunctionConstants(textures: Textures) -> MTLFunctionConstantValues {
        let constants = MTLFunctionConstantValues()

//        constant bool hasColorTexture [[function_constant(0)]];
        var property = textures.baseColor != nil
        constants.setConstantValue(&property, type: .bool, index: 0)

//        constant bool hasNormalTexture [[function_constant(1)]];
        property = textures.normal != nil
        constants.setConstantValue(&property, type: .bool, index: 1)

//        constant bool hasRoughnessTexture [[function_constant(2)]];
        property = false
        constants.setConstantValue(&property, type: .bool, index: 2)

//        constant bool hasMetallicTexture [[function_constant(3)]];
        constants.setConstantValue(&property, type: .bool, index: 3)

//        constant bool hasAOTexture [[function_constant(4)]];
        constants.setConstantValue(&property, type: .bool, index: 4)


        // TODO: - Setup roughness textures
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
                    let texture = try? Submesh.loadTexture(texture: mdlTexture, useMips: property.semantic != .tangentSpaceNormal){
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

//private extension Material {
//    init(material: MDLMaterial?) {
//        self.init()
//
//        if let baseColor = material?.property(with: .baseColor), baseColor.type == .float3 {
//            self.baseColor = baseColor.float3Value
//        }
//
//        if let specular = material?.property(with: .specular), specular.type == .float3 {
//            self.specularColor = specular.float3Value
//        }
//
//        if let shininess = material?.property(with: .specularExponent), shininess.type == .float {
//            self.shininess = shininess.floatValue
//        }
//    }
//}
