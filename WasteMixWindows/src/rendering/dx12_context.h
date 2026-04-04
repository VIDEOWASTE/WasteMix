#pragma once

#include <d3d12.h>
#include <dxgi1_6.h>
#include <d3dcompiler.h>
#include <wrl/client.h>
#include <string>
#include <unordered_map>
#include <vector>

using Microsoft::WRL::ComPtr;

struct Vertex {
    float position[2];
    float texCoord[2];
};

class DX12Context {
public:
    static constexpr UINT FRAME_COUNT = 3;
    static constexpr DXGI_FORMAT RENDER_FORMAT = DXGI_FORMAT_B8G8R8A8_UNORM;

    bool Initialize(HWND hwnd, UINT width, UINT height);
    void Shutdown();
    void Resize(UINT width, UINT height);

    // Pipeline management
    ID3D12PipelineState* GetPipeline(const std::string& name);
    bool CreatePipeline(const std::string& name, const std::wstring& psShaderPath,
                        const std::string& psEntry, int numTextures = 1);

    // Resource creation
    ComPtr<ID3D12Resource> CreateTexture(UINT width, UINT height);
    ComPtr<ID3D12Resource> CreateUploadBuffer(size_t size);

    // Frame management
    void BeginFrame();
    ID3D12GraphicsCommandList* GetCommandList() { return m_commandList.Get(); }
    void EndFrame();
    void Present();

    // Getters
    ID3D12Device* GetDevice() { return m_device.Get(); }
    ID3D12CommandQueue* GetCommandQueue() { return m_commandQueue.Get(); }
    ID3D12Resource* GetCurrentBackBuffer();
    D3D12_CPU_DESCRIPTOR_HANDLE GetCurrentRTV();
    UINT GetWidth() const { return m_width; }
    UINT GetHeight() const { return m_height; }
    D3D12_VERTEX_BUFFER_VIEW GetQuadVBV() const { return m_quadVBV; }

    // Descriptor heaps
    ID3D12DescriptorHeap* GetSRVHeap() { return m_srvHeap.Get(); }
    UINT AllocateSRVDescriptor();

    void WaitForGPU();

private:
    void CreateSwapChain(HWND hwnd);
    void CreateRTVs();
    void CreateQuadVertexBuffer();

    ComPtr<ID3D12Device> m_device;
    ComPtr<IDXGISwapChain3> m_swapChain;
    ComPtr<ID3D12CommandQueue> m_commandQueue;
    ComPtr<ID3D12CommandAllocator> m_commandAllocators[FRAME_COUNT];
    ComPtr<ID3D12GraphicsCommandList> m_commandList;
    ComPtr<ID3D12DescriptorHeap> m_rtvHeap;
    ComPtr<ID3D12DescriptorHeap> m_srvHeap;
    ComPtr<ID3D12Resource> m_backBuffers[FRAME_COUNT];
    ComPtr<ID3D12RootSignature> m_rootSignature;
    ComPtr<ID3D12Resource> m_quadVertexBuffer;
    D3D12_VERTEX_BUFFER_VIEW m_quadVBV{};

    std::unordered_map<std::string, ComPtr<ID3D12PipelineState>> m_pipelines;

    // Synchronization
    ComPtr<ID3D12Fence> m_fence;
    UINT64 m_fenceValues[FRAME_COUNT]{};
    HANDLE m_fenceEvent = nullptr;
    UINT m_frameIndex = 0;

    UINT m_width = 0;
    UINT m_height = 0;
    UINT m_rtvDescriptorSize = 0;
    UINT m_srvDescriptorSize = 0;
    UINT m_nextSRVSlot = 0;
};
