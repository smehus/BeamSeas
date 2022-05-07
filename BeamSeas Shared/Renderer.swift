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
        
//        let instance = Camera()
//        instance.position = [0, 5100, -100]
//        instance.rotation.x = Float(30).degreesToRadians
        
//        let instance = ArcballCamera()
//        instance.distance = 80
//        instance.target = SIMD3<Float>(0, 5200, 0)
 

        let instance = BaseThirdPersonCamera(focus: player)
        instance.focusDistance = 50
        instance.focusHeight = 25
        
//        let instance = ThirdPersonCamera(focus: player, scaffolding: mapScaffolding)
//        instance.focusDistance = 300
//        instance.focusHeight = 50

//        let instance = Camera()
//        instance.position.y = (mapScaffolding.size.x / 2) + 200
//        instance.rotation.x = Float(90).degreesToRadians
        
        

//        let instance = TopDownFollowRotationCamera()
//        instance.node = player
//        instance.position.y = terrain.scaffoldingPosition.y + 100
//        instance.rotation.x = Float(90).degreesToRadians
        
//        let instance = ClassicThirdPersonCamera(focus: player)
//        instance.focusDistance = 200
//        instance.focusHeight = 100
        return instance
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
    private(set) var lastUpdateTime: Float = 0
    private(set) var deltaFactor: DeltaFactor = .normal
    private(set) var firstRun = true
    private(set) var fft: BasicFFT
    private(set) var player: Model!
    private(set) var skybox: Skybox!
    private(set) var terrain: Terrain!
    private(set) var mapScaffolding: WorldMapScaffolding!
    private(set) var reflectionRenderPass: RenderPass
    private(set) var refractionRenderPass: RenderPass
    static let scaffoldingSize: Float = 5000

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

        metalView.clearColor = MTLClearColor(red: 0, green: 0,
                                             blue: 0, alpha: 1)

        metalView.delegate = self
        
        skybox = Skybox(textureName: nil)

        mapScaffolding = WorldMapScaffolding(extent: SIMD3<Float>(repeating: Renderer.scaffoldingSize), segments: [50, 50])
//        mapScaffolding.position = [0, -(mapScaffolding.size.x / 2), 0]
        models.append(mapScaffolding)
        
        
        terrain = Terrain()
//        terrain.scaffoldingPosition = [0, (mapScaffolding.size.x / 2), 0] // UV
        terrain.position = [0, (mapScaffolding.size.x / 2), 0] // UV
        mapScaffolding.add(child: terrain)
        models.append(terrain)
        
        var material = Material()
        material.baseColor = float3(1, 0, 0)
        let shape = BasicShape(shape: .sphere(extent: [3, 10, 3],
                                                 segments: [5, 5],
                                                 inwardNormals: false,
                                                 geometryType: .triangles,
                                                 material: material))
        models.append(shape)
        
        player = Model(name: "OldBoat", fragment: "fragment_main")
        player.scale = [0.5, 0.5, 0.5]
        terrain.add(child: player)
        models.append(player)
        
        models.append(fft)
        fragmentUniforms.light_count = UInt32(lighting.count)
        
        let worldMap = MiniWorldMap(vertexName: "worldMap_vertex", fragmentName: "worldMap_fragment")
        models.append(worldMap)
        
        
        // Debug Nodes \\
//        
//        var material = Material()
//        material.baseColor = float3(1, 0, 0)
//        let topShape = BasicShape(shape: .sphere(extent: [30, 30, 30],
//                                                 segments: [10, 10],
//                                                 inwardNormals: false,
//                                                 geometryType: .triangles,
//                                                 material: material))
//        topShape.position = [0, (mapScaffolding.size.x / 2), 0]
//        mapScaffolding.add(child: topShape)
//        models.append(topShape)
//        
//        material.baseColor = float3(0, 0, 1)
//        let bottomShape = BasicShape(shape: .sphere(extent: [30, 30, 30],
//                                                 segments: [10, 10],
//                                                 inwardNormals: false,
//                                                 geometryType: .triangles,
//                                                 material: material))
//        bottomShape.position = [0, -(mapScaffolding.size.x / 2), 0]
//        mapScaffolding.add(child: bottomShape)
//        models.append(bottomShape)
//        
        
        // Debug Nodes \\

        mtkView(metalView, drawableSizeWillChange: metalView.bounds.size)
    }

    static func buildDepthStencilState() -> MTLDepthStencilState {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .lessEqual
        descriptor.isDepthWriteEnabled = true

        return Self.device.makeDepthStencilState(descriptor: descriptor)!
    }
}

