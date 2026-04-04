#pragma once

#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <array>
#include <thread>
#include <atomic>
#include <mutex>

class AudioEngine {
public:
    bool Initialize();
    void Shutdown();

    float GetBandLevel(int band) const; // 0-6
    float GetLevel() const { return m_level; }
    bool IsRunning() const { return m_running; }

    static constexpr int NUM_BANDS = 7;
    static const char* BandNames[NUM_BANDS];

private:
    void CaptureThread();

    std::thread m_thread;
    std::atomic<bool> m_running{false};
    mutable std::mutex m_mutex;

    std::array<float, NUM_BANDS> m_bandLevels{};
    float m_level = 0;
};
