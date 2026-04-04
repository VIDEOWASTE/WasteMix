import CoreVideo
import Metal
import UIKit

final class PatternGeneratorSource: FrameProvider {
    private var pixelBuffer: CVPixelBuffer?
    private(set) var isActive = false

    init(pattern: PatternType, width: Int = 1920, height: Int = 1080) {
        switch pattern {
        case .colorBars:
            pixelBuffer = generateColorBars(width: width, height: height)
        case .gradient:
            pixelBuffer = generateGradient(width: width, height: height)
        case .checkerboard:
            pixelBuffer = generateCheckerboard(width: width, height: height)
        }
    }

    var latestPixelBuffer: CVPixelBuffer? { pixelBuffer }

    func start() { isActive = true }
    func stop() { isActive = false }

    private func makeBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [kCVPixelBufferMetalCompatibilityKey as String: true]
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)
        return pb
    }

    private func generateColorBars(width: Int, height: Int) -> CVPixelBuffer? {
        guard let pb = makeBuffer(width: width, height: height) else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        // SMPTE color bars: White, Yellow, Cyan, Green, Magenta, Red, Blue
        let bars: [(UInt8, UInt8, UInt8)] = [
            (255, 255, 255), (255, 255, 0), (0, 255, 255), (0, 255, 0),
            (255, 0, 255), (255, 0, 0), (0, 0, 255)
        ]
        let barWidth = width / bars.count

        for y in 0..<height {
            for x in 0..<width {
                let barIndex = min(x / barWidth, bars.count - 1)
                let (r, g, b) = bars[barIndex]
                let offset = y * bytesPerRow + x * 4
                ptr[offset + 0] = b   // BGRA
                ptr[offset + 1] = g
                ptr[offset + 2] = r
                ptr[offset + 3] = 255
            }
        }
        return pb
    }

    private func generateGradient(width: Int, height: Int) -> CVPixelBuffer? {
        guard let pb = makeBuffer(width: width, height: height) else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                let xf = UInt8(Float(x) / Float(width) * 255)
                let yf = UInt8(Float(y) / Float(height) * 255)
                ptr[offset + 0] = UInt8(255 - yf)  // B
                ptr[offset + 1] = yf                 // G
                ptr[offset + 2] = xf                 // R
                ptr[offset + 3] = 255
            }
        }
        return pb
    }

    private func generateCheckerboard(width: Int, height: Int) -> CVPixelBuffer? {
        guard let pb = makeBuffer(width: width, height: height) else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        let squareSize = 64

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                let isWhite = ((x / squareSize) + (y / squareSize)) % 2 == 0
                let val: UInt8 = isWhite ? 255 : 0
                ptr[offset + 0] = val
                ptr[offset + 1] = val
                ptr[offset + 2] = val
                ptr[offset + 3] = 255
            }
        }
        return pb
    }
}
