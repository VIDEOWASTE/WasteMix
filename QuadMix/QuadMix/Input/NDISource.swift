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
            receiverLock.lock()
            let recv = receiver
            receiverLock.unlock()

            guard let recv = recv else { break }

            var frame = NDIVideoFrame()
            if NDIWrapper_CaptureVideo(recv, &frame, 100) {
                if frame.data != nil && frame.width > 0 && frame.height > 0 {
                    if let pb = createPixelBuffer(from: frame) {
                        lock.lock()
                        _latestPixelBuffer = pb
                        lock.unlock()
                    }
                }
                receiverLock.lock()
                let stillValid = receiver != nil
                receiverLock.unlock()
                if stillValid {
                    NDIWrapper_FreeVideoFrame(recv, &frame)
                }
            }
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

/// NDI Discovery using the NDI SDK finder.
@Observable
final class NDIDiscovery {
    private(set) var sources: [NDIDiscoveredSource] = []
    private var finder: NDIFinderRef?
    private var scanTimer: Timer?
    private var initialized = false

    init() {
        initialized = NDIWrapper_Initialize()
    }

    deinit {
        stopDiscovery()
        if initialized { NDIWrapper_Destroy() }
    }

    func startDiscovery() {
        guard initialized else { return }
        finder = NDIWrapper_CreateFinder()
        guard finder != nil else { return }

        scanTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollSources()
        }
        pollSources()
    }

    func stopDiscovery() {
        scanTimer?.invalidate()
        scanTimer = nil
        if let f = finder {
            NDIWrapper_DestroyFinder(f)
            finder = nil
        }
    }

    private func pollSources() {
        guard let finder = finder else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            var sourcePtr: UnsafeMutablePointer<NDISourceInfo>?
            let count = NDIWrapper_GetSources(finder, &sourcePtr)

            var found: [NDIDiscoveredSource] = []
            if let ptr = sourcePtr, count > 0 {
                for i in 0..<Int(count) {
                    let info = ptr[i]
                    let name = info.name.map { String(cString: $0) } ?? "Unknown"
                    let address = info.address.map { String(cString: $0) } ?? ""
                    found.append(NDIDiscoveredSource(name: name, address: address))
                }
                free(sourcePtr)
            }

            DispatchQueue.main.async {
                self?.sources = found
            }
        }
    }
}
