
import Foundation
import MetalKit
import simd
//
//enum TextureIndex: Int {
//    case baseColor
//    case metallic
//    case roughness
//    case normal
//    case emissive
//    case irradiance = 9
//}

//enum VertexBufferIndex: Int {
//    case attributes
//    case uniforms
//}
//
//enum FragmentBufferIndex: Int {
//    case uniforms
//}
//
//struct Uniforms {
//    var modelMatrix: float4x4
//    let modelViewProjectionMatrix: float4x4
//    var normalMatrix: float3x3
//    let cameraPosition: float3
//    let lightDirection: float3
//    let lightPosition: float3
//
//    init(modelMatrix: float4x4, viewMatrix: float4x4, projectionMatrix: float4x4,
//         cameraPosition: float3, lightDirection: float3, lightPosition: float3)
//    {
//        self.modelMatrix = modelMatrix
//        self.modelViewProjectionMatrix = projectionMatrix * viewMatrix * modelMatrix
//        self.normalMatrix = modelMatrix.normalMatrix
//        self.cameraPosition = cameraPosition
//        self.lightDirection = lightDirection
//        self.lightPosition = lightPosition
//    }
//}

class Material {
    var baseColor: MTLTexture?
    var metallic: MTLTexture?
    var roughness: MTLTexture?
    var normal: MTLTexture?
    var emissive: MTLTexture?
    
    func texture(for semantic: MDLMaterialSemantic, in material: MDLMaterial?, textureLoader: MTKTextureLoader) -> MTLTexture? {
        guard let materialProperty = material?.property(with: semantic) else { return nil }
        guard let sourceTexture = materialProperty.textureSamplerValue?.texture else { return nil }
        let wantMips = materialProperty.semantic != .tangentSpaceNormal
        let options: [MTKTextureLoader.Option : Any] = [ .generateMipmaps : wantMips ]
        return try? textureLoader.newTexture(texture: sourceTexture, options: options)
    }

    init(material sourceMaterial: MDLMaterial?, textureLoader: MTKTextureLoader) {
        baseColor = texture(for: .baseColor, in: sourceMaterial, textureLoader: textureLoader)
        metallic = texture(for: .metallic, in: sourceMaterial, textureLoader: textureLoader)
        roughness = texture(for: .roughness, in: sourceMaterial, textureLoader: textureLoader)
        normal = texture(for: .tangentSpaceNormal, in: sourceMaterial, textureLoader: textureLoader)
        emissive = texture(for: .emission, in: sourceMaterial, textureLoader: textureLoader)
    }
}

//class Node {
//    var modelMatrix: float4x4
//    let mesh: MTKMesh
//    let materials: [Material]
//
//    init(mesh: MTKMesh, materials: [Material]) {
//        assert(mesh.submeshes.count == materials.count)
//
//        modelMatrix = matrix_identity_float4x4
//        self.mesh = mesh
//        self.materials = materials
//    }
//}

class Renderer: NSObject, MTKViewDelegate {

    let device: MTLDevice
    let depthStencilState: MTLDepthStencilState
    let vertexDescriptor: MDLVertexDescriptor
    let commandQueue: MTLCommandQueue

    let lighting = Lighting()
    var nodes = [Node]()
    var fragmentUniforms = FragmentUniforms()
    var viewMatrix = matrix_identity_float4x4
    var cameraWorldPosition = float3(0, 0, 10)
    var lightWorldDirection = float3(0, 1, 0)
    var lightWorldPosition = float3(0, 5, -5)
    var time: Float = 0
    var uniforms = Uniforms()
    var fragmetnUniforms = FragmentUniforms()

    static var library: MTLLibrary!
    static var colorPixelFormat: MTLPixelFormat!
    static var depthStencilFormat: MTLPixelFormat!
    static var device: MTLDevice!
    static var sampleCount: Int!
    static var vertexDescriptor: MDLVertexDescriptor!

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


        let model = Model(name: "Ship", fragment: "fragment_main")

        nodes.append(model)
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

    }
    
    func updateScene(view: MTKView) {
        time += 1 / Float(view.preferredFramesPerSecond)
        let aspectRatio = Float(view.drawableSize.width / view.drawableSize.height)

        uniforms.projectionMatrix = float4x4(perspectiveProjectionFov: Float.pi / 3, aspectRatio: aspectRatio, nearZ: 0.1, farZ: 100)
        uniforms.viewMatrix = viewMatrix

        cameraWorldPosition = viewMatrix.inverse[3].xyz
        
        lightWorldPosition = cameraWorldPosition
        lightWorldDirection = normalize(cameraWorldPosition)
    }

    func draw(in view: MTKView) {
        guard let renderPassDescriptor = view.currentRenderPassDescriptor else { return }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        updateScene(view: view)

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
