import SwiftUI
import MetalKit

/// Fullscreen live output view — shows the rendered program output texture.
/// Fills the entire selected display with no title bar.
struct OutputDisplayView: View {
    let renderEngine: RenderEngine
    let screenIndex: Int
    @Environment(\.dismissWindow) private var dismissWindow

    private var isEnabled: Bool {
        let config = renderEngine.outputConfig
        guard screenIndex < config.screens.count else { return false }
        return config.screens[screenIndex].enabled
            && config.screens[screenIndex].destination != .none
    }

    var body: some View {
        GeometryReader { _ in
            OutputMetalView(
                device: MetalContext.shared.device,
                renderEngine: renderEngine,
                screenIndex: screenIndex
            )
            .ignoresSafeArea()
        }
        .background(Color.black)
        .ignoresSafeArea()
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
        .onChange(of: isEnabled) { _, enabled in
            if !enabled {
                dismissWindow(id: "liveOutput")
            }
        }
    }
}

/// UIViewRepresentable wrapping an MTKView that draws the output screen texture at 60fps.
/// On Mac Catalyst, positions the window to fill the target display.
struct OutputMetalView: UIViewRepresentable {
    let device: MTLDevice
    let renderEngine: RenderEngine
    let screenIndex: Int

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = device
        view.isPaused = false
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.delegate = context.coordinator
        view.autoResizeDrawable = true
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        context.coordinator.metalView = view

        // Position on target display after view is in the hierarchy
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            context.coordinator.fillTargetDisplay()
        }

        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.renderEngine = renderEngine
        context.coordinator.screenIndex = screenIndex
    }

    func makeCoordinator() -> OutputDisplayCoordinator {
        OutputDisplayCoordinator(device: device, renderEngine: renderEngine, screenIndex: screenIndex)
    }

    class OutputDisplayCoordinator: NSObject, MTKViewDelegate {
        let device: MTLDevice
        let commandQueue: MTLCommandQueue?
        let pipelineState: MTLRenderPipelineState
        var renderEngine: RenderEngine
        var screenIndex: Int
        weak var metalView: MTKView?

        init(device: MTLDevice, renderEngine: RenderEngine, screenIndex: Int) {
            self.device = device
            // Share the engine's command queue so reads of programTexture /
            // screen textures are properly serialized with engine writes.
            // A separate queue produced tearing on the live output.
            self.commandQueue = MetalContext.shared.commandQueue
            self.pipelineState = MetalContext.shared.passthroughPipeline
            self.renderEngine = renderEngine
            self.screenIndex = screenIndex
            super.init()
        }

        /// Position this window on the target display, then enter true fullscreen
        func fillTargetDisplay() {
            #if targetEnvironment(macCatalyst)
            guard let view = metalView,
                  let windowScene = view.window?.windowScene else { return }

            let config = renderEngine.outputConfig
            guard screenIndex < config.screens.count else { return }
            let screen = config.screens[screenIndex]

            // Hide title bar
            windowScene.titlebar?.titleVisibility = .hidden
            windowScene.titlebar?.toolbar = nil

            // Remove size restrictions
            windowScene.sizeRestrictions?.minimumSize = CGSize(width: 100, height: 100)
            windowScene.sizeRestrictions?.maximumSize = CGSize(width: 10000, height: 10000)

            if let targetDisplayID = screen.displayID {
                let bounds = CGDisplayBounds(targetDisplayID)
                guard bounds.width > 0 else { return }

                // First position on the target display
                let geo = UIWindowScene.GeometryPreferences.Mac(
                    systemFrame: CGRect(
                        x: bounds.origin.x,
                        y: bounds.origin.y,
                        width: bounds.width,
                        height: bounds.height
                    )
                )
                windowScene.requestGeometryUpdate(geo) { _ in }
            }

            // Enter true fullscreen via NSApplication.shared.windows
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.enterNativeFullscreen()
            }
            #endif
        }

        #if targetEnvironment(macCatalyst)
        private func enterNativeFullscreen() {
            // Get NSApplication class
            guard let nsAppClass = NSClassFromString("NSApplication") else { return }
            let nsAppObj = nsAppClass.value(forKeyPath: "sharedApplication") as AnyObject

            // Get NSApplication.shared.windows
            guard let windows = nsAppObj.value(forKey: "windows") as? [AnyObject] else { return }

            // Find the window for our output view by matching the UIWindow
            guard let uiWindow = metalView?.window else { return }
            let uiFrame = uiWindow.frame

            for nsWindow in windows {
                // Match by checking if the NSWindow's frame overlaps with our UIWindow
                guard let frame = nsWindow.value(forKey: "frame") as? NSValue else { continue }
                let nsFrame = frame.cgRectValue

                // Check if this NSWindow corresponds to our UIWindow (approximate frame match)
                if abs(nsFrame.width - uiFrame.width) < 50 && abs(nsFrame.height - uiFrame.height) < 50 {
                    // Set fullscreen collection behavior
                    let fullScreenPrimary: UInt = 1 << 7  // NSWindowCollectionBehavior.fullScreenPrimary
                    if let currentBehavior = nsWindow.value(forKey: "collectionBehavior") as? UInt {
                        nsWindow.setValue(currentBehavior | fullScreenPrimary, forKey: "collectionBehavior")
                    }

                    // Check if already fullscreen
                    if let styleMask = nsWindow.value(forKey: "styleMask") as? UInt {
                        let fullScreenMask: UInt = 1 << 14  // NSWindowStyleMask.fullScreen
                        if styleMask & fullScreenMask != 0 { return } // already fullscreen
                    }

                    // Toggle fullscreen
                    let sel = NSSelectorFromString("toggleFullScreen:")
                    if nsWindow.responds(to: sel) {
                        nsWindow.perform(sel, with: nil)
                    }
                    return
                }
            }
        }
        #endif

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

            let config = renderEngine.outputConfig
            if screenIndex < config.screens.count {
                let screen = config.screens[screenIndex]
                if let texture = renderEngine.outputRenderer.getScreenTexture(for: screen) {
                    encoder.setRenderPipelineState(pipelineState)
                    encoder.setVertexBuffer(MetalContext.shared.quadVertexBuffer, offset: 0, index: 0)
                    encoder.setFragmentTexture(texture, index: 0)
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
                }
            }

            encoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
