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
    var playerRotation: (position: float3, tangent0: float3, tangent1: float3, normalMap: float3)!

    lazy var camera: Camera = {
        
//        let camera = ArcballCamera()
//        camera.distance = 80
//        camera.target = [0, 0, -80]
//        camera.rotation.x = Float(-10).degreesToRadians
//        camera.rotation.y = Float(-60).degreesToRadians
 
        
//        let camera = ThirdPersonCamera()
//        camera.focus = player
//        camera.focusDistance = 100
//        camera.focusHeight = 200

        let camera = Camera()
        camera.position.z = -300
        camera.position.y = 100
        camera.rotation.x = Float(45).degreesToRadians
        return camera
    }()
    
    let reflectionCamera = Camera()

    /// Debug lights
    lazy var lightPipelineState: MTLRenderPipelineState = {
      return buildLightPipelineState()
    }()

    var uniforms = Uniforms()
    private(set) var fragmentUniforms = FragmentUniforms()
    private(set) var models: [Renderable] = []
    private(set) var lighting = Lighting()
    private(set) var depthStencilState: MTLDepthStencilState
    private(set) var delta: Float = 0
    private(set) var deltaFactor: DeltaFactor = .normal
    private(set) var firstRun = true
    private(set) var fft: BasicFFT
    private(set) var player: Model!
    private(set) var skybox: Skybox!
    private(set) var terrain: Terrain!
    private(set) var mapScaffolding: WorldMapScaffolding!
    private(set) var reflectionRenderPass: RenderPass
    private(set) var refractionRenderPass: RenderPass

    enum DeltaFactor: Float {
        case normal = 0.01
        case forward = 0.025
    }

    init?(metalView: MTKView) {
        Self.metalView = metalView
        Self.device = MTLCreateSystemDefaultDevice()!
        Self.commandQueue = Renderer.device.makeCommandQueue()!
        Self.library = Self.device.makeDefaultLibrary()!

        metalView.device = Self.device
        metalView.depthStencilPixelFormat = .depth32Float

        depthStencilState = Self.buildDepthStencilState()

        fft = BasicFFT()
        
        reflectionRenderPass = RenderPass(name: "Reflection",
                                          size: metalView.drawableSize)
        refractionRenderPass = RenderPass(name: "Refraction",
                                          size: metalView.drawableSize)

        super.init()

        metalView.clearColor = MTLClearColor(red: 0.4, green: 0.4,
                                             blue: 0.4, alpha: 1)

        metalView.delegate = self
        
        skybox = Skybox(textureName: nil)
        
        let scaffoldingSize: Float = 500
        mapScaffolding = WorldMapScaffolding(extent: SIMD3<Float>(repeating: scaffoldingSize), segments: [50, 50])
        mapScaffolding.position = float3(0, (-(mapScaffolding.size.x / 2) - 30), 0)
    
        terrain = Terrain()
        terrain.scaffoldingPosition = [0, ((mapScaffolding.size.x / 2) + 10), 0]
        terrain.position = [0, ((mapScaffolding.size.x / 2) + 10), 0]
        models.append(terrain)
        mapScaffolding.add(child: terrain)
        
        models.append(mapScaffolding)

        player = Model(name: "OldBoat", fragment: "fragment_pbr")
        player.scale = [0.5, 0.5, 0.5]
        models.append(player) 
        terrain.add(child: player)
        models.append(fft)
        fragmentUniforms.light_count = UInt32(lighting.count)
        
        let worldMap = MiniWorldMap(vertexName: "worldMap_vertex", fragmentName: "worldMap_fragment")
        worldMap.position = float3(0, 0, 30)
        models.append(worldMap)



        mtkView(metalView, drawableSizeWillChange: metalView.bounds.size)
    }

    static func buildDepthStencilState() -> MTLDepthStencilState {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .less
        descriptor.isDepthWriteEnabled = true

        return Self.device.makeDepthStencilState(descriptor: descriptor)!
    }
}

protocol AspectRatioUpdateable {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize)
}

extension Renderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        camera.aspect = Float(size.width) / Float(size.height)
        reflectionRenderPass.updateTextures(size: size)
        refractionRenderPass.updateTextures(size: size)
        
        for case let aspectRatioUpdateable as AspectRatioUpdateable in models {
            aspectRatioUpdateable.mtkView(view, drawableSizeWillChange: size)
        }
    }

    func draw(in view: MTKView) {
        guard
            let descriptor = view.currentRenderPassDescriptor,
            let commandBuffer = Self.commandQueue.makeCommandBuffer()
        else {
            return
        }
        
        mtkView(view, drawableSizeWillChange: view.drawableSize)

        var lights = lighting.lights
        let fps = Float(Float(1) / Float(view.preferredFramesPerSecond))
        delta += (fps * 2)
        
        uniforms.deltaTime = delta
        uniforms.projectionMatrix = camera.projectionMatrix
        uniforms.viewMatrix = camera.viewMatrix
        fragmentUniforms.camera_position = camera.position
        
        // MARK: - UPDATE MODELS
        for model in models {
            if var container = model as? RendererContianer {
                container.renderer = self
            }
        
            model.update(
                deltaTime: delta,
                uniforms: &uniforms,
                fragmentUniforms: &fragmentUniforms,
                camera: camera,
                player: player
            )
        }
        
        // MARK: - REFLECTION PASS
        let reflectEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: reflectionRenderPass.descriptor)!
        reflectEncoder.pushDebugGroup("Reflection Pass")
        reflectEncoder.setDepthStencilState(depthStencilState)
        reflectEncoder.setFragmentBytes(
            &lights,
            length: MemoryLayout<Light>.stride * lights.count,
            index: BufferIndex.lights.rawValue
        )
        
        reflectionCamera.rotation = camera.rotation
        reflectionCamera.position = camera.position
        reflectionCamera.scale = camera.scale
        
        reflectionCamera.position.y = -camera.position.y
        reflectionCamera.rotation.x = -camera.rotation.x
        uniforms.viewMatrix = reflectionCamera.viewMatrix
