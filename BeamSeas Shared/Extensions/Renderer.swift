
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
    var nodes = [Node]()
    var fragmentUniforms = FragmentUniforms()
    var uniforms = Uniforms()
    var fragmetnUniforms = FragmentUniforms()

    var character: Node!

    lazy var camera: Camera = {
        let camera = ThirdPersonCamera()
        camera.focus = character
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


        character = Model(name: "Ship", fragment: "fragment_main")
        character.rotation = [Float(90).radiansToDegrees, 0, Float(90).radiansToDegrees]
        nodes.append(character)
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

        if let remderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            remderEncoder.setDepthStencilState(depthStencilState)

            for node in nodes {
                draw(node, in: remderEncoder)
            }
            
            remderEncoder.endEncoding()


            if let drawable = view.currentDrawable {
                commandBuffer.present(drawable)
            }
            commandBuffer.commit()
        }
    }
    
    func draw(_ node: Node, in commandEncoder: MTLRenderCommandEncoder) {


        var lights = lighting.lights
        commandEncoder.setFragmentBytes(&lights, length: MemoryLayout<Light>.stride * lights.count, index: 7)

        if let renderable = node as? Renderable {
            renderable.draw(renderEncoder: commandEncoder, uniforms: &uniforms, fragmentUniforms: &fragmentUniforms)
        }
    }
}



