#pragma once

#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <wrl/client.h>
#include <vector>
#include <mutex>

using Microsoft::WRL::ComPtr;

class CameraSource {
public:
    bool Initialize(int deviceIndex = 0);
    void Shutdown();
    bool GetLatestFrame(std::vector<uint8_t>& outData, UINT& outWidth, UINT& outHeight);

private:
    ComPtr<IMFSourceReader> m_reader;
    std::mutex m_mutex;
    bool m_initialized = false;
};
