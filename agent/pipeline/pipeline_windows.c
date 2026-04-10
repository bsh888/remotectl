// pipeline_windows.c — GDI BitBlt screen capture + x264 H.264 encoding
//
// Flow:
//   capture thread: GDI BitBlt → BGR24 pixel buffer
//   encode thread:  x264_encoder_encode → Annex-B → goH264FrameWin()
//
// Requires: libx264 (x264 -dev package or static lib)
// Build:    -lx264 -lgdi32

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <x264.h>

// Forward declaration of Go callback
extern void goH264FrameWin(void *data, int length, int isKeyframe);

// ── diagnostics ──────────────────────────────────────────────────────────────
static volatile int g_cap_frames  = 0;
static volatile int g_enc_frames  = 0;
static volatile int g_last_err    = 0;

void rc_win_get_diag(int *cap_frames, int *enc_frames, int *last_err) {
    if (cap_frames) *cap_frames = g_cap_frames;
    if (enc_frames) *enc_frames = g_enc_frames;
    if (last_err)   *last_err   = g_last_err;
}

// ── global state ──────────────────────────────────────────────────────────────
static CRITICAL_SECTION g_cs;
static volatile int     g_running   = 0;
static HANDLE           g_thread    = NULL;
static x264_t          *g_encoder   = NULL;
static x264_picture_t   g_pic_in;
static int              g_width     = 0;  // output (encoded) width
static int              g_height    = 0;  // output (encoded) height
static int              g_screen_w  = 0;  // physical screen width
static int              g_screen_h  = 0;  // physical screen height
static int              g_fps       = 15;
static int              g_bitrate   = 1000000;

// ── rc_win_check: returns primary monitor width (>0 = display available) ─────
int rc_win_check(void) {
    return GetSystemMetrics(SM_CXSCREEN);
}

// ── Annex-B helper ───────────────────────────────────────────────────────────
static void deliver_nal(x264_nal_t *nals, int nal_count, int is_keyframe) {
    // Calculate total Annex-B size
    int total = 0;
    for (int i = 0; i < nal_count; i++) total += nals[i].i_payload;
    if (total <= 0) return;

    uint8_t *buf = (uint8_t *)malloc(total);
    if (!buf) return;
    int off = 0;
    for (int i = 0; i < nal_count; i++) {
        memcpy(buf + off, nals[i].p_payload, nals[i].i_payload);
        off += nals[i].i_payload;
    }
    goH264FrameWin(buf, total, is_keyframe ? 1 : 0);
    free(buf);
}

// ── Capture + encode thread ──────────────────────────────────────────────────
static DWORD WINAPI capture_thread(LPVOID param) {
    (void)param;

    HDC screen_dc = GetDC(NULL);
    HDC mem_dc    = CreateCompatibleDC(screen_dc);
    HBITMAP bmp   = CreateCompatibleBitmap(screen_dc, g_width, g_height);
    SelectObject(mem_dc, bmp);

    BITMAPINFOHEADER bi = {0};
    bi.biSize        = sizeof(bi);
    bi.biWidth       = g_width;
    bi.biHeight      = -g_height; // top-down
    bi.biPlanes      = 1;
    bi.biBitCount    = 24;
    bi.biCompression = BI_RGB;

    uint8_t *bgr_buf = (uint8_t *)malloc(g_width * g_height * 3);
    if (!bgr_buf) goto cleanup;

    DWORD frame_ms = (g_fps > 0) ? (1000 / g_fps) : 66;
    DWORD pts = 0;

    // When output size == screen size, use fast 1:1 BitBlt.
    // When scale < 1, use StretchBlt with HALFTONE interpolation for quality.
    int need_scale = (g_width != g_screen_w || g_height != g_screen_h);

    while (g_running) {
        DWORD t0 = GetTickCount();

        // Capture (and scale if needed)
        if (need_scale) {
            SetStretchBltMode(mem_dc, HALFTONE);
            SetBrushOrgEx(mem_dc, 0, 0, NULL);
            StretchBlt(mem_dc, 0, 0, g_width, g_height,
                       screen_dc, 0, 0, g_screen_w, g_screen_h,
                       SRCCOPY | CAPTUREBLT);
        } else {
            BitBlt(mem_dc, 0, 0, g_width, g_height, screen_dc, 0, 0, SRCCOPY | CAPTUREBLT);
        }
        GetDIBits(mem_dc, bmp, 0, g_height, bgr_buf, (BITMAPINFO *)&bi, DIB_RGB_COLORS);
        InterlockedIncrement((LONG volatile *)&g_cap_frames);

        // Convert BGR24 → I420 for x264
        EnterCriticalSection(&g_cs);
        x264_t *enc = g_encoder;
        LeaveCriticalSection(&g_cs);
        if (!enc) break;

        // Simple BGR→I420 conversion
        int w = g_width, h = g_height;
        uint8_t *y_plane  = g_pic_in.img.plane[0];
        uint8_t *cb_plane = g_pic_in.img.plane[1];
        uint8_t *cr_plane = g_pic_in.img.plane[2];
        int y_stride  = g_pic_in.img.i_stride[0];
        int cb_stride = g_pic_in.img.i_stride[1];
        int cr_stride = g_pic_in.img.i_stride[2];

        for (int row = 0; row < h; row++) {
            uint8_t *src = bgr_buf + row * w * 3;
            uint8_t *yp  = y_plane + row * y_stride;
            for (int col = 0; col < w; col++) {
                int b = src[col*3+0], g_val = src[col*3+1], r = src[col*3+2];
                yp[col] = (uint8_t)((66*r + 129*g_val + 25*b + 128) >> 8) + 16;
                if ((row & 1) == 0 && (col & 1) == 0) {
                    int ci = (row/2) * cb_stride + col/2;
                    int ri = (row/2) * cr_stride + col/2;
                    cb_plane[ci] = (uint8_t)((-38*r - 74*g_val + 112*b + 128) >> 8) + 128;
                    cr_plane[ri] = (uint8_t)((112*r - 94*g_val - 18*b + 128) >> 8) + 128;
                }
            }
        }

        g_pic_in.i_pts = pts++;

        x264_picture_t pic_out;
        x264_nal_t    *nals;
        int            nal_count = 0;
        int frame_size = x264_encoder_encode(enc, &nals, &nal_count, &g_pic_in, &pic_out);
        if (frame_size > 0) {
            InterlockedIncrement((LONG volatile *)&g_enc_frames);
            int is_key = (pic_out.i_type == X264_TYPE_IDR || pic_out.i_type == X264_TYPE_I) ? 1 : 0;
            deliver_nal(nals, nal_count, is_key);
        }

        // Sleep remainder of frame interval
        DWORD elapsed = GetTickCount() - t0;
        if (elapsed < frame_ms) Sleep(frame_ms - elapsed);
    }

    free(bgr_buf);
cleanup:
    DeleteObject(bmp);
    DeleteDC(mem_dc);
    ReleaseDC(NULL, screen_dc);
    return 0;
}

