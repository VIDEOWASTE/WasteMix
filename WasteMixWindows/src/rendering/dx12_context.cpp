#include "dx12_context.h"
#include <stdexcept>
#include <fstream>

#pragma comment(lib, "d3d12.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "d3dcompiler.lib")

bool DX12Context::Initialize(HWND hwnd, UINT width, UINT height) {
    m_width = width;
    m_height = height;

    // Enable debug layer in debug builds
#ifdef _DEBUG
    ComPtr<ID3D12Debug> debugController;
    if (SUCCEEDED(D3D12GetDebugInterface(IID_PPV_ARGS(&debugController))))
        debugController->EnableDebugLayer();
#endif

    // Create device
    ComPtr<IDXGIFactory4> factory;
    CreateDXGIFactory2(0, IID_PPV_ARGS(&factory));

    ComPtr<IDXGIAdapter1> adapter;
    for (UINT i = 0; factory->EnumAdapters1(i, &adapter) != DXGI_ERROR_NOT_FOUND; i++) {
        DXGI_ADAPTER_DESC1 desc;
        adapter->GetDesc1(&desc);
        if (desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) continue;
        if (SUCCEEDED(D3D12CreateDevice(adapter.Get(), D3D_FEATURE_LEVEL_12_0, IID_PPV_ARGS(&m_device))))
            break;
    }
    if (!m_device) return false;

    // Command queue
    D3D12_COMMAND_QUEUE_DESC queueDesc{};
    queueDesc.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
    m_device->CreateCommandQueue(&queueDesc, IID_PPV_ARGS(&m_commandQueue));

    // Swap chain
    CreateSwapChain(hwnd);

    // RTV heap
    D3D12_DESCRIPTOR_HEAP_DESC rtvHeapDesc{};
    rtvHeapDesc.NumDescriptors = FRAME_COUNT;
    rtvHeapDesc.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV;
    m_device->CreateDescriptorHeap(&rtvHeapDesc, IID_PPV_ARGS(&m_rtvHeap));
    m_rtvDescriptorSize = m_device->GetDescriptorHandleIncrementSize(D3D12_DESCRIPTOR_HEAP_TYPE_RTV);

    // SRV heap (shader visible, for textures)
    D3D12_DESCRIPTOR_HEAP_DESC srvHeapDesc{};
    srvHeapDesc.NumDescriptors = 256;
    srvHeapDesc.Type = D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV;
    srvHeapDesc.Flags = D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE;
    m_device->CreateDescriptorHeap(&srvHeapDesc, IID_PPV_ARGS(&m_srvHeap));
    m_srvDescriptorSize = m_device->GetDescriptorHandleIncrementSize(D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);

    CreateRTVs();

    // Command allocators + command list
    for (UINT i = 0; i < FRAME_COUNT; i++)
        m_device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(&m_commandAllocators[i]));

    m_device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT,
        m_commandAllocators[0].Get(), nullptr, IID_PPV_ARGS(&m_commandList));
    m_commandList->Close();

    // Fence
    m_device->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&m_fence));
    m_fenceEvent = CreateEvent(nullptr, FALSE, FALSE, nullptr);

    // Root signature: 2 descriptor tables (textures) + 1 root constants (uniforms)
    D3D12_DESCRIPTOR_RANGE1 srvRange{};
    srvRange.RangeType = D3D12_DESCRIPTOR_RANGE_TYPE_SRV;
    srvRange.NumDescriptors = 2;
    srvRange.BaseShaderRegister = 0;

    D3D12_ROOT_PARAMETER1 params[2]{};
    // Param 0: descriptor table for textures
    params[0].ParameterType = D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE;
    params[0].DescriptorTable.NumDescriptorRanges = 1;
    params[0].DescriptorTable.pDescriptorRanges = &srvRange;
    params[0].ShaderVisibility = D3D12_SHADER_VISIBILITY_PIXEL;
    // Param 1: root constants (16 floats = 64 bytes, enough for any uniform struct)
    params[1].ParameterType = D3D12_ROOT_PARAMETER_TYPE_32BIT_CONSTANTS;
    params[1].Constants.ShaderRegister = 0;
    params[1].Constants.Num32BitValues = 16;
    params[1].ShaderVisibility = D3D12_SHADER_VISIBILITY_PIXEL;

    D3D12_STATIC_SAMPLER_DESC sampler{};
    sampler.Filter = D3D12_FILTER_MIN_MAG_MIP_LINEAR;
    sampler.AddressU = D3D12_TEXTURE_ADDRESS_MODE_CLAMP;
    sampler.AddressV = D3D12_TEXTURE_ADDRESS_MODE_CLAMP;
    sampler.AddressW = D3D12_TEXTURE_ADDRESS_MODE_CLAMP;
    sampler.ShaderRegister = 0;
    sampler.ShaderVisibility = D3D12_SHADER_VISIBILITY_PIXEL;

    D3D12_VERSIONED_ROOT_SIGNATURE_DESC rsDesc{};
    rsDesc.Version = D3D_ROOT_SIGNATURE_VERSION_1_1;
    rsDesc.Desc_1_1.NumParameters = 2;
    rsDesc.Desc_1_1.pParameters = params;
    rsDesc.Desc_1_1.NumStaticSamplers = 1;
    rsDesc.Desc_1_1.pStaticSamplers = &sampler;
    rsDesc.Desc_1_1.Flags = D3D12_ROOT_SIGNATURE_FLAG_ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT;

    ComPtr<ID3DBlob> signature, error;
    D3D12SerializeVersionedRootSignature(&rsDesc, &signature, &error);
    m_device->CreateRootSignature(0, signature->GetBufferPointer(), signature->GetBufferSize(),
        IID_PPV_ARGS(&m_rootSignature));

    CreateQuadVertexBuffer();

    return true;
}

