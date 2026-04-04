import Metal

final class TexturePool {
    private let device: MTLDevice
    private var available: [MTLTexture] = []
    private var width: Int
    private var height: Int

    init(device: MTLDevice, width: Int, height: Int, count: Int = 4) {
        self.device = device
        self.width = width
        self.height = height
        for _ in 0..<count {
            if let tex = Self.createTexture(device: device, width: width, height: height) {
                available.append(tex)
            }
        }
    }

    func checkout() -> MTLTexture? {
        if let tex = available.popLast() {
            return tex
        }
        return Self.createTexture(device: device, width: width, height: height)
    }

    func returnTexture(_ texture: MTLTexture) {
        if texture.width == width && texture.height == height {
            available.append(texture)
        }
    }

    func resize(width: Int, height: Int) {
        self.width = width
        self.height = height
        available.removeAll()
    }

    private static func createTexture(device: MTLDevice, width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }
}
