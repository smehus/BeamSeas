//
//  Mesh.swift
//  BeamSeas
//
//  Created by Scott Mehus on 6/17/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

import MetalKit

struct Mesh {
    let mtkMesh: MTKMesh
    let mdlMesh: MDLMesh
    let submeshes: [Submesh]

    init(mdlMesh: MDLMesh, mtkMesh: MTKMesh, fragment: String) {
        self.mtkMesh = mtkMesh
        self.mdlMesh = mdlMesh
        submeshes = zip(mdlMesh.submeshes!, mtkMesh.submeshes).map { mesh in
            Submesh(mdlSubmesh: mesh.0 as! MDLSubmesh, mtkSubmesh: mesh.1, fragmentName: fragment)
        }
    }
}