// ── rc_win_start ─────────────────────────────────────────────────────────────
// Returns: 0 = success, 1 = already running, 2 = DC failed,
//          3 = bitmap failed, 4 = x264 init failed, 5 = thread failed
int rc_win_start(int width, int height, int fps, int bitrate) {
    static int cs_init = 0;
    if (!cs_init) { InitializeCriticalSection(&g_cs); cs_init = 1; }

    EnterCriticalSection(&g_cs);
    if (g_running) { LeaveCriticalSection(&g_cs); return 1; }

    g_screen_w = GetSystemMetrics(SM_CXSCREEN);
    g_screen_h = GetSystemMetrics(SM_CYSCREEN);
    g_width   = (width  > 0) ? width  : g_screen_w;
    g_height  = (height > 0) ? height : g_screen_h;
    // x264 requires dimensions divisible by 2; round down if odd.
    g_width  &= ~1;
    g_height &= ~1;
    g_fps     = (fps    > 0) ? fps    : 15;
    g_bitrate = bitrate;

    // Init x264
    x264_param_t param;
    x264_param_default_preset(&param, "ultrafast", "zerolatency");
    param.i_width        = g_width;
    param.i_height       = g_height;
    param.i_fps_num      = (uint32_t)g_fps;
    param.i_fps_den      = 1;
    param.rc.i_rc_method = X264_RC_ABR;
    param.rc.i_bitrate   = bitrate / 1000; // kbps
    param.i_keyint_max   = g_fps * 2;
    param.b_repeat_headers = 1; // include SPS/PPS before each keyframe
    param.b_annexb         = 1; // Annex-B output
    x264_param_apply_profile(&param, "baseline");

    x264_picture_alloc(&g_pic_in, X264_CSP_I420, g_width, g_height);

    g_encoder = x264_encoder_open(&param);
    if (!g_encoder) {
        x264_picture_clean(&g_pic_in);
        LeaveCriticalSection(&g_cs);
        return 4;
    }

    g_cap_frames = 0;
    g_enc_frames = 0;
    g_last_err   = 0;
    g_running    = 1;

    g_thread = CreateThread(NULL, 0, capture_thread, NULL, 0, NULL);
    if (!g_thread) {
        g_running = 0;
        x264_encoder_close(g_encoder); g_encoder = NULL;
        x264_picture_clean(&g_pic_in);
        LeaveCriticalSection(&g_cs);
        return 5;
    }

    LeaveCriticalSection(&g_cs);
    return 0;
}

// ── rc_win_stop ───────────────────────────────────────────────────────────────
void rc_win_stop(void) {
    EnterCriticalSection(&g_cs);
    if (!g_running) { LeaveCriticalSection(&g_cs); return; }
    g_running = 0;
    HANDLE t  = g_thread; g_thread = NULL;
    x264_t *enc = g_encoder; g_encoder = NULL;
    LeaveCriticalSection(&g_cs);

    if (t) { WaitForSingleObject(t, 3000); CloseHandle(t); }
    if (enc) {
        // Flush delayed frames
        x264_nal_t *nals; int nc = 0;
        x264_picture_t po;
        while (x264_encoder_delayed_frames(enc) > 0) {
            x264_encoder_encode(enc, &nals, &nc, NULL, &po);
        }
        x264_encoder_close(enc);
        x264_picture_clean(&g_pic_in);
    }
}
