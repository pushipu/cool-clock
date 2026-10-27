import Foundation
import Metal
import simd

final class CloudRenderer {
    let scene: CloudScene
    private let pipeline: MTLRenderPipelineState

    private struct Uniforms {
        var size: SIMD4<Float>
        var state: SIMD4<UInt32>
    }
    private struct Rectangle {
        var bounds: SIMD4<Float>
        var blend: SIMD4<Float>
    }

    init(device: MTLDevice, bundle: Bundle) throws {
        scene = try CloudScene(bundle: bundle)
        guard let url = bundle.url(forResource: "Clouds", withExtension: "metal") else {
            throw NSError(domain: "CoolClock", code: 52, userInfo: [NSLocalizedDescriptionKey: "Clouds.metal is missing"])
        }
        let library = try device.makeLibrary(source: String(contentsOf: url, encoding: .utf8), options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "cloudVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "cloudFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }

    func encode(commandBuffer: MTLCommandBuffer, target: MTLTexture, textures: [MTLTexture], seconds: Double) throws {
        guard textures.count == 3, textures.allSatisfy({ $0.pixelFormat == .r8Unorm }), target.pixelFormat == .bgra8Unorm else {
            throw NSError(domain: "CoolClock", code: 53, userInfo: [NSLocalizedDescriptionKey: "Invalid cloud texture formats"])
        }
        let frame = scene.frame(at: seconds)
        let width = Float(target.width), height = Float(target.height)
        let sourceAspect = Float(textures[0].width) / Float(textures[0].height)
        let targetAspect = width / height
        let uvScale = SIMD2(min(1, targetAspect / sourceAspect), min(1, sourceAspect / targetAspect))
        var uniforms = Uniforms(size: SIMD4(width, height, uvScale.x, uvScale.y),
                                state: SIMD4(UInt32(frame.background), UInt32(frame.coverage.count + frame.windows.count), 0, 0))
        func bounds(_ rectangle: SIMD4<Double>) -> SIMD4<Float> {
            let scaled = rectangle * SIMD4(Double(target.width) / 984, Double(target.height) / 718,
                                          Double(target.width) / 984, Double(target.height) / 718)
            return SIMD4(Float(scaled.x.rounded(.toNearestOrEven)), Float(scaled.y.rounded(.toNearestOrEven)),
                         Float(scaled.z.rounded(.toNearestOrEven)), Float(scaled.w.rounded(.toNearestOrEven)))
        }
        var rectangles = frame.coverage.map { Rectangle(bounds: bounds($0), blend: SIMD4(Float(frame.takeoverTarget!), Float(frame.takeoverTarget!), 0, 0)) }
        rectangles += frame.windows.map { Rectangle(bounds: bounds($0.rectangle), blend: SIMD4(Float($0.before), Float($0.after), Float($0.weight), 0)) }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            throw NSError(domain: "CoolClock", code: 54, userInfo: [NSLocalizedDescriptionKey: "Unable to encode cloud frame"])
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        rectangles.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 1) }
        frame.luts.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 2) }
        for (index, texture) in textures.enumerated() { encoder.setFragmentTexture(texture, index: index) }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
