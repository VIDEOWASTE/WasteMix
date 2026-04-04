import Foundation
import CoreGraphics

struct NormalizedPoint: Codable, Equatable {
    var x: Float
    var y: Float

    static let topLeft = NormalizedPoint(x: 0, y: 0)
    static let topRight = NormalizedPoint(x: 1, y: 0)
    static let bottomLeft = NormalizedPoint(x: 0, y: 1)
    static let bottomRight = NormalizedPoint(x: 1, y: 1)
}

/// Output destination type
enum OutputDestination: String, CaseIterable, Codable, Identifiable {
    case none
    case display
    case ndi
    case syphon
    case fullscreen

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .none: return "None"
        case .display: return "Display"
        case .ndi: return "NDI"
        case .syphon: return "Syphon"
        case .fullscreen: return "Fullscreen"
        }
    }
    var icon: String {
        switch self {
        case .none: return "xmark.circle"
        case .display: return "display"
        case .ndi: return "network"
        case .syphon: return "arrow.triangle.branch"
        case .fullscreen: return "arrow.up.left.and.arrow.down.right"
        }
    }
}

/// A mesh warp node — part of a grid of draggable control points
struct WarpNode: Identifiable, Codable {
    var id = UUID()
    var x: Float  // 0-1 position on the output
    var y: Float
}

/// Mesh warp grid for a slice — NxM grid of draggable nodes
struct MeshWarp: Codable {
    var cols: Int = 1
    var rows: Int = 1
    var nodes: [WarpNode] = []

    var isDefault: Bool { nodes.isEmpty }

    /// Generate default grid — starts as 1x1 (4 corner nodes)
    mutating func generateGrid() {
        nodes.removeAll()
        for r in 0...rows {
            for c in 0...cols {
                nodes.append(WarpNode(
                    x: Float(c) / Float(cols),
                    y: Float(r) / Float(rows)
                ))
            }
        }
    }

    /// Add one subdivision level (adds one row + one col each time)
    mutating func subdivide() {
        // Preserve existing node positions by interpolating into new grid
        let oldCols = cols
        let oldRows = rows
        let oldNodes = nodes

        cols = min(cols + 1, 16)
        rows = min(rows + 1, 16)

        // Generate fresh grid, then blend in old positions where they map
        nodes.removeAll()
        for r in 0...rows {
            for c in 0...cols {
                // Find corresponding position in old grid
                let oldC = Float(c) / Float(cols) * Float(oldCols)
                let oldR = Float(r) / Float(rows) * Float(oldRows)

                // If this maps exactly to an old node, use its position
                let ci = Int(round(oldC))
                let ri = Int(round(oldR))
                if !oldNodes.isEmpty && ci <= oldCols && ri <= oldRows &&
                   abs(oldC - Float(ci)) < 0.01 && abs(oldR - Float(ri)) < 0.01 {
                    let oldIdx = ri * (oldCols + 1) + ci
                    if oldIdx < oldNodes.count {
                        nodes.append(oldNodes[oldIdx])
                        continue
                    }
                }
                // Otherwise, default grid position
                nodes.append(WarpNode(
                    x: Float(c) / Float(cols),
                    y: Float(r) / Float(rows)
                ))
            }
        }
    }

    /// Get node index at grid position
    func nodeIndex(col: Int, row: Int) -> Int {
        return row * (cols + 1) + col
    }

    /// Reset to 1x1 grid (4 corner nodes at default positions)
    mutating func reset() {
        cols = 1
        rows = 1
        generateGrid()
    }
}

struct MaskRect: Identifiable, Codable {
    var id = UUID()
    var x: Float = 0.25; var y: Float = 0.25
    var w: Float = 0.5; var h: Float = 0.5
}

struct OutputSlice: Identifiable, Codable {
    var id = UUID()
    var name: String = "Slice"
    var enabled: Bool = true

    // Source region (0-1 in program)
    var sourceX: Float = 0; var sourceY: Float = 0
    var sourceW: Float = 1; var sourceH: Float = 1

