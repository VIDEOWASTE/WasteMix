import SwiftUI
import MetalKit

struct PreviewView: UIViewRepresentable {
    let device: MTLDevice
    var textureProvider: (() -> MTLTexture?)?

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = device
        // Continuous rendering at 30fps for real-time preview
        view.isPaused = false
        view.preferredFramesPerSecond = 30
        view.enableSetNeedsDisplay = false
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.delegate = context.coordinator
        view.autoResizeDrawable = true
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.textureProvider = textureProvider
    }

    func makeCoordinator() -> PreviewCoordinator {
        PreviewCoordinator(device: device)
    }

    class PreviewCoordinator: NSObject, MTKViewDelegate {
        let device: MTLDevice
        let commandQueue: MTLCommandQueue?
        let pipelineState: MTLRenderPipelineState
        var textureProvider: (() -> MTLTexture?)?

        init(device: MTLDevice) {
            self.device = device
            self.commandQueue = device.makeCommandQueue()
            self.pipelineState = MetalContext.shared.passthroughPipeline
            super.init()
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let commandBuffer = commandQueue?.makeCommandBuffer() else { return }

            let desc = MTLRenderPassDescriptor()
            desc.colorAttachments[0].texture = drawable.texture
            desc.colorAttachments[0].loadAction = .clear
            desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            desc.colorAttachments[0].storeAction = .store

            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc) else { return }

            // If we have a texture from the render engine, draw it
            if let texture = textureProvider?() {
                encoder.setRenderPipelineState(pipelineState)
                encoder.setVertexBuffer(MetalContext.shared.quadVertexBuffer, offset: 0, index: 0)
                encoder.setFragmentTexture(texture, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            }
            // Otherwise the clear-to-black loadAction shows a black frame

            encoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
