#include "audio_engine.h"
#include <cmath>
#include <vector>
#include <functiondiscoverykeys_devpkey.h>

#pragma comment(lib, "ole32.lib")

const char* AudioEngine::BandNames[NUM_BANDS] = {
    "Sub Bass", "Bass", "Low Mid", "Mid", "High Mid", "High", "Brilliance"
};

bool AudioEngine::Initialize() {
    m_running = true;
    m_thread = std::thread(&AudioEngine::CaptureThread, this);
    return true;
}

void AudioEngine::CaptureThread() {
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);

    IMMDeviceEnumerator* enumerator = nullptr;
    CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
        __uuidof(IMMDeviceEnumerator), (void**)&enumerator);

    IMMDevice* device = nullptr;
    // Use default audio capture device (microphone)
    enumerator->GetDefaultAudioEndpoint(eCapture, eConsole, &device);

    if (!device) {
        // Fall back to loopback (what you hear)
        enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device);
    }

    IAudioClient* audioClient = nullptr;
    device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, (void**)&audioClient);

    WAVEFORMATEX* fmt = nullptr;
    audioClient->GetMixFormat(&fmt);

    audioClient->Initialize(AUDCLNT_SHAREMODE_SHARED, 0, 10000000, 0, fmt, nullptr);

    IAudioCaptureClient* captureClient = nullptr;
    audioClient->GetService(__uuidof(IAudioCaptureClient), (void**)&captureClient);

    audioClient->Start();

    const int fftSize = 1024;
    std::vector<float> buffer(fftSize, 0);
    int bufPos = 0;

    while (m_running) {
        UINT32 packetLength = 0;
        captureClient->GetNextPacketSize(&packetLength);

        while (packetLength > 0) {
            BYTE* data;
            UINT32 numFrames;
            DWORD flags;
            captureClient->GetBuffer(&data, &numFrames, &flags, nullptr, nullptr);

            // Convert to mono float
            float* fData = (float*)data;
            int channels = fmt->nChannels;
            for (UINT32 i = 0; i < numFrames && bufPos < fftSize; i++) {
                float sample = 0;
                for (int c = 0; c < channels; c++)
                    sample += fData[i * channels + c];
                buffer[bufPos++] = sample / channels;
            }

            captureClient->ReleaseBuffer(numFrames);

            if (bufPos >= fftSize) {
                // Simple DFT band analysis
                float sampleRate = (float)fmt->nSamplesPerSec;
                float bandRanges[][2] = {
                    {20,60}, {60,250}, {250,500}, {500,2000}, {2000,4000}, {4000,8000}, {8000,20000}
                };

                std::array<float, NUM_BANDS> bands{};
                float rms = 0;
                for (int i = 0; i < fftSize; i++) rms += buffer[i] * buffer[i];
                rms = sqrtf(rms / fftSize);

                // Simple band energy estimation using Goertzel-like approach
                for (int b = 0; b < NUM_BANDS; b++) {
                    float lowBin = bandRanges[b][0] * fftSize / sampleRate;
                    float highBin = bandRanges[b][1] * fftSize / sampleRate;
                    float energy = 0;
                    int count = 0;
                    for (int k = (int)lowBin; k < (int)highBin && k < fftSize/2; k++) {
                        float re = 0, im = 0;
                        for (int n = 0; n < fftSize; n++) {
                            float angle = 2.0f * 3.14159f * k * n / fftSize;
                            re += buffer[n] * cosf(angle);
                            im -= buffer[n] * sinf(angle);
                        }
                        energy += sqrtf(re*re + im*im);
                        count++;
                    }
                    bands[b] = count > 0 ? energy / count / fftSize : 0;
                }

                // Normalize
                float maxBand = 0.001f;
                for (auto b : bands) maxBand = max(maxBand, b);
                for (auto& b : bands) b /= maxBand;

                std::lock_guard<std::mutex> lock(m_mutex);
                m_bandLevels = bands;
                m_level = min(rms * 5.0f, 1.0f);

                bufPos = 0;
            }

            captureClient->GetNextPacketSize(&packetLength);
        }

        Sleep(10);
    }

    audioClient->Stop();
    captureClient->Release();
    audioClient->Release();
    device->Release();
    enumerator->Release();
    CoUninitialize();
}

float AudioEngine::GetBandLevel(int band) const {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (band >= 0 && band < NUM_BANDS) return m_bandLevels[band];
    return 0;
}

void AudioEngine::Shutdown() {
    m_running = false;
    if (m_thread.joinable()) m_thread.join();
}