    // Transform (0-1 normalized to screen)
    var outputX: Float = 0; var outputY: Float = 0
    var outputW: Float = 1; var outputH: Float = 1
    var rotation: Float = 0  // degrees

    // Corner pin warp
    var warpTL: NormalizedPoint = .topLeft
    var warpTR: NormalizedPoint = .topRight
    var warpBL: NormalizedPoint = .bottomLeft
    var warpBR: NormalizedPoint = .bottomRight

    var isWarped: Bool {
        warpTL != .topLeft || warpTR != .topRight || warpBL != .bottomLeft || warpBR != .bottomRight
    }

    // Mesh warp
    var meshWarpEnabled: Bool = false
    var meshWarp = MeshWarp()

    // Edge blending
    var blendLeft: Float = 0; var blendRight: Float = 0
    var blendTop: Float = 0; var blendBottom: Float = 0
    var blendGamma: Float = 2.2

    var hasBlending: Bool {
        blendLeft > 0 || blendRight > 0 || blendTop > 0 || blendBottom > 0
    }

    var brightness: Float = 0; var contrast: Float = 1
    var masks: [MaskRect] = []

    mutating func resetWarp() {
        warpTL = .topLeft; warpTR = .topRight; warpBL = .bottomLeft; warpBR = .bottomRight
        meshWarp = MeshWarp()
    }

    mutating func resetBlend() {
        blendLeft = 0; blendRight = 0; blendTop = 0; blendBottom = 0
    }

    mutating func initMeshWarp() {
        if meshWarp.nodes.isEmpty { meshWarp.generateGrid() }
    }
}

struct OutputScreen: Identifiable, Codable {
    var id = UUID()
    var name: String = "Output 1"
    var enabled: Bool = true

    // Destination
    var destination: OutputDestination = .display
    var displayID: UInt32? = nil
    var width: Int = 1920; var height: Int = 1080

    // Slices
    var slices: [OutputSlice] = [OutputSlice()]

    // NDI
    var ndiOutputEnabled: Bool = false
    var ndiOutputName: String = "WasteMix Output"

    // Test pattern
    var showTestPattern: Bool = false
    var testPatternType: TestPatternType = .grid
}

enum TestPatternType: String, CaseIterable, Codable, Identifiable {
    case grid; case colorBars; case white; case crosshatch; case gradient
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .grid: return "Grid"; case .colorBars: return "Color Bars"
        case .white: return "White"; case .crosshatch: return "Crosshatch"; case .gradient: return "Gradient"
        }
    }
}

enum CanvasEditMode: String, CaseIterable {
    case transform
    case mesh
}

@Observable
final class OutputConfig {
    var screens: [OutputScreen] = [OutputScreen()]
    var globalNDIOutput: Bool = true
    var globalNDIName: String = "WasteMix Program"
    var isAdvancedOutputOpen: Bool = false
    var selectedScreenIndex: Int = 0
    var selectedSliceIndex: Int = 0
    var selectedNodeIndex: Int? = nil
    var showMeshWarp: Bool = false
    var canvasEditMode: CanvasEditMode = .transform

    func addScreen() {
        screens.append(OutputScreen(name: "Output \(screens.count + 1)"))
    }

    func addSlice(to screenIndex: Int) {
        guard screenIndex < screens.count else { return }
        var slice = OutputSlice()
        slice.name = "Slice \(screens[screenIndex].slices.count + 1)"
        screens[screenIndex].slices.append(slice)
    }

    func removeSlice(screenIndex: Int, sliceIndex: Int) {
        guard screenIndex < screens.count,
              sliceIndex < screens[screenIndex].slices.count,
              screens[screenIndex].slices.count > 1 else { return }
        screens[screenIndex].slices.remove(at: sliceIndex)
        // Clamp selected slice index to valid range
        if selectedSliceIndex >= screens[screenIndex].slices.count {
            selectedSliceIndex = max(0, screens[screenIndex].slices.count - 1)
        }
    }
}
