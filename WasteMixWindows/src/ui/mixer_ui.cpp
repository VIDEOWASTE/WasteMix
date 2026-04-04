#include "mixer_ui.h"

// ImGui headers — include after downloading/adding ImGui to libs/imgui/
#ifdef HAS_IMGUI
#include "imgui.h"
#endif

void MixerUI::Initialize(RenderEngine* engine) {
    m_engine = engine;
}

void MixerUI::Render() {
#ifdef HAS_IMGUI
    auto& state = m_engine->GetState();

    // Style: dark, sharp, red accents
    ImGuiStyle& style = ImGui::GetStyle();
    style.WindowRounding = 0;
    style.FrameRounding = 0;
    style.GrabRounding = 0;
    style.TabRounding = 0;
    style.Colors[ImGuiCol_WindowBg] = ImVec4(0.03f, 0.03f, 0.04f, 1.0f);
    style.Colors[ImGuiCol_FrameBg] = ImVec4(0.05f, 0.05f, 0.06f, 1.0f);
    style.Colors[ImGuiCol_SliderGrab] = ImVec4(1.0f, 0.15f, 0.15f, 1.0f);
    style.Colors[ImGuiCol_CheckMark] = ImVec4(1.0f, 0.15f, 0.15f, 1.0f);
    style.Colors[ImGuiCol_Button] = ImVec4(0.1f, 0.02f, 0.02f, 1.0f);
    style.Colors[ImGuiCol_ButtonHovered] = ImVec4(0.3f, 0.05f, 0.05f, 1.0f);
    style.Colors[ImGuiCol_ButtonActive] = ImVec4(1.0f, 0.15f, 0.15f, 1.0f);
    style.Colors[ImGuiCol_Header] = ImVec4(0.15f, 0.02f, 0.02f, 1.0f);
    style.Colors[ImGuiCol_HeaderHovered] = ImVec4(0.3f, 0.05f, 0.05f, 1.0f);
    style.Colors[ImGuiCol_Separator] = ImVec4(1.0f, 0.15f, 0.15f, 0.15f);
    style.Colors[ImGuiCol_Text] = ImVec4(0.85f, 0.85f, 0.85f, 1.0f);

    // Full window
    ImGui::SetNextWindowPos(ImVec2(0, 0));
    ImGui::SetNextWindowSize(ImGui::GetIO().DisplaySize);
    ImGui::Begin("WasteMix", nullptr,
        ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize |
        ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoCollapse);

    DrawTopBar();
    ImGui::Separator();
    DrawMonitors();
    ImGui::Separator();
    DrawChannelCells();
    ImGui::Separator();
    DrawMasterSection();

    ImGui::End();
#endif
}

void MixerUI::DrawTopBar() {
#ifdef HAS_IMGUI
    ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(1.0f, 0.15f, 0.15f, 0.7f));
    float windowWidth = ImGui::GetWindowWidth();
    float textWidth = ImGui::CalcTextSize("WASTEMIX").x;
    ImGui::SetCursorPosX((windowWidth - textWidth) * 0.5f);
    ImGui::Text("WASTEMIX");
    ImGui::PopStyleColor();
#endif
}

void MixerUI::DrawMonitors() {
#ifdef HAS_IMGUI
    float w = ImGui::GetContentRegionAvail().x * 0.5f - 4;
    // PVW
    ImGui::BeginChild("PVW", ImVec2(w, 150), true);
    ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(1, 0.15f, 0.15f, 1));
    ImGui::Text("--- PVW ---");
    ImGui::PopStyleColor();
    ImGui::Text("CH %d", m_engine->GetState().selectedPreviewChannel + 1);
    // Texture would be rendered here via ImGui::Image with DX12 SRV
    ImGui::EndChild();

    ImGui::SameLine();

    // PGM
    ImGui::BeginChild("PGM", ImVec2(w, 150), true);
    ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(1, 0.15f, 0.15f, 1));
    ImGui::Text("--- PGM ---");
    ImGui::PopStyleColor();
    // Program output texture rendered here
    ImGui::EndChild();
#endif
}

void MixerUI::DrawChannelCells() {
#ifdef HAS_IMGUI
    float cellWidth = ImGui::GetContentRegionAvail().x / 4 - 4;
    for (int i = 0; i < 4; i++) {
        if (i > 0) ImGui::SameLine();
        ImGui::PushID(i);
        DrawChannelCell(i);
        ImGui::PopID();
    }
#endif
}

