#include "camera_source.h"
#include <mfapi.h>
#include <mfplay.h>

#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfreadwrite.lib")
#pragma comment(lib, "mfuuid.lib")

bool CameraSource::Initialize(int deviceIndex) {
    MFStartup(MF_VERSION);

    ComPtr<IMFAttributes> attrs;
    MFCreateAttributes(&attrs, 1);
    attrs->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE, MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);

    IMFActivate** devices = nullptr;
    UINT32 count = 0;
    MFEnumDeviceSources(attrs.Get(), &devices, &count);
    if (count == 0 || deviceIndex >= (int)count) return false;

    ComPtr<IMFMediaSource> source;
    devices[deviceIndex]->ActivateObject(IID_PPV_ARGS(&source));

    for (UINT32 i = 0; i < count; i++) devices[i]->Release();
    CoTaskMemFree(devices);

    ComPtr<IMFAttributes> readerAttrs;
    MFCreateAttributes(&readerAttrs, 1);
    MFCreateSourceReaderFromMediaSource(source.Get(), readerAttrs.Get(), &m_reader);

    // Request BGRA output
    ComPtr<IMFMediaType> mediaType;
    MFCreateMediaType(&mediaType);
    mediaType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    mediaType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
    m_reader->SetCurrentMediaType(0, nullptr, mediaType.Get());

    m_initialized = true;
    return true;
}

bool CameraSource::GetLatestFrame(std::vector<uint8_t>& outData, UINT& outWidth, UINT& outHeight) {
    if (!m_initialized) return false;

    DWORD flags = 0;
    ComPtr<IMFSample> sample;
    m_reader->ReadSample(0, 0, nullptr, &flags, nullptr, &sample);
    if (!sample) return false;

    ComPtr<IMFMediaBuffer> buffer;
    sample->ConvertToContiguousBuffer(&buffer);

    BYTE* data = nullptr;
    DWORD length = 0;
    buffer->Lock(&data, nullptr, &length);

    outData.assign(data, data + length);
    // Get dimensions from current media type
    ComPtr<IMFMediaType> type;
    m_reader->GetCurrentMediaType(0, &type);
    MFGetAttributeSize(type.Get(), MF_MT_FRAME_SIZE, &outWidth, &outHeight);

    buffer->Unlock();
    return true;
}

void CameraSource::Shutdown() {
    m_reader.Reset();
    m_initialized = false;
}
