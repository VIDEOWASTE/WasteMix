// NDI SDK C Wrapper implementation
// This file links against the NDI SDK library.
//
// To enable:
// 1. Download NDI SDK from https://ndi.video/tools/ndi-sdk/
// 2. Copy Processing.NDI.Lib.h to QuadMix/NDI/
// 3. Copy libndi.dylib (macOS) to QuadMix/NDI/
// 4. Add ENABLE_NDI=1 to preprocessor defines in Xcode build settings
// 5. Add libndi.dylib to Link Binary With Libraries

#include "NDIWrapper.h"

#ifdef ENABLE_NDI

#include "Processing.NDI.Lib.h"
#include <stdlib.h>
#include <string.h>

bool NDIWrapper_Initialize(void) {
    return NDIlib_initialize();
}

void NDIWrapper_Destroy(void) {
    NDIlib_destroy();
}

NDIFinderRef NDIWrapper_CreateFinder(void) {
    NDIlib_find_create_t find_create;
    find_create.show_local_sources = true;
    find_create.p_groups = NULL;
    find_create.p_extra_ips = NULL;
    return (NDIFinderRef)NDIlib_find_create_v2(&find_create);
}

int NDIWrapper_GetSources(NDIFinderRef finder, NDISourceInfo** outSources) {
    if (!finder) return 0;

    NDIlib_find_instance_t ndi_find = (NDIlib_find_instance_t)finder;

    // Wait up to 1 second for sources
    NDIlib_find_wait_for_sources(ndi_find, 1000);

    uint32_t count = 0;
    const NDIlib_source_t* sources = NDIlib_find_get_current_sources(ndi_find, &count);

    if (count == 0 || !sources) {
        *outSources = NULL;
        return 0;
    }

    // Allocate our source info array
    NDISourceInfo* infos = (NDISourceInfo*)calloc(count, sizeof(NDISourceInfo));
    for (uint32_t i = 0; i < count; i++) {
        infos[i].name = sources[i].p_ndi_name;      // Points into NDI's internal memory
        infos[i].address = sources[i].p_url_address; // Same
    }

    *outSources = infos;
    return (int)count;
}

void NDIWrapper_DestroyFinder(NDIFinderRef finder) {
    if (finder) NDIlib_find_destroy((NDIlib_find_instance_t)finder);
}

NDIReceiverRef NDIWrapper_CreateReceiver(const char* sourceName, const char* sourceAddress) {
    if (!sourceName) return NULL;

    NDIlib_source_t source;
    memset(&source, 0, sizeof(source));
    source.p_ndi_name = sourceName;
    source.p_url_address = sourceAddress;

    NDIlib_recv_create_v3_t recv_create;
    memset(&recv_create, 0, sizeof(recv_create));
    recv_create.source_to_connect_to = source;
    recv_create.color_format = NDIlib_recv_color_format_BGRX_BGRA;
    recv_create.bandwidth = NDIlib_recv_bandwidth_highest;
    recv_create.allow_video_fields = false;
    recv_create.p_ndi_recv_name = "WasteMix";

    return (NDIReceiverRef)NDIlib_recv_create_v3(&recv_create);
}

bool NDIWrapper_CaptureVideo(NDIReceiverRef receiver, NDIVideoFrame* outFrame, int timeoutMs) {
    if (!receiver || !outFrame) return false;

    memset(outFrame, 0, sizeof(NDIVideoFrame));

    NDIlib_recv_instance_t ndi_recv = (NDIlib_recv_instance_t)receiver;
    NDIlib_video_frame_v2_t video_frame;
    memset(&video_frame, 0, sizeof(video_frame));

    NDIlib_frame_type_e frame_type = NDIlib_recv_capture_v3(ndi_recv, &video_frame, NULL, NULL, timeoutMs);

    if (frame_type != NDIlib_frame_type_video) return false;
    if (!video_frame.p_data || video_frame.xres <= 0 || video_frame.yres <= 0) return false;

    outFrame->width = video_frame.xres;
    outFrame->height = video_frame.yres;
    outFrame->stride = video_frame.line_stride_in_bytes;
    outFrame->data = video_frame.p_data;
    outFrame->fourCC = video_frame.FourCC;

    // Store the original SDK frame verbatim so FreeVideoFrame can pass it back untouched
    memcpy(outFrame->_ndi_frame, &video_frame, sizeof(video_frame) < 128 ? sizeof(video_frame) : 128);

    return true;
}