void MixerUI::DrawChannelCell(int index) {
#ifdef HAS_IMGUI
    auto& ch = m_engine->GetState().channels[index];
    auto& state = m_engine->GetState();
    float cellWidth = ImGui::GetContentRegionAvail().x / 4 - 3;

    ImGui::BeginChild(("CH" + std::to_string(index)).c_str(), ImVec2(cellWidth, 400), true);

    // Header
    bool isSelected = state.selectedPreviewChannel == index;
    ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(1.0f, 0.15f, 0.15f, 1.0f));
    if (ImGui::Selectable(("CH" + std::to_string(index + 1)).c_str(), isSelected))
        state.selectedPreviewChannel = index;
    ImGui::PopStyleColor();

    if (isSelected) {
        ImGui::SameLine();
        ImGui::TextColored(ImVec4(1, 0.15f, 0.15f, 1), "PVW");
    }

    // Level
    ImGui::SameLine(cellWidth - 30);
    ImGui::Text("%d", (int)(ch.faderLevel * 100));

    ImGui::Separator();

    // Fader
    ImGui::VSliderFloat("##fader", ImVec2(30, 120), &ch.faderLevel, 0, 1, "");

    ImGui::Separator();

    // Blend mode
    const char* blendNames[] = {
        "Normal","Add","Multiply","Screen","Overlay",
        "HardLight","SoftLight","ColorDodge","ColorBurn",
        "Difference","Exclusion","Darken","Lighten",
        "Subtract","Average","XOR"
    };
    int blendIdx = (int)ch.blendMode;
    if (ImGui::Combo("BLD", &blendIdx, blendNames, (int)BlendMode::COUNT))
        ch.blendMode = (BlendMode)blendIdx;

    // Source (placeholder)
    if (ImGui::Button("SOURCE", ImVec2(-1, 0))) {
        // Open file dialog for media source
    }

    // Transition
    const char* transNames[] = {
        "Mix","Cut","DipBlk","WipeL","WipeR","WipeU","WipeD",
        "DiagTL","DiagTR","Circle","Diamond","Blinds","Star"
    };
    int transIdx = (int)ch.transitionType;
    if (ImGui::Combo("TRANS", &transIdx, transNames, (int)TransitionType::COUNT))
        ch.transitionType = (TransitionType)transIdx;

    ImGui::SameLine();
    if (ImGui::Button(ch.isTransitioning ? "STOP" : "GO")) {
        if (ch.isTransitioning) {
            ch.isTransitioning = false;
            ch.transitionProgress = 0;
        } else {
            ch.isTransitioning = true;
            ch.transitionProgress = 0;
        }
    }

    // FX
    const char* fxNames[] = {
        "None","Freeze","MirrorH","MirrorV","Invert","Mosaic","Strobe",
        "RGBSplit","Posterize","Blur","Solarize","Edges","Datamosh",
        "Scanlines","Kaleido","Halftone"
    };
    int fxIdx = (int)ch.effectType;
    if (ImGui::Combo("FX", &fxIdx, fxNames, (int)EffectType::COUNT))
        ch.effectType = (EffectType)fxIdx;

    if (ch.effectType != EffectType::None && ch.effectType != EffectType::Freeze)
        ImGui::SliderFloat("INT", &ch.effectIntensity, 0, 1);

    ImGui::Checkbox("FRZ", &ch.isFrozen);

    // FX Params button
    if (ImGui::Button("FX PARAMS")) m_showFXParams[index] = true;
    ImGui::SameLine();
    if (ImGui::Button("CLR")) m_showColorCorrection[index] = true;
    ImGui::SameLine();
    if (ImGui::Button("AUD")) m_showAudioReact[index] = true;

    ImGui::EndChild();

    // FX Params popup
    if (m_showFXParams[index]) {
        ImGui::OpenPopup(("FXParams" + std::to_string(index)).c_str());
        m_showFXParams[index] = false;
    }
    if (ImGui::BeginPopup(("FXParams" + std::to_string(index)).c_str())) {
        DrawFXParamsPopup(index);
        ImGui::EndPopup();
    }
#endif
}

