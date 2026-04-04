#pragma once

#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <wrl/client.h>
#include <vector>
#include <string>

using Microsoft::WRL::ComPtr;

class MediaSource {
public:
    bool LoadFile(const std::wstring& path);
    bool GetNextFrame(std::vector<uint8_t>& outData, UINT& outWidth, UINT& outHeight);
    void Shutdown();

private:
    ComPtr<IMFSourceReader> m_reader;
    bool m_loaded = false;
};
