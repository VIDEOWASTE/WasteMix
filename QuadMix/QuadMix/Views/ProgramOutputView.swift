import SwiftUI
import MetalKit

struct ProgramOutputView: UIViewRepresentable {
    let renderEngine: RenderEngine

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MetalContext.shared.device
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.autoResizeDrawable = true
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        // THIS MTKView drives the entire render loop.
        // isPaused = false means its internal display link fires draw(in:) every frame.
        // The RenderEngine (as MTKViewDelegate) does all compositing in that callback.
        // This guarantees currentDrawable is always valid when we render.
        view.isPaused = false
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false

        // RenderEngine is the delegate - its draw(in:) is the render loop
        view.delegate = renderEngine

        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        // Keep delegate current
        view.delegate = renderEngine
    }
}
