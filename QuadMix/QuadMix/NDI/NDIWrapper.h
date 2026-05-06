// NDI SDK C Wrapper for Swift bridging
// This wraps the NDI SDK C API so Swift can use it via the bridging header.
// Download the NDI SDK from https://ndi.video/tools/ndi-sdk/
// Copy the headers and library to WasteMix/NDI/

#ifndef NDIWrapper_h
#define NDIWrapper_h

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque types
typedef void* NDIFinderRef;
typedef void* NDIReceiverRef;

// Source info
typedef struct {
    const char* name;
    const char* address;
} NDISourceInfo;

// Video frame info
typedef struct {
    int width;
    int height;
    int stride;
    uint8_t* data;
    int fourCC; // NDIlib_FourCC_video_type_BGRA etc.
    // Stores the original NDIlib_video_frame_v2_t for safe freeing.
    // 512 bytes is generously sized: the v2 struct fluctuates between 96-160
    // bytes across SDK versions/architectures; the previous 128-byte buffer
    // truncated newer revs and corrupted the heap when freed.
    uint8_t _ndi_frame[512];
} NDIVideoFrame;

// Initialize NDI runtime. Call once at app startup.
bool NDIWrapper_Initialize(void);

// Shutdown NDI runtime.
void NDIWrapper_Destroy(void);

// Create a finder to discover NDI sources on the network.
NDIFinderRef NDIWrapper_CreateFinder(void);

// Get current list of discovered sources. Returns count.
// sources array is valid until next call to this function or DestroyFinder.
int NDIWrapper_GetSources(NDIFinderRef finder, NDISourceInfo** outSources);

// Destroy finder.
void NDIWrapper_DestroyFinder(NDIFinderRef finder);

// Create a receiver connected to a specific source.
NDIReceiverRef NDIWrapper_CreateReceiver(const char* sourceName, const char* sourceAddress);

// Capture a video frame. Returns true if a frame was received.
// Caller must call NDIWrapper_FreeVideoFrame when done.
bool NDIWrapper_CaptureVideo(NDIReceiverRef receiver, NDIVideoFrame* outFrame, int timeoutMs);

// Free a captured video frame.
void NDIWrapper_FreeVideoFrame(NDIReceiverRef receiver, NDIVideoFrame* frame);

// Destroy receiver.
void NDIWrapper_DestroyReceiver(NDIReceiverRef receiver);

// --- NDI Send API ---

typedef void* NDISenderRef;

// Create an NDI sender with the given name (visible on the network)
NDISenderRef NDIWrapper_CreateSender(const char* name);

// Send a BGRA video frame (synchronous — copies the data inside the lib)
void NDIWrapper_SendVideo(NDISenderRef sender, const uint8_t* data,
                          int width, int height, int stride);

// Send a BGRA video frame asynchronously. The NDI lib keeps a reference to
// `data` until the next async call; the caller must NOT free or rewrite the
// buffer before then. Use a ring of 3+ buffers to avoid races.
void NDIWrapper_SendVideoAsync(NDISenderRef sender, const uint8_t* data,
                               int width, int height, int stride);

// Destroy sender
void NDIWrapper_DestroySender(NDISenderRef sender);

#ifdef __cplusplus
}
#endif

#endif
