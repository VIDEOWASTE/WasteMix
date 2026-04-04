#pragma once

#include "dx12_context.h"

struct MixerState;

class Compositor {
public:
    void Initialize(DX12Context* ctx);
    void Composite(const MixerState& state, ID3D12GraphicsCommandList* cmdList, float time);

private:
    DX12Context* m_ctx = nullptr;
    ComPtr<ID3D12Resource> m_intermediateA;
    ComPtr<ID3D12Resource> m_intermediateB;
    ComPtr<ID3D12Resource> m_intermediateC;
};
