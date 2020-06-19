//
//  Texturable.swift
//  BeamSeas
//
//  Created by Scott Mehus on 6/19/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

import MetalKit

protocol Texturable { }

extension Texturable {

    static func loadTexture(imageName: String) -> MTLTexture {

        let textureLoader = MTKTextureLoader(device: Renderer.device)
        let textureLoaderOptions: [MTKTextureLoader.Option: Any] = [.origin: MTKTextureLoader.Origin.bottomLeft,
                                                                    .SRGB: false]
        let fileExtension = URL(fileURLWithPath: imageName).pathExtension.isEmpty ? "png" : nil
        let url = Bundle.main.url(forResource: imageName, withExtension: fileExtension)!
        let texture = try! textureLoader.newTexture(URL: url, options: textureLoaderOptions)

        print("✅ Loaded Texture \(imageName)")
        return texture
    }
}
