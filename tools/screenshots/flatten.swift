// Used by tools/screenshots/shoot.sh.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
// Re-encodes each PNG as opaque RGB (no alpha channel), keeping pixels and the sRGB profile.
for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { print("read fail \(path)"); exit(1) }
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: img.width, height: img.height))
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
    let out = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, out, nil)
    guard CGImageDestinationFinalize(dest) else { print("write fail \(path)"); exit(1) }
    print("flattened \(url.lastPathComponent)")
}
