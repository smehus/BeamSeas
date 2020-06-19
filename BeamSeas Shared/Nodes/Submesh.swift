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
    }

    let textures: Textures
    var mtkSubmesh: MTKSubmesh
    
    init(mdlSubmesh: MDLSubmesh, mtkSubmesh: MTKSubmesh) {
        self.mtkSubmesh = mtkSubmesh
        textures = Textures(material: mdlSubmesh.material)
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
    }
}
