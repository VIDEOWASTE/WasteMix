#pragma once

#include "../rendering/render_engine.h"

// ImGui-based mixer UI matching the iPad WasteMix layout
class MixerUI {
public:
    void Initialize(RenderEngine* engine);
    void Render(); // Call each frame after ImGui::NewFrame()

private:
    void DrawTopBar();
    void DrawMonitors();
    void DrawChannelCells();
    void DrawChannelCell(int index);
    void DrawMasterSection();
    void DrawFXParamsPopup(int channelIndex);

    RenderEngine* m_engine = nullptr;
    bool m_showFXParams[4] = {};
    bool m_showColorCorrection[4] = {};
    bool m_showAudioReact[4] = {};
    bool m_showGlobalColor = false;
    bool m_showPresets = false;
};
