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
    static var metalView: MTKView!
    static var commandQueue: MTLCommandQueue!
    static var library: MTLLibrary!

    lazy var camera: Camera = {
        let camera = ArcballCamera()
        camera.distance = 30
        camera.target = [0, 0, -30]
        camera.rotation.x = Float(-10).degreesToRadians
//        camera.rotation.y = Float(-60).degreesToRadians
        return camera
    }()

    /// Debug lights
    lazy var lightPipelineState: MTLRenderPipelineState = {
      return buildLightPipelineState()
    }()

    var uniforms = Uniforms()
    var fragmentUniforms = FragmentUniforms()
    var models: [Renderable] = []
    var lighting = Lighting()
    var depthStencilState: MTLDepthStencilState
    var delta: Float = 0
    var firstRun = true
    var fft: BasicFFT

    init?(metalView: MTKView) {
        Self.metalView = metalView
        Self.device = MTLCreateSystemDefaultDevice()!
        Self.commandQueue = Renderer.device.makeCommandQueue()!
        Self.library = Self.device.makeDefaultLibrary()!

        metalView.device = Self.device
        metalView.depthStencilPixelFormat = .depth32Float

        depthStencilState = Self.buildDepthStencilState()

        fft = BasicFFT()

        super.init()

        metalView.clearColor = MTLClearColor(red: 0.0, green: 0.0,
                                             blue: 0.0, alpha: 1)

        metalView.delegate = self



        let terrain = Terrain()
        models.append(terrain)

        let cube = Model(name: "Ship", fragment: "fragment_pbr")
        cube.position = [-1, 0, -50]
        cube.rotation = [Float(-90).degreesToRadians, 0/*Float(-20).degreesToRadians*/, 0]
        models.append(cube)


        models.append(fft)
        fragmentUniforms.light_count = UInt32(lighting.count)

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
            let commandBuffer = Self.commandQueue.makeCommandBuffer()
        else {
            return
        }

        delta += 0.02
        uniforms.deltaTime = delta
        uniforms.projectionMatrix = camera.projectionMatrix
        uniforms.viewMatrix = camera.viewMatrix
        fragmentUniforms.camera_position = camera.position


        let distributionEncoder = commandBuffer.makeComputeCommandEncoder()!
        fft.generateDistributions(computeEncoder: distributionEncoder, uniforms: uniforms)
        distributionEncoder.endEncoding()

        fft.runfft(phase: delta)

        let mapEncoder = commandBuffer.makeComputeCommandEncoder()!
        fft.generateMaps(computeEncoder: mapEncoder, uniforms: &uniforms)
        mapEncoder.endEncoding()


        let gradientEncoder = commandBuffer.makeComputeCommandEncoder()!
        fft.generateGradient(computeEncoder: gradientEncoder, uniforms: &uniforms)
        gradientEncoder.endEncoding()

        let normalEncoder = commandBuffer.makeComputeCommandEncoder()!
        fft.generateTerrainNormals(computeEncoder: normalEncoder, uniforms: &uniforms)
        normalEncoder.endEncoding()


        // Terrain Pass \\

        let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
        computeEncoder.pushDebugGroup("Tessellation")
        computeEncoder.setBytes(
            &fragmentUniforms,
            length: MemoryLayout<FragmentUniforms>.stride,
            index: BufferIndex.fragmentUniforms.rawValue
        )

        for model in models {
            model.compute(computeEncoder: computeEncoder, uniforms: &uniforms, fragmentUniforms: &fragmentUniforms)
        }

        computeEncoder.popDebugGroup()
        computeEncoder.endEncoding()


        // Height pass \\
        let computeHeightEncoder = commandBuffer.makeComputeCommandEncoder()!
        computeHeightEncoder.pushDebugGroup("Calc Height")
        for model in models {
            model.computeHeight(
                computeEncoder: computeHeightEncoder,
                uniforms: &uniforms,
                controlPoints: Terrain.controlPointsBuffer,
                terrainParams: &Terrain.terrainParams)
        }

        computeHeightEncoder.popDebugGroup()
        computeHeightEncoder.endEncoding()

        // Render Pass \\
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)!
        renderEncoder.setDepthStencilState(depthStencilState)

        var lights = lighting.lights
        renderEncoder.setFragmentBytes(&lights, length: MemoryLayout<Light>.stride * lights.count, index: BufferIndex.lights.rawValue)

        for model in models {
            uniforms.deltaTime = delta
            uniforms.projectionMatrix = camera.projectionMatrix
            uniforms.viewMatrix = camera.viewMatrix
            fragmentUniforms.camera_position = camera.position
            model.draw(renderEncoder: renderEncoder, uniforms: &uniforms, fragmentUniforms: &fragmentUniforms)
        }

        
        debugLights(renderEncoder: renderEncoder, lightType: Sunlight)
        renderEncoder.endEncoding()
        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }
}
