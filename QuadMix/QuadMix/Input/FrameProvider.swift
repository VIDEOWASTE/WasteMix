import CoreVideo
import Metal

protocol FrameProvider: AnyObject {
    var latestPixelBuffer: CVPixelBuffer? { get }
    var latestTexture: MTLTexture? { get }
    var isActive: Bool { get }
    func start()
    func stop()
}

extension FrameProvider {
    var latestTexture: MTLTexture? {
        guard let pb = latestPixelBuffer else { return nil }
        return MetalContext.shared.textureConverter.texture(from: pb)
    }
}
