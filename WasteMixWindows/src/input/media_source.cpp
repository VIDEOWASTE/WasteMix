#include "media_source.h"

bool MediaSource::LoadFile(const std::wstring& path) {
    MFStartup(MF_VERSION);

    ComPtr<IMFAttributes> attrs;
    MFCreateAttributes(&attrs, 0);
    HRESULT hr = MFCreateSourceReaderFromURL(path.c_str(), attrs.Get(), &m_reader);
    if (FAILED(hr)) return false;

    ComPtr<IMFMediaType> mediaType;
    MFCreateMediaType(&mediaType);
    mediaType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    mediaType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
    m_reader->SetCurrentMediaType((DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, nullptr, mediaType.Get());

    m_loaded = true;
    return true;
}

bool MediaSource::GetNextFrame(std::vector<uint8_t>& outData, UINT& outWidth, UINT& outHeight) {
    if (!m_loaded) return false;

    DWORD flags = 0;
    ComPtr<IMFSample> sample;
    m_reader->ReadSample((DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, nullptr, &flags, nullptr, &sample);

    if (flags & MF_SOURCE_READERF_ENDOFSTREAM) {
        // Loop: seek back to start
        PROPVARIANT var;
        PropVariantInit(&var);
        var.vt = VT_I8;
        var.hVal.QuadPart = 0;
        m_reader->SetCurrentPosition(GUID_NULL, var);
        return false;
    }

    if (!sample) return false;

    ComPtr<IMFMediaBuffer> buffer;
    sample->ConvertToContiguousBuffer(&buffer);

    BYTE* data;
    DWORD length;
    buffer->Lock(&data, nullptr, &length);
    outData.assign(data, data + length);
    buffer->Unlock();

    ComPtr<IMFMediaType> type;
    m_reader->GetCurrentMediaType((DWORD)MF_SOURCE_READER_FIRST_VIDEO_STREAM, &type);
    MFGetAttributeSize(type.Get(), MF_MT_FRAME_SIZE, &outWidth, &outHeight);

    return true;
}

void MediaSource::Shutdown() {
    m_reader.Reset();
    m_loaded = false;
}
