//
//  Renderer.swift
//  BeamSeas Shared
//
//  Created by Scott Mehus on 6/15/20.
//  Copyright © 2020 Scott Mehus. All rights reserved.
//

// Our platform independent renderer class

import Metal
import MetalKit
import simd

final class Renderer: NSObject {

    static var device: MTLDevice!
    static var commandQueue: MTLCommandQueue!
    static var library: MTLLibrary!

    lazy var camera: Camera = {
        let camera = ArcballCamera()
        camera.distance = 4.3
        camera.target = [0.0, 1.2, 0.0]
        camera.rotation.x = Float(-10).degreesToRadians
      return camera
    }()

    /// Debug lights
    lazy var lightPipelineState: MTLRenderPipelineState = {
      return buildLightPipelineState()
    }()

    var uniforms = Uniforms()
    var fragmentUniforms = FragmentUniforms()
    var models: [Model] = []
    var lights: [Light] = []
    var depthStencilState: MTLDepthStencilState

    init?(metalView: MTKView) {
        Self.device = MTLCreateSystemDefaultDevice()!
        Self.commandQueue = Renderer.device.makeCommandQueue()!
        Self.library = Self.device.makeDefaultLibrary()!

        metalView.device = Self.device
        metalView.depthStencilPixelFormat = .depth32Float

        depthStencilState = Self.buildDepthStencilState()
        super.init()

        metalView.clearColor = MTLClearColor(
            red: 1.0,
            green: 1.0,
            blue: 0.8,
            alpha: 1.0
        )

        metalView.delegate = self

        lights.append(Lights.sunlight)
        lights.append(Lights.ambientLight)
        lights.append(Lights.redLight)
        lights.append(Lights.spotlight)

        let house = Model(name: "lowpoly-house.obj")
        house.position = [0, 0, 0]
        house.rotation = [0, Float(45).degreesToRadians, 0]
        models.append(house)

        fragmentUniforms.light_count = UInt32(lights.count)
        mtkView(metalView, drawableSizeWillChange: metalView.bounds.size)
    }

    static func buildDepthStencilState() -> MTLDepthStencilState {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .less
        descriptor.isDepthWriteEnabled = true

        return Self.device.makeDepthStencilState(descriptor: descriptor)!
    }
}

extension Renderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        camera.aspect = Float(view.bounds.width) / Float(view.bounds.height)
    }

    func draw(in view: MTKView) {
        guard
            let descriptor = view.currentRenderPassDescriptor,
            let commandBuffer = Self.commandQueue.makeCommandBuffer(),
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else {
            return
        }

        renderEncoder.setDepthStencilState(depthStencilState)

        uniforms.projectionMatrix = camera.projectionMatrix
        uniforms.viewMatrix = camera.viewMatrix

        fragmentUniforms.camera_position = camera.position

        for model in models {

            uniforms.modelMatrix = model.modelMatrix
            uniforms.normalMatrix = uniforms.modelMatrix.upperLeft

            renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: BufferIndex.uniforms.rawValue)
            renderEncoder.setRenderPipelineState(model.pipelineState)

            renderEncoder.setFragmentBytes(&lights, length: MemoryLayout<Light>.stride * lights.count, index: BufferIndex.lights.rawValue)
            renderEncoder.setFragmentBytes(&fragmentUniforms, length: MemoryLayout<FragmentUniforms>.stride, index: BufferIndex.fragmentUniforms.rawValue)

            for mesh in model.meshes {
                let vertexBuffer = mesh.mtkMesh.vertexBuffers[0].buffer
                renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: BufferIndex.vertexBuffer.rawValue)

                for submesh in mesh.submeshes {
                    let mtkMesh = submesh.mtkSubmesh

                    renderEncoder.setFragmentTexture(submesh.textures.baseColor, index: TextureIndex.color.rawValue)
                    renderEncoder.drawIndexedPrimitives(
                        type: .triangle,
                        indexCount: mtkMesh.indexCount,
                        indexType: mtkMesh.indexType,
                        indexBuffer: mtkMesh.indexBuffer.buffer,
                        indexBufferOffset: mtkMesh.indexBuffer.offset
                    )
                }
            }
        }

        debugLights(renderEncoder: renderEncoder, lightType: Spotlight)
        renderEncoder.endEncoding()
        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }
}
