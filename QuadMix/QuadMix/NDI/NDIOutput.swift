import Metal

/// Sends video frames as an NDI source on the network.
/// Uses shared-memory textures for zero-copy GPU→CPU readback.
final class NDIOutput {
    private var sender: NDISenderRef?
    private(set) var isActive = false
    let name: String

    // Three malloc'd buffers cycled per send. Combined with the dedicated
    // serial sendQueue below, this lets NDIWrapper_SendVideo run off-thread
    // without racing on a single buffer when frames pile up.
    private static let bufferRingSize = 3
    private var bufferRing: [UnsafeMutableRawPointer] = []
    private var bufferRingSize: Int = 0
    private var bufferIndex: Int = 0

    /// Dedicated serial queue for NDI sends — keeps the Metal completion
    /// thread from blocking on network/encode work, which was a major source
    /// of the laggy NDI broadcast.
    private let sendQueue = DispatchQueue(label: "com.wastemix.ndi.\(UUID().uuidString)", qos: .userInitiated)

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
        // Drain the queue then free buffers
        sendQueue.sync { /* serialize after any in-flight send */ }
        for buf in bufferRing { free(buf) }
        bufferRing.removeAll()
        bufferRingSize = 0
    }

    /// Send a shared-memory Metal texture as an NDI BGRA frame.
    /// The texture MUST have storageMode = .shared for this to work without stalls.
    /// Caller is on a Metal completion thread; we do the GPU→CPU read here so
    /// the readback texture is free for the next frame's blit, then dispatch
    /// the actual NDI send onto our private serial queue.
    func sendTexture(_ texture: MTLTexture) {
        guard isActive, sender != nil else { return }

        let width = texture.width
        let height = texture.height
        let bytesPerRow = width * 4
        let totalBytes = height * bytesPerRow

        // Lazy-init the buffer ring whenever the size changes
        if bufferRing.isEmpty || bufferRingSize != totalBytes {
            for buf in bufferRing { free(buf) }
            bufferRing.removeAll()
            for _ in 0..<Self.bufferRingSize {
                if let p = malloc(totalBytes) { bufferRing.append(p) }
            }
            bufferRingSize = totalBytes
            bufferIndex = 0
        }
        guard !bufferRing.isEmpty else { return }

        let buf = bufferRing[bufferIndex]
        bufferIndex = (bufferIndex + 1) % bufferRing.count

        // Synchronous CPU read while we still hold the readback texture
        // (called from Metal completion handler so the blit is done).
        texture.getBytes(buf, bytesPerRow: bytesPerRow,
                         from: MTLRegion(origin: MTLOrigin(), size: MTLSize(width: width, height: height, depth: 1)),
                         mipmapLevel: 0)

        // Hand off send to our own queue. We use the async API: the NDI lib
        // pins our buffer until the next async send fires, which is why we
        // keep a ring of 3 — by the time we cycle back to buf[0], buf[1] and
        // buf[2] have each been async-sent and released.
        let s = sender
        sendQueue.async {
            guard let s = s else { return }
            NDIWrapper_SendVideoAsync(s, buf.assumingMemoryBound(to: UInt8.self),
                                      Int32(width), Int32(height), Int32(bytesPerRow))
        }
    }
}