void DX12Context::CreateSwapChain(HWND hwnd) {
    ComPtr<IDXGIFactory4> factory;
    CreateDXGIFactory2(0, IID_PPV_ARGS(&factory));

    DXGI_SWAP_CHAIN_DESC1 scDesc{};
    scDesc.Width = m_width;
    scDesc.Height = m_height;
    scDesc.Format = RENDER_FORMAT;
    scDesc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    scDesc.BufferCount = FRAME_COUNT;
    scDesc.SampleDesc.Count = 1;
    scDesc.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;

    ComPtr<IDXGISwapChain1> swapChain1;
    factory->CreateSwapChainForHwnd(m_commandQueue.Get(), hwnd, &scDesc, nullptr, nullptr, &swapChain1);
    swapChain1.As(&m_swapChain);
    m_frameIndex = m_swapChain->GetCurrentBackBufferIndex();
}

void DX12Context::CreateRTVs() {
    D3D12_CPU_DESCRIPTOR_HANDLE rtvHandle = m_rtvHeap->GetCPUDescriptorHandleForHeapStart();
    for (UINT i = 0; i < FRAME_COUNT; i++) {
        m_swapChain->GetBuffer(i, IID_PPV_ARGS(&m_backBuffers[i]));
        m_device->CreateRenderTargetView(m_backBuffers[i].Get(), nullptr, rtvHandle);
        rtvHandle.ptr += m_rtvDescriptorSize;
    }
}

void DX12Context::CreateQuadVertexBuffer() {
    Vertex vertices[] = {
        {{-1,  1}, {0, 0}},
        {{-1, -1}, {0, 1}},
        {{ 1, -1}, {1, 1}},
        {{-1,  1}, {0, 0}},
        {{ 1, -1}, {1, 1}},
        {{ 1,  1}, {1, 0}},
    };

    const UINT bufferSize = sizeof(vertices);
    D3D12_HEAP_PROPERTIES heapProps{};
    heapProps.Type = D3D12_HEAP_TYPE_UPLOAD;
    D3D12_RESOURCE_DESC bufferDesc = {};
    bufferDesc.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
    bufferDesc.Width = bufferSize;
    bufferDesc.Height = 1;
    bufferDesc.DepthOrArraySize = 1;
    bufferDesc.MipLevels = 1;
    bufferDesc.SampleDesc.Count = 1;
    bufferDesc.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;

    m_device->CreateCommittedResource(&heapProps, D3D12_HEAP_FLAG_NONE, &bufferDesc,
        D3D12_RESOURCE_STATE_GENERIC_READ, nullptr, IID_PPV_ARGS(&m_quadVertexBuffer));

    void* mapped;
    m_quadVertexBuffer->Map(0, nullptr, &mapped);
    memcpy(mapped, vertices, bufferSize);
    m_quadVertexBuffer->Unmap(0, nullptr);

    m_quadVBV.BufferLocation = m_quadVertexBuffer->GetGPUVirtualAddress();
    m_quadVBV.SizeInBytes = bufferSize;
    m_quadVBV.StrideInBytes = sizeof(Vertex);
}

