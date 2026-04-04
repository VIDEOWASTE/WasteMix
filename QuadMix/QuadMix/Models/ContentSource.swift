import Foundation
import AVFoundation

enum PatternType: String, CaseIterable, Identifiable, Codable {
    case colorBars
    case gradient
    case checkerboard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .colorBars: return "Color Bars"
        case .gradient: return "Gradient"
        case .checkerboard: return "Checkerboard"
        }
    }
}

enum ContentSource: Identifiable {
    case camera(position: AVCaptureDevice.Position)
    case mediaFile(url: URL)
    case image(url: URL)
    case solidColor(red: Float, green: Float, blue: Float)
    case pattern(PatternType)
    case ndi(sourceName: String, ipAddress: String)

    var id: String {
        switch self {
        case .camera(let pos):
            return "camera_\(pos.rawValue)"
        case .mediaFile(let url):
            return "media_\(url.lastPathComponent)"
        case .image(let url):
            return "image_\(url.lastPathComponent)"
        case .solidColor(let r, let g, let b):
            return "color_\(r)_\(g)_\(b)"
        case .pattern(let type):
            return "pattern_\(type.rawValue)"
        case .ndi(let name, _):
            return "ndi_\(name)"
        }
    }

    var displayName: String {
        switch self {
        case .camera(let pos):
            return pos == .front ? "Front Camera" : "Back Camera"
        case .mediaFile(let url):
            return url.lastPathComponent
        case .image(let url):
            return url.lastPathComponent
        case .solidColor:
            return "Solid Color"
        case .pattern(let type):
            return type.displayName
        case .ndi(let name, _):
            return "NDI: \(name)"
        }
    }
}
