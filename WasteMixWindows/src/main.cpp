// WasteMix — Windows DirectX 12 Application
// Entry point: Win32 window + DX12 render loop + ImGui UI

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include "rendering/render_engine.h"
#include "ui/mixer_ui.h"

// Globals
static RenderEngine g_engine;
static MixerUI g_ui;
static bool g_running = true;
static UINT g_width = 1280;
static UINT g_height = 800;

LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
    case WM_SIZE:
        if (wParam != SIZE_MINIMIZED) {
            g_width = LOWORD(lParam);
            g_height = HIWORD(lParam);
            g_engine.Resize(g_width, g_height);
        }
        return 0;
    case WM_DESTROY:
        g_running = false;
        PostQuitMessage(0);
        return 0;
    case WM_KEYDOWN:
        if (wParam == VK_ESCAPE) {
            g_running = false;
            PostQuitMessage(0);
        }
        return 0;
    }
    return DefWindowProc(hwnd, msg, wParam, lParam);
}

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE, LPSTR, int nCmdShow) {
    // Register window class
    WNDCLASSEX wc{};
    wc.cbSize = sizeof(WNDCLASSEX);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInstance;
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.lpszClassName = L"WasteMixClass";
    RegisterClassEx(&wc);

    // Create window
    RECT rect = {0, 0, (LONG)g_width, (LONG)g_height};
    AdjustWindowRect(&rect, WS_OVERLAPPEDWINDOW, FALSE);

    HWND hwnd = CreateWindowEx(0, L"WasteMixClass", L"WasteMix",
        WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT,
        rect.right - rect.left, rect.bottom - rect.top,
        nullptr, nullptr, hInstance, nullptr);

    ShowWindow(hwnd, nCmdShow);
    UpdateWindow(hwnd);

    // Initialize DirectX 12
    if (!g_engine.Initialize(hwnd, g_width, g_height)) {
        MessageBox(hwnd, L"Failed to initialize DirectX 12.\nMake sure you have a DX12-capable GPU.",
                   L"WasteMix Error", MB_OK | MB_ICONERROR);
        return 1;
    }

    g_ui.Initialize(&g_engine);

    // Main loop
    MSG msg{};
    while (g_running) {
        while (PeekMessage(&msg, nullptr, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
            if (msg.message == WM_QUIT) g_running = false;
        }

        if (!g_running) break;

        // Render frame
        g_engine.RenderFrame();
    }

    g_engine.Shutdown();
    DestroyWindow(hwnd);
    UnregisterClass(L"WasteMixClass", hInstance);

    return 0;
}