void NDIWrapper_FreeVideoFrame(NDIReceiverRef receiver, NDIVideoFrame* frame) {
    if (!receiver || !frame || !frame->data) return;

    NDIlib_recv_instance_t ndi_recv = (NDIlib_recv_instance_t)receiver;

    // Pass back the original SDK frame struct — never reconstruct it
    NDIlib_video_frame_v2_t video_frame;
    memcpy(&video_frame, frame->_ndi_frame, sizeof(video_frame) < 128 ? sizeof(video_frame) : 128);

    NDIlib_recv_free_video_v2(ndi_recv, &video_frame);
    frame->data = NULL;
}

void NDIWrapper_DestroyReceiver(NDIReceiverRef receiver) {
    if (receiver) NDIlib_recv_destroy((NDIlib_recv_instance_t)receiver);
}

// --- NDI Send ---

NDISenderRef NDIWrapper_CreateSender(const char* name) {
    NDIlib_send_create_t send_create;
    send_create.p_ndi_name = name;
    send_create.p_groups = NULL;
    send_create.clock_video = true;
    send_create.clock_audio = false;
    return (NDISenderRef)NDIlib_send_create(&send_create);
}

void NDIWrapper_SendVideo(NDISenderRef sender, const uint8_t* data,
                          int width, int height, int stride) {
    if (!sender || !data) return;
    NDIlib_send_instance_t ndi_send = (NDIlib_send_instance_t)sender;

    NDIlib_video_frame_v2_t frame;
    frame.xres = width;
    frame.yres = height;
    frame.FourCC = NDIlib_FourCC_video_type_BGRA;
    frame.frame_rate_N = 60000;
    frame.frame_rate_D = 1001;
    frame.picture_aspect_ratio = (float)width / (float)height;
    frame.frame_format_type = 1; // progressive
    frame.timecode = 0;
    frame.p_data = (uint8_t*)data;
    frame.line_stride_in_bytes = stride;
    frame.p_metadata = NULL;
    frame.timestamp = 0;

    NDIlib_send_send_video_v2(ndi_send, &frame);
}

void NDIWrapper_DestroySender(NDISenderRef sender) {
    if (sender) NDIlib_send_destroy((NDIlib_send_instance_t)sender);
}

#else // !ENABLE_NDI — stub implementations

bool NDIWrapper_Initialize(void) { return false; }
void NDIWrapper_Destroy(void) {}
NDIFinderRef NDIWrapper_CreateFinder(void) { return NULL; }
int NDIWrapper_GetSources(NDIFinderRef finder, NDISourceInfo** outSources) { *outSources = NULL; return 0; }
void NDIWrapper_DestroyFinder(NDIFinderRef finder) {}
NDIReceiverRef NDIWrapper_CreateReceiver(const char* n, const char* a) { return NULL; }
bool NDIWrapper_CaptureVideo(NDIReceiverRef r, NDIVideoFrame* f, int t) { return false; }
void NDIWrapper_FreeVideoFrame(NDIReceiverRef r, NDIVideoFrame* f) {}
void NDIWrapper_DestroyReceiver(NDIReceiverRef r) {}
NDISenderRef NDIWrapper_CreateSender(const char* n) { return NULL; }
void NDIWrapper_SendVideo(NDISenderRef s, const uint8_t* d, int w, int h, int st) {}
void NDIWrapper_DestroySender(NDISenderRef s) {}

#endif
