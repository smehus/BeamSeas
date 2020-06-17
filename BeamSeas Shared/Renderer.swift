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
      camera.distance = 2
      camera.target = [0, 0.5, 0]
      camera.rotation.x = Float(-10).degreesToRadians
      return camera
    }()


    var uniforms = Uniforms()
    var models: [Model] = []


    init?(metalView: MTKView) {
        Self.device = metalView.device!
        Self.commandQueue = Renderer.device.makeCommandQueue()!
        Self.library = Self.device.makeDefaultLibrary()!

        super.init()

        metalView.clearColor = MTLClearColor(
            red: 1.0,
            green: 1.0,
            blue: 0.8,
            alpha: 1.0
        )

        metalView.delegate = self

        let train = Model(name: "train.obj")
        train.position = [0, 0, 0]
        train.rotation = [0, Float(45).degreesToRadians, 0]
        models.append(train)

        mtkView(metalView, drawableSizeWillChange: metalView.bounds.size)
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

        uniforms.projectionMatrix = camera.projectionMatrix
        uniforms.viewMatrix = camera.viewMatrix

        for model in models {

            uniforms.modelMatrix = model.modelMatrix

            renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: BufferIndex.uniforms.rawValue)
            renderEncoder.setRenderPipelineState(model.pipelineState)

            for mesh in model.meshes {
                let vertexBuffer = mesh.mtkMesh.vertexBuffers[0].buffer
                renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: BufferIndex.vertexBuffer.rawValue)

                for submesh in mesh.submeshes {
                    let mtkMesh = submesh.mtkSubmesh

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

        renderEncoder.endEncoding()
        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }
}
