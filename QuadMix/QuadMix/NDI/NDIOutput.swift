import Metal

/// Sends video frames as an NDI source on the network.
/// Uses shared-memory textures for zero-copy GPU→CPU readback.
final class NDIOutput {
    private var sender: NDISenderRef?
    /// Guards `sender` and `isActive` against the
    /// Metal-completion-thread → sendQueue → stop()-thread race. Also held
    /// across NDI calls so a stop() can't free the sender mid-send.
    private let senderLock = NSLock()
    private(set) var isActive = false
    let name: String

    // Three malloc'd buffers cycled per send. Combined with the dedicated
    // serial sendQueue below, this lets NDIWrapper_SendVideo run off-thread
    // without racing on a single buffer when frames pile up.
    private static let ringCapacity = 3
    private var bufferRing: [UnsafeMutableRawPointer] = []
    private var bufferRingByteCount: Int = 0
    private var bufferIndex: Int = 0

    /// Dedicated serial queue for NDI sends — keeps the Metal completion
    /// thread from blocking on network/encode work, which was a major source
    /// of the laggy NDI broadcast.
    private let sendQueue = DispatchQueue(label: "com.wastemix.ndi.\(UUID().uuidString)", qos: .userInitiated)

    init(name: String) {
        self.name = name
    }

    func start() {
        senderLock.lock(); defer { senderLock.unlock() }
        guard !isActive else { return }
        sender = NDIWrapper_CreateSender(name)
        isActive = sender != nil
    }

    func stop() {
        // Order matters: flip isActive first so any in-flight Metal-completion
        // calls early-out instead of dispatching new sends. Then drain the
        // sendQueue so any already-dispatched block finishes (under the
        // sender lock, so it sees a still-valid sender). Only then destroy
        // the sender and free the buffer ring.
        senderLock.lock()
        isActive = false
        senderLock.unlock()

        // Drain the queue — any in-flight block runs to completion.
        sendQueue.sync { }

        senderLock.lock()
        if let s = sender { NDIWrapper_DestroySender(s) }
        sender = nil
        // Buffers can only be freed after the queue is drained AND the
        // sender is destroyed — the NDI lib pins the most recently
        // submitted buffer until the next send (or destroy).
        for buf in bufferRing { free(buf) }
        bufferRing.removeAll()
        bufferRingByteCount = 0
        senderLock.unlock()
    }

    /// Send a shared-memory Metal texture as an NDI BGRA frame.
    /// The texture MUST have storageMode = .shared for this to work without stalls.
    /// Caller is on a Metal completion thread; we do the GPU→CPU read here so
    /// the readback texture is free for the next frame's blit, then dispatch
    /// the actual NDI send onto our private serial queue.
    func sendTexture(_ texture: MTLTexture) {
        // Snapshot active state — cheap fast-path check before locking.
        guard isActive else { return }

        let width = texture.width
        let height = texture.height
        let bytesPerRow = width * 4
        let totalBytes = height * bytesPerRow

        senderLock.lock()
        // Re-check under the lock; stop() may have flipped this between
        // the fast-path read and now.
        guard isActive, sender != nil else {
            senderLock.unlock()
            return
        }

        // Lazy-init the buffer ring whenever the size changes
        if bufferRing.isEmpty || bufferRingByteCount != totalBytes {
            for buf in bufferRing { free(buf) }
            bufferRing.removeAll()
            for _ in 0..<Self.ringCapacity {
                if let p = malloc(totalBytes) { bufferRing.append(p) }
            }
            bufferRingByteCount = totalBytes
            bufferIndex = 0
        }
        guard !bufferRing.isEmpty else {
            senderLock.unlock()
            return
        }

        let buf = bufferRing[bufferIndex]
        bufferIndex = (bufferIndex + 1) % bufferRing.count
        senderLock.unlock()

        // Synchronous CPU read while we still hold the readback texture
        // (called from Metal completion handler so the blit is done).
        texture.getBytes(buf, bytesPerRow: bytesPerRow,
                         from: MTLRegion(origin: MTLOrigin(), size: MTLSize(width: width, height: height, depth: 1)),
                         mipmapLevel: 0)

        // Hand off send to our own queue. We use the async API: the NDI lib
        // pins our buffer until the next async send fires, which is why we
        // keep a ring of 3 — by the time we cycle back to buf[0], buf[1] and
        // buf[2] have each been async-sent and released.
        sendQueue.async { [weak self] in
            guard let self = self else { return }
            // Re-check under the sender lock so stop() (which acquires the
            // same lock) can't race us into a destroyed sender.
            self.senderLock.lock()
            defer { self.senderLock.unlock() }
            guard self.isActive, let s = self.sender else { return }
            NDIWrapper_SendVideoAsync(s, buf.assumingMemoryBound(to: UInt8.self),
                                      Int32(width), Int32(height), Int32(bytesPerRow))
        }
    }
}
