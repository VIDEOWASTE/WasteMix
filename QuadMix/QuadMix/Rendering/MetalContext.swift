import Metal
import MetalKit
import simd

final class MetalContext {
    static let shared = MetalContext()

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let textureConverter: TextureConverter
    var texturePool: TexturePool

    // Pipeline states
    let passthroughPipeline: MTLRenderPipelineState
    let passthroughOpacityPipeline: MTLRenderPipelineState
    let pipPipeline: MTLRenderPipelineState
    let colorCorrectionPipeline: MTLRenderPipelineState
    let wipePipeline: MTLRenderPipelineState
    let wipeABPipeline: MTLRenderPipelineState
    let dipPipeline: MTLRenderPipelineState
    var blendPipelines: [ChannelBlendMode: MTLRenderPipelineState] = [:]
    var effectPipelines: [String: MTLRenderPipelineState] = [:]
    let lumaKeyPipeline: MTLRenderPipelineState
    let chromaKeyPipeline: MTLRenderPipelineState

    // Shared vertex buffer for fullscreen quad
    let quadVertexBuffer: MTLBuffer

    private init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            fatalError("Failed to create Metal command queue")
        }
        self.commandQueue = queue

        self.textureConverter = TextureConverter(device: device)
        self.texturePool = TexturePool(
            device: device,
            width: Constants.defaultWidth,
            height: Constants.defaultHeight
        )

        // Fullscreen quad vertices
        let vertices: [Float] = [
            // position     // texCoord
            -1,  1,         0, 0,   // top-left
            -1, -1,         0, 1,   // bottom-left
             1, -1,         1, 1,   // bottom-right

            -1,  1,         0, 0,   // top-left
             1, -1,         1, 1,   // bottom-right
             1,  1,         1, 0,   // top-right
        ]
        guard let buffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Float>.size,
            options: .storageModeShared
        ) else {
            fatalError("Failed to create vertex buffer")
        }
        self.quadVertexBuffer = buffer

        let library: MTLLibrary
        do {
            library = try device.makeDefaultLibrary(bundle: .main)
        } catch {
            guard let lib = device.makeDefaultLibrary() else {
                fatalError("Failed to create Metal library: \(error)")
            }
            library = lib
        }

        let vertexFunc = library.makeFunction(name: "vertex_passthrough")!

        // Passthrough pipeline
        self.passthroughPipeline = Self.makePipeline(
            device: device, library: library,
            vertexFunction: vertexFunc,
            fragmentName: "fragment_passthrough"
        )

        // Passthrough with opacity (for base channel fader)
        self.passthroughOpacityPipeline = Self.makePipeline(
            device: device, library: library,
            vertexFunction: vertexFunc,
            fragmentName: "fragment_passthrough_opacity"
        )

        // PIP pipeline (alpha blending enabled so transparent pixels show through)
        self.pipPipeline = Self.makeBlendPipeline(
            device: device, library: library,
            vertexFunction: vertexFunc,
            fragmentName: "fragment_pip"
        )

        // Color correction pipeline
        self.colorCorrectionPipeline = Self.makePipeline(
            device: device, library: library,
            vertexFunction: vertexFunc,
            fragmentName: "color_correction"
        )

        // Wipe transition pipelines
        self.wipePipeline = Self.makePipeline(
            device: device, library: library,
            vertexFunction: vertexFunc,
            fragmentName: "transition_wipe"
        )
        self.wipeABPipeline = Self.makePipeline(
            device: device, library: library,
            vertexFunction: vertexFunc,
            fragmentName: "transition_wipe_ab"
        )

        // Dip transition pipeline
        self.dipPipeline = Self.makePipeline(
            device: device, library: library,
            vertexFunction: vertexFunc,
            fragmentName: "transition_dip"
        )

        // Blend mode pipelines
        for mode in ChannelBlendMode.allCases {
            let pipeline = Self.makeBlendPipeline(
                device: device, library: library,
                vertexFunction: vertexFunc,
                fragmentName: mode.metalFunctionName
            )
            blendPipelines[mode] = pipeline
        }

        // Effect pipelines
        let effectNames = ["effect_mirror_h", "effect_mirror_v", "effect_invert",
                           "effect_mosaic", "effect_strobe", "effect_rgb_split",
                           "effect_posterize", "effect_blur", "effect_solarize",
                           "effect_edges", "effect_datamosh", "effect_scanlines",
                           "effect_kaleidoscope", "effect_halftone", "effect_feedback"]
        for name in effectNames {
            effectPipelines[name] = Self.makePipeline(
                device: device, library: library,
                vertexFunction: vertexFunc, fragmentName: name
            )
        }

        // Keying pipelines
        self.lumaKeyPipeline = Self.makePipeline(
            device: device, library: library,
            vertexFunction: vertexFunc, fragmentName: "key_luma"
        )
        self.chromaKeyPipeline = Self.makePipeline(
            device: device, library: library,
            vertexFunction: vertexFunc, fragmentName: "key_chroma"
        )
    }

    private static func makePipeline(
        device: MTLDevice,
        library: MTLLibrary,
        vertexFunction: MTLFunction,
        fragmentName: String
    ) -> MTLRenderPipelineState {
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFunction
        desc.fragmentFunction = library.makeFunction(name: fragmentName)
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        do {
            return try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            fatalError("Failed to create pipeline for \(fragmentName): \(error)")
        }
    }

    private static func makeBlendPipeline(
        device: MTLDevice,
        library: MTLLibrary,
        vertexFunction: MTLFunction,
        fragmentName: String
    ) -> MTLRenderPipelineState {
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFunction
        desc.fragmentFunction = library.makeFunction(name: fragmentName)
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        // Enable alpha blending for wipe transitions
        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor = .one
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        do {
            return try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            fatalError("Failed to create blend pipeline for \(fragmentName): \(error)")
        }
    }

    func makeTexture(width: Int, height: Int, usage: MTLTextureUsage = [.renderTarget, .shaderRead]) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = usage
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }
}
