import CoreVideo
import Metal
import UIKit

final class ImageSource: FrameProvider {
    private var pixelBuffer: CVPixelBuffer?
    private(set) var isActive = false

    init(image: UIImage) {
        self.pixelBuffer = createPixelBuffer(from: image)
    }

    init(url: URL) {
        if let image = UIImage(contentsOfFile: url.path) {
            self.pixelBuffer = createPixelBuffer(from: image)
        }
    }

    init(color: (Float, Float, Float), width: Int = 1920, height: Int = 1080) {
        self.pixelBuffer = createSolidColorBuffer(
            red: color.0, green: color.1, blue: color.2,
            width: width, height: height
        )
    }

    var latestPixelBuffer: CVPixelBuffer? { pixelBuffer }

    func start() { isActive = true }
    func stop() { isActive = false }

    private func createPixelBuffer(from image: UIImage) -> CVPixelBuffer? {
        guard let cgImage = image.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height

        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)

        guard let pixelBuffer = pb else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }

    private func createSolidColorBuffer(
        red: Float, green: Float, blue: Float,
        width: Int, height: Int
    ) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)

        guard let pixelBuffer = pb else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddr = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let ptr = baseAddr.assumingMemoryBound(to: UInt8.self)

        let b = UInt8(min(max(blue * 255, 0), 255))
        let g = UInt8(min(max(green * 255, 0), 255))
        let r = UInt8(min(max(red * 255, 0), 255))

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                ptr[offset + 0] = b
                ptr[offset + 1] = g
                ptr[offset + 2] = r
                ptr[offset + 3] = 255
            }
        }

        return pixelBuffer
    }
}
