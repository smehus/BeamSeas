
import Foundation
import MetalKit
import simd

class Renderer: NSObject, MTKViewDelegate {

    static var library: MTLLibrary!
    static var colorPixelFormat: MTLPixelFormat!
    static var depthStencilFormat: MTLPixelFormat!
    static var device: MTLDevice!
    static var sampleCount: Int!
    static var vertexDescriptor: MDLVertexDescriptor!

    let device: MTLDevice
    let depthStencilState: MTLDepthStencilState
    let vertexDescriptor: MDLVertexDescriptor
    let commandQueue: MTLCommandQueue

    let lighting = Lighting()
    var models: [Renderable] = []
    var fragmentUniforms = FragmentUniforms()
    var uniforms = Uniforms()
    var fragmetnUniforms = FragmentUniforms()

    lazy var camera: ThirdPersonCamera = {
        let camera = ThirdPersonCamera()
        camera.focusDistance = 6
        camera.focusHeight = 6
        return camera
    }()

    init(view: MTKView, device: MTLDevice) {
        Self.sampleCount = view.sampleCount
        Self.device = device
        Self.vertexDescriptor = Self.buildVertexDescriptor(device: device)
        Self.colorPixelFormat = view.colorPixelFormat
        Self.depthStencilFormat = view.depthStencilPixelFormat
        self.device = device
        Self.library = device.makeDefaultLibrary()

        commandQueue = device.makeCommandQueue()!
        vertexDescriptor = Renderer.buildVertexDescriptor(device: device)
        depthStencilState = Renderer.buildDepthStencilState(device: device)

        super.init()

        let terrain = Terrain()
        models.append(terrain)

        let character = Model(name: "Ship", fragment: "fragment_main")
        character.rotation = [Float(90).radiansToDegrees, 0, 0]
        models.append(character)

        camera.focus = character
    }
    
    static func buildVertexDescriptor(device: MTLDevice) -> MDLVertexDescriptor {
        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition,
                                                            format: .float3,
                                                            offset: 0,
                                                            bufferIndex: BufferIndex.vertexBuffer.rawValue)
        vertexDescriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal,
                                                            format: .float3,
                                                            offset: MemoryLayout<Float>.size * 3,
                                                            bufferIndex: BufferIndex.vertexBuffer.rawValue)
        vertexDescriptor.attributes[2] = MDLVertexAttribute(name: MDLVertexAttributeTangent,
                                                            format: .float3,
                                                            offset: MemoryLayout<Float>.size * 6,
                                                            bufferIndex: BufferIndex.vertexBuffer.rawValue)
        vertexDescriptor.attributes[3] = MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate,
                                                            format: .float2,
                                                            offset: MemoryLayout<Float>.size * 9,
                                                            bufferIndex: BufferIndex.vertexBuffer.rawValue)
        vertexDescriptor.layouts[BufferIndex.vertexBuffer.rawValue] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.size * 11)
        return vertexDescriptor
    }

    static func buildDepthStencilState(device: MTLDevice) -> MTLDepthStencilState {
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .less
        depthStencilDescriptor.isDepthWriteEnabled = true
        return device.makeDepthStencilState(descriptor: depthStencilDescriptor)!
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        camera.aspect = Float(view.bounds.width) / Float(view.bounds.height)
    }

    func draw(in view: MTKView) {
        guard let renderPassDescriptor = view.currentRenderPassDescriptor else { return }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        uniforms.projectionMatrix = camera.projectionMatrix
        uniforms.viewMatrix = camera.viewMatrix
        fragmetnUniforms.camera_position = camera.position


        // Compute Pass \\

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


        let computeHeightEncoder = commandBuffer.makeComputeCommandEncoder()!
        computeHeightEncoder.pushDebugGroup("Calc Height")
        for model in models {
//            model.computeHeight(
//                computeEncoder: computeHeightEncoder,
//                uniforms: &uniforms,
//                controlPoints: Terrain.controlPointsBuffer,
//                terrainParams: &Terrain.terrainParams)
        }

        computeHeightEncoder.popDebugGroup()
        computeHeightEncoder.endEncoding()



        let mainRenderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        mainRenderEncoder.setDepthStencilState(depthStencilState)

        var lights = lighting.lights
        mainRenderEncoder.setFragmentBytes(&lights, length: MemoryLayout<Light>.stride * lights.count, index: 7)

        for model in models {
            model.draw(
                renderEncoder: mainRenderEncoder,
                uniforms: &uniforms,
                fragmentUniforms: &fragmentUniforms
            )
        }

        mainRenderEncoder.endEncoding()
        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()

    }
}