bool DX12Context::CreatePipeline(const std::string& name, const std::wstring& psShaderPath,
                                  const std::string& psEntry, int numTextures) {
    // Compile vertex shader (inline)
    const char* vsSource = R"(
        struct VSInput { float2 pos : POSITION; float2 uv : TEXCOORD; };
        struct PSInput { float4 pos : SV_POSITION; float2 uv : TEXCOORD; };
        PSInput main(VSInput input) {
            PSInput output;
            output.pos = float4(input.pos, 0, 1);
            output.uv = input.uv;
            return output;
        }
    )";

    ComPtr<ID3DBlob> vsBlob, psBlob, errors;
    D3DCompile(vsSource, strlen(vsSource), nullptr, nullptr, nullptr, "main", "vs_5_1", 0, 0, &vsBlob, &errors);

    // Compile pixel shader from file
    HRESULT hr = D3DCompileFromFile(psShaderPath.c_str(), nullptr, D3D_COMPILE_STANDARD_FILE_INCLUDE,
        psEntry.c_str(), "ps_5_1", 0, 0, &psBlob, &errors);
    if (FAILED(hr)) return false;

    // Input layout
    D3D12_INPUT_ELEMENT_DESC inputLayout[] = {
        {"POSITION", 0, DXGI_FORMAT_R32G32_FLOAT, 0, 0, D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA, 0},
        {"TEXCOORD", 0, DXGI_FORMAT_R32G32_FLOAT, 0, 8, D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA, 0},
    };

    D3D12_GRAPHICS_PIPELINE_STATE_DESC psoDesc{};
    psoDesc.InputLayout = {inputLayout, 2};
    psoDesc.pRootSignature = m_rootSignature.Get();
    psoDesc.VS = {vsBlob->GetBufferPointer(), vsBlob->GetBufferSize()};
    psoDesc.PS = {psBlob->GetBufferPointer(), psBlob->GetBufferSize()};
    psoDesc.RasterizerState.FillMode = D3D12_FILL_MODE_SOLID;
    psoDesc.RasterizerState.CullMode = D3D12_CULL_MODE_NONE;
    psoDesc.BlendState.RenderTarget[0].RenderTargetWriteMask = D3D12_COLOR_WRITE_ENABLE_ALL;
    psoDesc.SampleMask = UINT_MAX;
    psoDesc.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE;
    psoDesc.NumRenderTargets = 1;
    psoDesc.RTVFormats[0] = RENDER_FORMAT;
    psoDesc.SampleDesc.Count = 1;

    ComPtr<ID3D12PipelineState> pso;
    hr = m_device->CreateGraphicsPipelineState(&psoDesc, IID_PPV_ARGS(&pso));
    if (FAILED(hr)) return false;

    m_pipelines[name] = pso;
    return true;
}

ID3D12PipelineState* DX12Context::GetPipeline(const std::string& name) {
    auto it = m_pipelines.find(name);
    return it != m_pipelines.end() ? it->second.Get() : nullptr;
}

ComPtr<ID3D12Resource> DX12Context::CreateTexture(UINT width, UINT height) {
    D3D12_HEAP_PROPERTIES heapProps{};
    heapProps.Type = D3D12_HEAP_TYPE_DEFAULT;

    D3D12_RESOURCE_DESC texDesc{};
    texDesc.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
    texDesc.Width = width;
    texDesc.Height = height;
    texDesc.DepthOrArraySize = 1;
    texDesc.MipLevels = 1;
    texDesc.Format = RENDER_FORMAT;
    texDesc.SampleDesc.Count = 1;
    texDesc.Flags = D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;

    ComPtr<ID3D12Resource> texture;
    D3D12_CLEAR_VALUE clearValue{};
    clearValue.Format = RENDER_FORMAT;
    m_device->CreateCommittedResource(&heapProps, D3D12_HEAP_FLAG_NONE, &texDesc,
        D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE, &clearValue, IID_PPV_ARGS(&texture));
    return texture;
}

UINT DX12Context::AllocateSRVDescriptor() {
    return m_nextSRVSlot++;
}

void DX12Context::BeginFrame() {
    m_frameIndex = m_swapChain->GetCurrentBackBufferIndex();
    if (m_fence->GetCompletedValue() < m_fenceValues[m_frameIndex]) {
        m_fence->SetEventOnCompletion(m_fenceValues[m_frameIndex], m_fenceEvent);
        WaitForSingleObject(m_fenceEvent, INFINITE);
    }
    m_commandAllocators[m_frameIndex]->Reset();
    m_commandList->Reset(m_commandAllocators[m_frameIndex].Get(), nullptr);
}

ID3D12Resource* DX12Context::GetCurrentBackBuffer() {
    return m_backBuffers[m_frameIndex].Get();
}

D3D12_CPU_DESCRIPTOR_HANDLE DX12Context::GetCurrentRTV() {
    D3D12_CPU_DESCRIPTOR_HANDLE handle = m_rtvHeap->GetCPUDescriptorHandleForHeapStart();
    handle.ptr += m_frameIndex * m_rtvDescriptorSize;
    return handle;
}

void DX12Context::EndFrame() {
    m_commandList->Close();
    ID3D12CommandList* lists[] = {m_commandList.Get()};
    m_commandQueue->ExecuteCommandLists(1, lists);
}

void DX12Context::Present() {
    m_swapChain->Present(1, 0);
    m_fenceValues[m_frameIndex] = ++m_fenceValues[0];
    m_commandQueue->Signal(m_fence.Get(), m_fenceValues[m_frameIndex]);
}

void DX12Context::WaitForGPU() {
    m_commandQueue->Signal(m_fence.Get(), ++m_fenceValues[0]);
    m_fence->SetEventOnCompletion(m_fenceValues[0], m_fenceEvent);
    WaitForSingleObject(m_fenceEvent, INFINITE);
}

void DX12Context::Shutdown() {
    WaitForGPU();
    if (m_fenceEvent) CloseHandle(m_fenceEvent);
}

void DX12Context::Resize(UINT width, UINT height) {
    if (width == 0 || height == 0) return;
    WaitForGPU();
    for (UINT i = 0; i < FRAME_COUNT; i++) m_backBuffers[i].Reset();
    m_swapChain->ResizeBuffers(FRAME_COUNT, width, height, RENDER_FORMAT, 0);
    m_width = width;
    m_height = height;
    m_frameIndex = m_swapChain->GetCurrentBackBufferIndex();
    CreateRTVs();
}
