import SwiftUI

/// Passive presenter for the engine's stable program texture.
/// The render loop is driven by a CADisplayLink inside RenderEngine, so this
/// view doesn't drive rendering — it just blits the latest program frame.
struct ProgramOutputView: View {
    let renderEngine: RenderEngine

    var body: some View {
        PreviewView(
            device: MetalContext.shared.device,
            textureProvider: { [weak renderEngine] in renderEngine?.programTexture }
        )
    }
}
