import CoreVideo
import Foundation

struct NDIDiscoveredSource: Equatable {
    let name: String
    let address: String
}

/// NDI receiver using the NDI SDK via the C wrapper.
final class NDISource: FrameProvider {
    private var _latestPixelBuffer: CVPixelBuffer?
    private let lock = NSLock()
    private let receiverLock = NSLock()
    private(set) var isActive = false

    let sourceName: String
    let ipAddress: String

    private var receiver: NDIReceiverRef?
    private var receiveQueue: DispatchQueue?
    /// Signaled by the receive loop when it has fully exited; `stop()` waits
    /// on this with a short timeout so we don't sleep blindly for 200ms on
    /// the calling thread (UI thread when changing channel sources).
    private let stoppedSemaphore = DispatchSemaphore(value: 0)

    // Pixel buffer pool for zero-alloc frame receive
    private var pixelBufferPool: CVPixelBufferPool?
    private var poolWidth: Int = 0
    private var poolHeight: Int = 0

    init(sourceName: String, ipAddress: String) {
        self.sourceName = sourceName
        self.ipAddress = ipAddress
    }

    var latestPixelBuffer: CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return _latestPixelBuffer
    }

    func start() {
        guard !sourceName.isEmpty else { return }
        // Guard against double-start — without this, calling start() twice
        // leaks the first receiver + cName/cAddr because the second call
        // overwrites them before stop() can free them.
        guard !isActive else { return }

        // Copy strings to C heap so they survive the entire NDI session
        let nameCopy = strdup(sourceName)
        let addrCopy = ipAddress.isEmpty ? nil : strdup(ipAddress)

        guard let nameCopy = nameCopy else { return }

        let recv = NDIWrapper_CreateReceiver(nameCopy, addrCopy)

        // Keep the C strings alive — store and free on stop()
        cName = nameCopy
        cAddr = addrCopy

        receiverLock.lock()
        receiver = recv
        receiverLock.unlock()

        guard recv != nil else {
            free(nameCopy)
            free(addrCopy)
            cName = nil
            cAddr = nil
            return
        }
        isActive = true

        let queue = DispatchQueue(label: "com.wastemix.ndi.receive")
        receiveQueue = queue
        queue.async { [weak self] in
            self?.receiveLoop()
        }
    }

    private var cName: UnsafeMutablePointer<CChar>?
    private var cAddr: UnsafeMutablePointer<CChar>?

    func stop() {
        guard isActive else { return }
        isActive = false
        receiveQueue = nil

        // Wait for the receive loop to actually exit, capped at 200ms so
        // we don't block UI longer than necessary. The loop signals the
        // semaphore on its last iteration; if it's already past its
        // capture call we'll just hit the timeout — which is fine.
        _ = stoppedSemaphore.wait(timeout: .now() + .milliseconds(200))

        // Destroy receiver under lock
        receiverLock.lock()
        let recv = receiver
        receiver = nil
        receiverLock.unlock()

        if let recv = recv {
            NDIWrapper_DestroyReceiver(recv)
        }

        // Free C string copies
        if let n = cName { free(n); cName = nil }
        if let a = cAddr { free(a); cAddr = nil }
    }

    private func receiveLoop() {
        while isActive {
            // Hold receiverLock across the entire capture + free pair.
            // Without this, stop() could destroy `recv` between our
            // capture and our free, calling FreeVideoFrame on a dangling
            // pointer (UAF). The lock makes stop() wait until our current
            // capture/free is finished before it nukes the receiver.
            receiverLock.lock()
            guard let recv = receiver else {
                receiverLock.unlock()
                break
            }

            var frame = NDIVideoFrame()
            let got = NDIWrapper_CaptureVideo(recv, &frame, 100)
            if got {
                if frame.data != nil && frame.width > 0 && frame.height > 0 {
                    if let pb = createPixelBuffer(from: frame) {
                        lock.lock()
                        _latestPixelBuffer = pb
                        lock.unlock()
                    }
                }
                NDIWrapper_FreeVideoFrame(recv, &frame)
            }
            receiverLock.unlock()
        }
        // Tell stop() that the loop has fully exited so it can proceed
        // to destroy the receiver without UI hitch.
        stoppedSemaphore.signal()
    }

    private func ensurePool(width: Int, height: Int) {
        if pixelBufferPool != nil && poolWidth == width && poolHeight == height { return }

        let poolAttrs: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 3
        ]
        let pixelAttrs: [String: Any] = [
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]

        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, poolAttrs as CFDictionary, pixelAttrs as CFDictionary, &pool)
        pixelBufferPool = pool
        poolWidth = width
        poolHeight = height
    }

    private func createPixelBuffer(from frame: NDIVideoFrame) -> CVPixelBuffer? {
        guard let data = frame.data else { return nil }
        let width = Int(frame.width)
        let height = Int(frame.height)
        let stride = Int(frame.stride)
        guard width > 0, height > 0, stride > 0 else { return nil }

        // Use pooled buffer (avoids malloc/free per frame)
        ensurePool(width: width, height: height)

        var pb: CVPixelBuffer?
        if let pool = pixelBufferPool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
        }
        if pb == nil {
            // Fallback if pool fails
            let attrs: [String: Any] = [
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)
        }

        guard let pixelBuffer = pb else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let destBase = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let destStride = CVPixelBufferGetBytesPerRow(pixelBuffer)

        // Fast copy — if strides match, single memcpy; otherwise row-by-row
        let copyLen = min(stride, destStride)
        if stride == destStride {
            memcpy(destBase, data, height * stride)
        } else {
            for y in 0..<height {
                memcpy(destBase.advanced(by: y * destStride), data.advanced(by: y * stride), copyLen)
            }
        }

        return pixelBuffer
    }
}