protocol AspectRatioUpdateable {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize)
}

extension Renderer {
    func handleLocationInteraction(location: CGPoint) {
        let viewport = Self.metalView.bounds // Assume viewport matches window; if not, apply additional inverse viewport xform
         let width = Float(viewport.size.width)
         let height = Float(viewport.size.height)
//         let aspectRatio = width / height
        
        let clipX = (2 * Float(location.x)) / width - 1
        let clipY = 1 - (2 * Float(location.y)) / height
        let clipCoords = float4(clipX, clipY, 0, 1)
        
        let projectionMatrix = camera.projectionMatrix
        let inverseProjectionMatrix = projectionMatrix.inverse
        
        var eyeRayDir = inverseProjectionMatrix * clipCoords
        eyeRayDir.z = -1
        eyeRayDir.w = 0
        
        let viewMatrix = camera.worldTransform.inverse
        let inverseViewMatrix = viewMatrix.inverse
        
        var worldRayDir = (inverseViewMatrix * eyeRayDir).xyz
        worldRayDir = normalize(worldRayDir)
        
        let eyeRayOrigin = float4(x: 0, y: 0, z: 0, w: 1)
        let worldRayOrigin = (inverseViewMatrix * eyeRayOrigin).xyz
        
        print("*** world ray \(worldRayOrigin)")
        print("*** dir: \(worldRayDir)")
    }
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
//        lastUpdateTime += fps
        
        var light = lights.first!
        light.position.x += 0.5
        lighting.lights = [light]
        
        uniforms.currentTime = lastUpdateTime
        uniforms.projectionMatrix = camera.projectionMatrix
        uniforms.viewMatrix = camera.viewMatrix
        fragmentUniforms.camera_position = camera.position
        
        // MARK: - UPDATE MODELS
        for model in models {
            if var container = model as? RendererContianer {
                container.renderer = self
            }
        
            model.update(
                deltaTime: lastUpdateTime,
                uniforms: &uniforms,
                fragmentUniforms: &fragmentUniforms,
                camera: camera,
                scaffolding: mapScaffolding,
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
        reflectEncoder.setVertexBytes(&lights, length: MemoryLayout<Light>.stride * lights.count, index: BufferIndex.lights.rawValue)
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
        refractEncoder.setVertexBytes(&lights, length: MemoryLayout<Light>.stride * lights.count, index: BufferIndex.lights.rawValue)
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

        fft.runfft(phase: lastUpdateTime)

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
        renderEncoder.setVertexBytes(&lights, length: MemoryLayout<Light>.stride * lights.count, index: BufferIndex.lights.rawValue)

        if player.moveStates.contains(.forward) {
            uniforms.playerMovement += player.forwardVector * 0.001
        }
        
        renderEncoder.setFragmentTexture(reflectionRenderPass.texture, index: TextureIndex.reflection.rawValue)
        renderEncoder.setFragmentTexture(refractionRenderPass.texture, index: TextureIndex.refraction.rawValue)
        
        for model in models {
            uniforms.currentTime = lastUpdateTime
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
//        drawSpotLight(renderEncoder: renderEncoder, position: playerRotation.position, direction: tangent1, color: float3(0, 1, 0)) // Green forwardVec
//        drawSpotLight(renderEncoder: renderEncoder, position: playerRotation.position, direction: normalMap, color: float3(1, 0, 1)) // Blue

//        drawDirectionalLight(renderEncoder: renderEncoder, direction: direction, color: float3(1, 0, 0), count: 5)
        debugLights(renderEncoder: renderEncoder, lightType: Sunlight)
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
