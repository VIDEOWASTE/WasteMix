import Metal

/// Sends video frames as an NDI source on the network.
/// Uses shared-memory textures for zero-copy GPU→CPU readback.
final class NDIOutput {
    private var sender: NDISenderRef?
    private(set) var isActive = false
    let name: String

    // Pre-allocated shared-memory buffer for GPU→CPU readback (no per-frame alloc)
    private var readbackBuffer: UnsafeMutableRawPointer?
    private var readbackSize: Int = 0
    private var lastWidth: Int = 0
    private var lastHeight: Int = 0

    init(name: String) {
        self.name = name
    }

    func start() {
        guard !isActive else { return }
        sender = NDIWrapper_CreateSender(name)
        isActive = sender != nil
    }

    func stop() {
        if let s = sender { NDIWrapper_DestroySender(s) }
        sender = nil
        isActive = false
        if let buf = readbackBuffer {
            free(buf)
            readbackBuffer = nil
        }
    }

    /// Send a shared-memory Metal texture as an NDI BGRA frame.
    /// The texture MUST have storageMode = .shared for this to work without stalls.
    func sendTexture(_ texture: MTLTexture) {
        guard isActive, let sender = sender else { return }

        let width = texture.width
        let height = texture.height
        let bytesPerRow = width * 4
        let totalBytes = height * bytesPerRow

        // Ensure readback buffer is allocated
        if readbackBuffer == nil || readbackSize != totalBytes {
            if let old = readbackBuffer { free(old) }
            readbackBuffer = malloc(totalBytes)
            readbackSize = totalBytes
            lastWidth = width
            lastHeight = height
        }

        guard let buf = readbackBuffer else { return }

        // Read from shared texture — this is fast because the texture is already in CPU-accessible memory
        texture.getBytes(buf, bytesPerRow: bytesPerRow,
                         from: MTLRegion(origin: MTLOrigin(), size: MTLSize(width: width, height: height, depth: 1)),
                         mipmapLevel: 0)

        NDIWrapper_SendVideo(sender, buf.assumingMemoryBound(to: UInt8.self),
                             Int32(width), Int32(height), Int32(bytesPerRow))
    }
}
