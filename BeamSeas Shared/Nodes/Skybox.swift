//
//  Skybox.swift
//  BeamSeas
//
//  Created by Scott Mehus on 6/16/21.
//  Copyright © 2021 Scott Mehus. All rights reserved.
//

import MetalKit
import Foundation
import simd

class Skybox: Node, Texturable, DepthStencilStateBuilder {
    
    struct SkySettings {
        var turbidity: Float = 0.28
        var sunElevation: Float = 0.5
        var upperAtmosphereScattering: Float = 0.1
        var groundAlbedo: Float = 4
    }
    var skySettings = SkySettings()
    let mesh: MTKMesh
    var texture: MTLTexture?
    let pipelineState: MTLRenderPipelineState
    let depthStencilState: MTLDepthStencilState?
    
    init(textureName: String?) {
        
        let allocator = MTKMeshBufferAllocator(device: Renderer.device)
        let cube = MDLMesh(boxWithExtent: [1,1,1], segments: [1, 1, 1],
                           inwardNormals: true,
                           geometryType: .triangles,
                           allocator: allocator)
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.colorAttachments[0].pixelFormat = Renderer.metalView.colorPixelFormat
        descriptor.depthAttachmentPixelFormat = .depth32Float
        descriptor.vertexFunction = Renderer.library?.makeFunction(name: "vertexSkybox")
        descriptor.fragmentFunction = Renderer.library?.makeFunction(name: "fragmentSkybox")
        descriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(cube.vertexDescriptor)
        
        do {
            mesh = try MTKMesh(mesh: cube, device: Renderer.device)
            pipelineState = try Renderer.device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            fatalError(error.localizedDescription)
        }
        
        let stencilDescriptor = MTLDepthStencilDescriptor()
        stencilDescriptor.depthCompareFunction = .less
        stencilDescriptor.isDepthWriteEnabled = true
        depthStencilState = Renderer.device.makeDepthStencilState(descriptor: stencilDescriptor)
        
        super.init()
  
        texture = loadSkyboxTexture()
//        if let _ = textureName {
//            // Custome texture if available
//        } else {
//            texture = loadGeneratedSkyboxTexture(dimensions: [256, 256])
//        }
    }
    
    func loadGeneratedSkyboxTexture(dimensions: SIMD2<Int32>) -> MTLTexture? {
        var texture: MTLTexture?
        
        let skyTexture = MDLSkyCubeTexture(
            name: "sky",
            channelEncoding: .uInt8,
            textureDimensions: dimensions,
            turbidity: skySettings.turbidity,
            sunElevation: skySettings.sunElevation,
            upperAtmosphereScattering: skySettings.upperAtmosphereScattering,
            groundAlbedo: skySettings.groundAlbedo
        )
        
        do {
            let textureLoader = MTKTextureLoader(device: Renderer.device)
            texture = try textureLoader.newTexture(texture: skyTexture, options: nil)
        } catch {
            fatalError(error.localizedDescription)
        }
        
        return texture
    }
}

extension Skybox: Renderable {
    
    func update(
        deltaTime: Float,
        uniforms: inout Uniforms,
        fragmentUniforms: inout FragmentUniforms,
        camera: Camera,
        scaffolding: WorldMapScaffolding,
        player: Model
    ) {
        
    }
    
    func draw(renderEncoder: MTLRenderCommandEncoder, uniforms: inout Uniforms, fragmentUniforms: inout FragmentUniforms) {
        renderEncoder.pushDebugGroup("Skybox")

        var viewMatrix = uniforms.viewMatrix
        viewMatrix.columns.3 = [0, 0, 0, 1]
        var viewProjectionMatrix = uniforms.projectionMatrix * viewMatrix
        uniforms.viewMatrix = viewMatrix
        uniforms.modelMatrix = modelMatrix
        
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthStencilState)
        
        renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: BufferIndex.uniforms.rawValue)
        renderEncoder.setVertexBuffer(mesh.vertexBuffers[0].buffer, offset: 0, index: 0)
        renderEncoder.setVertexBytes(&viewProjectionMatrix, length: MemoryLayout<float4x4>.stride, index: 1)
        renderEncoder.setFragmentTexture(texture, index: TextureIndex.skybox.rawValue)
        
        let submesh = mesh.submeshes[0]
        renderEncoder.drawIndexedPrimitives(type: .triangle,
          indexCount: submesh.indexCount,
          indexType: submesh.indexType,
          indexBuffer: submesh.indexBuffer.buffer,
          indexBufferOffset: 0)
        
        renderEncoder.popDebugGroup()
    }
}