void MixerUI::DrawFXParamsPopup(int index) {
#ifdef HAS_IMGUI
    auto& ch = m_engine->GetState().channels[index];

    ImGui::Text("FX PARAMS - CH%d", index + 1);
    ImGui::Separator();

    ImGui::Checkbox("Freeze", &ch.isFrozen);
    ImGui::SliderFloat("Intensity", &ch.effectIntensity, 0, 1);
    ImGui::SliderFloat("Param 2", &ch.effectParam2, 0, 1);

    ImGui::Separator();
    ImGui::Text("PIP / POSITION");
    ImGui::SliderFloat("Scale", &ch.pipScale, 0.1f, 5.0f);
    ImGui::SliderFloat("X Offset", &ch.pipOffsetX, -1, 1);
    ImGui::SliderFloat("Y Offset", &ch.pipOffsetY, -1, 1);
    if (ImGui::Button("Reset PIP")) {
        ch.pipScale = 1; ch.pipOffsetX = 0; ch.pipOffsetY = 0;
    }

    ImGui::Separator();
    ImGui::Text("LFO");
    ImGui::Checkbox("Enable LFO", &ch.lfo.enabled);
    if (ch.lfo.enabled) {
        const char* shapes[] = {"Sine","Triangle","Square","Saw","Random"};
        ImGui::Combo("Shape", &ch.lfo.shape, shapes, 5);
        const char* targets[] = {"Off","Opacity","FX Int","FX P2","PIP Scale","PIP X","PIP Y"};
        ImGui::Combo("Target", &ch.lfo.target, targets, 7);
        ImGui::SliderFloat("Rate", &ch.lfo.rate, 0.01f, 2.7f, "%.2f Hz");
        ImGui::SliderFloat("Depth", &ch.lfo.depth, 0, 1);
        ImGui::SliderFloat("Min", &ch.lfo.minVal, 0, 1);
        ImGui::SliderFloat("Max", &ch.lfo.maxVal, 0, 1);
        ImGui::Checkbox("BPM Sync", &ch.lfo.useBPM);
    }
#endif
}

void MixerUI::DrawMasterSection() {
#ifdef HAS_IMGUI
    auto& state = m_engine->GetState();

    ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(1.0f, 0.15f, 0.15f, 0.7f));
    ImGui::Text("MASTER");
    ImGui::PopStyleColor();

    // Crossfader
    ImGui::BeginChild("Master", ImVec2(-1, 200), true);

    ImGui::Text("CROSSFADER  A:CH%d  B:CH%d", state.crossfaderA + 1, state.crossfaderB + 1);
    for (int i = 0; i < 4; i++) {
        ImGui::SameLine();
        if (ImGui::SmallButton(("A:" + std::to_string(i+1)).c_str())) state.crossfaderA = i;
    }
    ImGui::SliderFloat("XFADE", &state.crossfaderPos, 0, 1);
    if (state.crossfaderA != state.crossfaderB) {
        state.channels[state.crossfaderA].faderLevel = 1.0f - state.crossfaderPos;
        state.channels[state.crossfaderB].faderLevel = state.crossfaderPos;
    }

    ImGui::Separator();

    // Fade to black
    if (ImGui::Button("FADE TO BLACK", ImVec2(-1, 30))) {
        for (auto& ch : state.channels) {
            if (ch.faderLevel > 0.001f) {
                ch.isTransitioning = true;
                ch.transitionProgress = 0;
            }
        }
    }

    // BPM
    ImGui::Text("BPM: %.0f", state.bpm);
    static float tapTimes[8] = {};
    static int tapCount = 0;
    if (ImGui::Button("TAP")) {
        // Simple tap tempo
        float now = (float)ImGui::GetTime();
        if (tapCount > 0 && now - tapTimes[(tapCount-1)%8] > 2.0f) tapCount = 0;
        tapTimes[tapCount % 8] = now;
        tapCount++;
        if (tapCount >= 2) {
            float total = 0;
            int n = min(tapCount, 8);
            for (int i = 1; i < n; i++)
                total += tapTimes[i%8] - tapTimes[(i-1)%8];
            float avg = total / (n - 1);
            if (avg > 0) state.bpm = 60.0f / avg;
        }
    }

    // Global color
    if (ImGui::Button("GLOBAL COLOR")) m_showGlobalColor = !m_showGlobalColor;
    if (m_showGlobalColor) {
        auto& gc = state.globalColorCorrection;
        ImGui::SliderFloat("Brightness", &gc.brightness, -1, 1);
        ImGui::SliderFloat("Contrast", &gc.contrast, 0, 2);
        ImGui::SliderFloat("Saturation", &gc.saturation, 0, 2);
        ImGui::SliderFloat("Hue", &gc.hueShift, 0, 360);
    }

    ImGui::EndChild();
#endif
}