/// NDI Discovery via Apple's native Bonjour (`NetServiceBrowser`) instead
/// of NDI's built-in mDNS implementation. Why: NDI Advanced 6's built-in
/// discovery silently fails on Macs with many network interfaces (utun,
/// awdl, anpi, bridge, etc.) — the discovery thread either binds to a
/// wrong interface or never opens its UDP socket at all, and finders
/// return zero sources forever. `dns-sd -B _ndi._tcp` from the command
/// line finds the same sources on the same Mac instantly, so going
/// through `mDNSResponder` (what `dns-sd` uses) is reliable. Same code
/// path works on iOS / iPadOS / Catalyst because Bonjour is uniform
/// across Apple platforms.
///
/// We still call `NDIWrapper_Initialize()` at startup so the rest of the
/// NDI lib (send + receive) is ready to go — only the discovery side is
/// replaced.
@Observable
final class NDIDiscovery: NSObject {
    private(set) var sources: [NDIDiscoveredSource] = []
    private var initialized = false

    private let browser = NetServiceBrowser()
    private var resolving: Set<NetService> = []
    /// Resolved sources keyed by service name, so additions/removals
    /// don't produce duplicates if the same service shows up on multiple
    /// interfaces.
    private var byName: [String: NDIDiscoveredSource] = [:]

    override init() {
        super.init()
        initialized = NDIWrapper_Initialize()
    }

    deinit {
        stopDiscovery()
        if initialized { NDIWrapper_Destroy() }
    }

    func startDiscovery() {
        browser.delegate = self
        browser.searchForServices(ofType: "_ndi._tcp", inDomain: "local.")
    }

    func stopDiscovery() {
        browser.stop()
        for s in resolving { s.stop() }
        resolving.removeAll()
        byName.removeAll()
        sources = []
    }

    fileprivate func publish() {
        sources = byName.values.sorted { $0.name < $1.name }
    }
}

extension NDIDiscovery: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser,
                           didFind service: NetService,
                           moreComing: Bool) {
        service.delegate = self
        resolving.insert(service)
        service.resolve(withTimeout: 5.0)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser,
                           didRemove service: NetService,
                           moreComing: Bool) {
        byName.removeValue(forKey: service.name)
        resolving.remove(service)
        if !moreComing { publish() }
    }
}

extension NDIDiscovery: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        // NDI URL format is "host:port" — NDI's recv API accepts either
        // hostnames or IPs. Hostname is more robust if the device's IP
        // changes mid-session.
        guard let host = sender.hostName else {
            resolving.remove(sender)
            return
        }
        let url = "\(host):\(sender.port)"
        byName[sender.name] = NDIDiscoveredSource(name: sender.name, address: url)
        resolving.remove(sender)
        publish()
    }

    func netService(_ sender: NetService,
                    didNotResolve errorDict: [String: NSNumber]) {
        resolving.remove(sender)
    }
}