//        uniforms.clipPlane = float4(0, 1, 0, 0.3)
        
        for renderable in models {
            guard let model = renderable as? Model, model.name == "OldBoat" else { continue }
            
            model.draw(
                renderEncoder: reflectEncoder,
                uniforms: &uniforms,
                fragmentUniforms: &fragmentUniforms
            )
        }
        
        skybox.draw(renderEncoder: reflectEncoder,
                    uniforms: &uniforms,
                    fragmentUniforms: &fragmentUniforms)
        reflectEncoder.endEncoding()
        reflectEncoder.popDebugGroup()
        
        // MARK: - REFRACTION PASS
        uniforms.clipPlane = float4(0, -1, 0, 0.1)
        uniforms.viewMatrix = camera.viewMatrix
        let refractEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: refractionRenderPass.descriptor)!
        refractEncoder.pushDebugGroup("Refraction Pass")
        refractEncoder.setDepthStencilState(depthStencilState)
        refractEncoder.setFragmentBytes(
            &lights,
            length: MemoryLayout<Light>.stride * lights.count,
            index: BufferIndex.lights.rawValue
        )
        
        for renderable in models {
            guard let model = renderable as? Model, model.name == "OldBoat" else { continue }
            
            model.draw(
                renderEncoder: refractEncoder,
                uniforms: &uniforms,
                fragmentUniforms: &fragmentUniforms
            )
        }
        
        skybox.draw(
            renderEncoder: refractEncoder,
            uniforms: &uniforms,
            fragmentUniforms: &fragmentUniforms
        )
        
        refractEncoder.endEncoding()
        refractEncoder.popDebugGroup()
        
        
        uniforms.projectionMatrix = camera.projectionMatrix
        uniforms.viewMatrix = camera.viewMatrix
        uniforms.clipPlane = float4(0, -1, 0, 100)
        
        // MARK: - FFT PASS
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


        // MARK: - TERRAIN PASS

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


        // MARK: - Height Pass
        
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

        
        // MARK: - Main Render Pass
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)!
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setFragmentBytes(&lights, length: MemoryLayout<Light>.stride * lights.count, index: BufferIndex.lights.rawValue)

        if player.moveStates.contains(.forward) {
            uniforms.playerMovement += player.forwardVector * 0.001
        }
        
        renderEncoder.setFragmentTexture(reflectionRenderPass.texture, index: TextureIndex.reflection.rawValue)
        renderEncoder.setFragmentTexture(refractionRenderPass.texture, index: TextureIndex.refraction.rawValue)
        
        for model in models {
            uniforms.deltaTime = delta
            uniforms.projectionMatrix = camera.projectionMatrix
            uniforms.viewMatrix = camera.viewMatrix
            fragmentUniforms.camera_position = camera.position
            model.draw(renderEncoder: renderEncoder, uniforms: &uniforms, fragmentUniforms: &fragmentUniforms)
            renderEncoder.setDepthStencilState(depthStencilState)
            renderEncoder.setTriangleFillMode(.fill)
            renderEncoder.setViewport(
                MTLViewport(originX: 0,
                            originY: 0,
                            width: Renderer.metalView.drawableSize.width.double,
                            height: Renderer.metalView.drawableSize.height.double,
                            znear: 0.001,
                            zfar: 1)
            )
        }
        
        renderEncoder.setDepthStencilState(depthStencilState)
        skybox.draw(renderEncoder: renderEncoder, uniforms: &uniforms, fragmentUniforms: &fragmentUniforms)
        
        uniforms.projectionMatrix = camera.projectionMatrix
        uniforms.viewMatrix = camera.viewMatrix

        // MARK: - DEBUG NORMALS
//        var playerRotation: (position: float3, tangent0: float3, tangent1: float3, normalMap: float3)!
        let tangent0 = float3(playerRotation.tangent0.x.radiansToDegrees, playerRotation.tangent0.y.radiansToDegrees, playerRotation.tangent0.z.radiansToDegrees)
        let tangent1 = float3(playerRotation.tangent1.x.radiansToDegrees, playerRotation.tangent1.y.radiansToDegrees, playerRotation.tangent1.z.radiansToDegrees)
        let normalMap = float3(playerRotation.normalMap.x.radiansToDegrees, playerRotation.normalMap.y.radiansToDegrees, playerRotation.normalMap.z.radiansToDegrees)
        
//        drawSpotLight(renderEncoder: renderEncoder, position: playerRotation.position, direction: tangent0, color: float3(1, 0, 0)) // Red
        drawSpotLight(renderEncoder: renderEncoder, position: playerRotation.position, direction: tangent1, color: float3(0, 1, 0)) // Green forwardVec
//        drawSpotLight(renderEncoder: renderEncoder, position: playerRotation.position, direction: normalMap, color: float3(1, 0, 1)) // Blue

//        drawDirectionalLight(renderEncoder: renderEncoder, direction: direction, color: float3(1, 0, 0), count: 5)
//        debugLights(renderEncoder: renderEncoder, lightType: Spotlight)
        renderEncoder.endEncoding()
        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }
}


extension Renderer {
    func didUpdate(keys: Set<Key>) {
        for renderable in models {
            renderable.didUpdate(keys: keys)
        }
    }
}
