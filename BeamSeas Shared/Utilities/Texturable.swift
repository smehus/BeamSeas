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

    static func loadTexture(imageName: String, path: String = "png") -> MTLTexture {

        let textureLoader = MTKTextureLoader(device: Renderer.device)
        let textureLoaderOptions: [MTKTextureLoader.Option: Any] = [.origin: MTKTextureLoader.Origin.bottomLeft,
                                                                    .SRGB: false,
                                                                    .generateMipmaps: NSNumber(booleanLiteral: true)]
        let fileExtension = URL(fileURLWithPath: imageName).pathExtension.isEmpty ? path : nil
        guard let url = Bundle.main.url(forResource: imageName, withExtension: fileExtension) else {
            // Read from asset catalog
            return try! textureLoader.newTexture(name: imageName,
                                                 scaleFactor: 1.0,
                                                 bundle: Bundle.main,
                                                 options: nil)
        }
        let texture = try! textureLoader.newTexture(URL: url, options: textureLoaderOptions)

        print("✅ Loaded Texture \(imageName)")
        return texture
    }

    static func loadTexture(texture: MDLTexture) throws -> MTLTexture? {
        let textureLoader = MTKTextureLoader(device: Renderer.device)
        let textureLoaderOptions: [MTKTextureLoader.Option: Any] =
            [.origin: MTKTextureLoader.Origin.bottomLeft,
             .SRGB: false,
             .generateMipmaps: NSNumber(booleanLiteral: true)]

        let texture = try! textureLoader.newTexture(texture: texture,
                                                    options: textureLoaderOptions)
        return texture
    }
    
    func loadSkyboxTexture(names: [String] = ["TropicalSunnyDay_px.jpg",
                                              "TropicalSunnyDay_nx.jpg",
                                              "TropicalSunnyDay_py.jpg",
                                              "TropicalSunnyDay_ny.jpg",
                                              "TropicalSunnyDay_pz.jpg",
                                              "TropicalSunnyDay_nz.jpg"]) -> MTLTexture? {
        var texture: MTLTexture?
        let textureLoader = MTKTextureLoader(device: Renderer.device)
        if let mdlTexture = MDLTexture(cubeWithImagesNamed: names) {
            do {
                texture = try textureLoader.newTexture(texture: mdlTexture, options: nil)
            } catch {
                print("no texture created")
            }
        } else {
            fatalError("Failed to find cube skybox textures")
        }
        return texture
    }
    
    func loadCubeMap(names: [String], options: [MTKTextureLoader.Option : Any]? = [.origin: MTKTextureLoader.Origin.bottomLeft]) -> MTLTexture? {
        guard let mdlTexture = MDLTexture(cubeWithImagesNamed: names) else { fatalError("Failed to find cube skybox textures") }
        
        var texture: MTLTexture?
        let descriptor = MTLTextureDescriptor()
        descriptor.height = 128
        descriptor.width = 128
        let textureLoader = MTKTextureLoader(device: Renderer.device)
        
        do {
            texture = try textureLoader.newTexture(texture: mdlTexture,
                                                   options: options)
        } catch {
            print("no texture created")
        }
    
        return texture
    }
}

extension Texturable {
    func worldMapTexture(options: [MTKTextureLoader.Option : Any]? = [.origin: MTKTextureLoader.Origin.bottomLeft]) -> MTLTexture? {
//        return loadCubeMap(names: ["posx.jpg",
//                                   "negx.jpg",
//                                   "posy.jpg",
//                                   "negy.jpg",
//                                   "posz.jpg",
//                                   "negz.jpg"],
//                           options: options)
        
        return loadCubeMap(names: ["world_map_+x.png",
                                   "world_map_-x.png",
                                   "world_map_+y.png",
                                   "world_map_-y.png",
                                   "world_map_+z.png",
                                   "world_map_-z.png"],
                           options: options)
    }
}
