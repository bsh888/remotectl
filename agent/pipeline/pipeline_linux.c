// pipeline_linux.c — X11 XShm screen capture + x264 H.264 encoding
//
// Flow:
//   capture thread: XShmGetImage → BGRx pixel buffer → I420
//   encode:         x264_encoder_encode → Annex-B → goH264FrameLinux()
//
// Requires: libx264-dev, libx11-dev, libxext-dev
// Build:    -lx264 -lX11 -lXext

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <pthread.h>
#include <time.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/extensions/XShm.h>
#include <sys/ipc.h>
#include <sys/shm.h>
#include <x264.h>

// Forward declaration of Go callback
extern void goH264FrameLinux(void *data, int length, int isKeyframe);

// ── diagnostics ──────────────────────────────────────────────────────────────
static volatile int g_cap_frames = 0;
static volatile int g_enc_frames = 0;
static volatile int g_last_err   = 0;

void rc_linux_get_diag(int *cap_frames, int *enc_frames, int *last_err) {
    if (cap_frames) *cap_frames = __atomic_load_n(&g_cap_frames, __ATOMIC_RELAXED);
    if (enc_frames) *enc_frames = __atomic_load_n(&g_enc_frames, __ATOMIC_RELAXED);
    if (last_err)   *last_err   = __atomic_load_n(&g_last_err,   __ATOMIC_RELAXED);
}

// ── global state ──────────────────────────────────────────────────────────────
static pthread_mutex_t  g_mu      = PTHREAD_MUTEX_INITIALIZER;
static volatile int     g_running = 0;
static pthread_t        g_thread;
static x264_t          *g_encoder = NULL;
static x264_picture_t   g_pic_in;
static int              g_width   = 0;
static int              g_height  = 0;
static int              g_fps     = 15;
static int              g_bitrate = 1000000;

// ── check X11 display is available ───────────────────────────────────────────
int rc_linux_check(void) {
    const char *d = getenv("DISPLAY");
    return (d && d[0]) ? 1 : 0;
}

// ── Annex-B delivery ─────────────────────────────────────────────────────────
static void deliver_nal(x264_nal_t *nals, int nal_count, int is_keyframe) {
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
    goH264FrameLinux(buf, total, is_keyframe);
    free(buf);
}

// ── BGRx → I420 conversion ────────────────────────────────────────────────────
static void bgrx_to_i420(const uint8_t *src, int w, int h,
                          uint8_t *y, int ys, uint8_t *cb, int cbs, uint8_t *cr, int crs) {
    for (int row = 0; row < h; row++) {
        const uint8_t *s = src + row * w * 4;
        uint8_t *yp = y + row * ys;
        for (int col = 0; col < w; col++) {
            int b = s[col*4+0], g = s[col*4+1], r = s[col*4+2];
            yp[col] = (uint8_t)(((66*r + 129*g + 25*b + 128) >> 8) + 16);
            if ((row & 1) == 0 && (col & 1) == 0) {
                cb[(row/2)*cbs + col/2] = (uint8_t)(((-38*r - 74*g + 112*b + 128) >> 8) + 128);
                cr[(row/2)*crs + col/2] = (uint8_t)(((112*r - 94*g - 18*b + 128) >> 8) + 128);
            }
        }
    }
}

// ── Capture + encode thread ──────────────────────────────────────────────────
static void *capture_thread_fn(void *arg) {
    (void)arg;

    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) { __atomic_store_n(&g_last_err, 2, __ATOMIC_RELAXED); return NULL; }

    int screen = DefaultScreen(dpy);
    Window root = RootWindow(dpy, screen);

    // Try XShm
    int shm_ok = XShmQueryExtension(dpy);
    XShmSegmentInfo shminfo = {0};
    XImage *img = NULL;

    if (shm_ok) {
        img = XShmCreateImage(dpy, DefaultVisual(dpy, screen), DefaultDepth(dpy, screen),
                              ZPixmap, NULL, &shminfo, (unsigned)g_width, (unsigned)g_height);
        if (img) {
            shminfo.shmid = shmget(IPC_PRIVATE, (size_t)(img->bytes_per_line * img->height),
                                   IPC_CREAT | 0600);
            if (shminfo.shmid < 0) { XDestroyImage(img); img = NULL; }
            else {
                shminfo.shmaddr = img->data = (char *)shmat(shminfo.shmid, 0, 0);
                shminfo.readOnly = False;
                if (!XShmAttach(dpy, &shminfo)) { XDestroyImage(img); img = NULL; }
            }
        }
        shm_ok = (img != NULL);
    }

    long frame_ns = (g_fps > 0) ? (1000000000L / g_fps) : 66666666L;

    while (g_running) {
        struct timespec t0;
        clock_gettime(CLOCK_MONOTONIC, &t0);

        // Capture frame
        if (shm_ok) {
            XShmGetImage(dpy, root, img, 0, 0, AllPlanes);
        } else {
            if (img) XDestroyImage(img);
            img = XGetImage(dpy, root, 0, 0, (unsigned)g_width, (unsigned)g_height, AllPlanes, ZPixmap);
        }
        if (!img) break;
        __atomic_fetch_add(&g_cap_frames, 1, __ATOMIC_RELAXED);

        // Convert to I420
        pthread_mutex_lock(&g_mu);
        x264_t *enc = g_encoder;
        pthread_mutex_unlock(&g_mu);
        if (!enc) break;

        bgrx_to_i420((const uint8_t *)img->data, g_width, g_height,
                     g_pic_in.img.plane[0], g_pic_in.img.i_stride[0],
                     g_pic_in.img.plane[1], g_pic_in.img.i_stride[1],
                     g_pic_in.img.plane[2], g_pic_in.img.i_stride[2]);

        static long pts = 0;
        g_pic_in.i_pts = pts++;

        x264_picture_t pic_out;
        x264_nal_t    *nals;
        int            nal_count = 0;
        int sz = x264_encoder_encode(enc, &nals, &nal_count, &g_pic_in, &pic_out);
        if (sz > 0) {
            __atomic_fetch_add(&g_enc_frames, 1, __ATOMIC_RELAXED);
            int is_key = (pic_out.i_type == X264_TYPE_IDR || pic_out.i_type == X264_TYPE_I) ? 1 : 0;
            deliver_nal(nals, nal_count, is_key);
        }

        // Sleep remainder of frame interval
        struct timespec t1;
        clock_gettime(CLOCK_MONOTONIC, &t1);
        long elapsed_ns = (t1.tv_sec - t0.tv_sec) * 1000000000L + (t1.tv_nsec - t0.tv_nsec);
        long sleep_ns = frame_ns - elapsed_ns;
        if (sleep_ns > 0) {
            struct timespec ts = { .tv_sec = sleep_ns / 1000000000L, .tv_nsec = sleep_ns % 1000000000L };
            nanosleep(&ts, NULL);
        }
    }

    if (shm_ok && img) {
        XShmDetach(dpy, &shminfo);
        XDestroyImage(img);
        shmdt(shminfo.shmaddr);
        shmctl(shminfo.shmid, IPC_RMID, 0);
    } else if (img) {
        XDestroyImage(img);
    }
    XCloseDisplay(dpy);
    return NULL;
}

// ── rc_linux_start ────────────────────────────────────────────────────────────
int rc_linux_start(int fps, int bitrate) {
    pthread_mutex_lock(&g_mu);
    if (g_running) { pthread_mutex_unlock(&g_mu); return 1; }

    // Query display dimensions
    Display *dpy = XOpenDisplay(NULL);
    if (!dpy) { pthread_mutex_unlock(&g_mu); return 2; }
    int screen  = DefaultScreen(dpy);
    g_width     = DisplayWidth(dpy, screen);
    g_height    = DisplayHeight(dpy, screen);
    XCloseDisplay(dpy);

    g_fps     = (fps     > 0) ? fps     : 15;
    g_bitrate = (bitrate > 0) ? bitrate : 1000000;

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
    param.b_repeat_headers = 1;
    param.b_annexb         = 1;
    x264_param_apply_profile(&param, "baseline");

    x264_picture_alloc(&g_pic_in, X264_CSP_I420, g_width, g_height);

    g_encoder = x264_encoder_open(&param);
    if (!g_encoder) {
        x264_picture_clean(&g_pic_in);
        pthread_mutex_unlock(&g_mu);
        return 4;
    }

    g_cap_frames = 0;
    g_enc_frames = 0;
    g_last_err   = 0;
    g_running    = 1;

    if (pthread_create(&g_thread, NULL, capture_thread_fn, NULL) != 0) {
        g_running = 0;
        x264_encoder_close(g_encoder); g_encoder = NULL;
        x264_picture_clean(&g_pic_in);
        pthread_mutex_unlock(&g_mu);
        return 5;
    }

    pthread_mutex_unlock(&g_mu);
    return 0;
}

// ── rc_linux_stop ─────────────────────────────────────────────────────────────
void rc_linux_stop(void) {
    pthread_mutex_lock(&g_mu);
    if (!g_running) { pthread_mutex_unlock(&g_mu); return; }
    g_running = 0;
    pthread_t t   = g_thread;
    x264_t *enc   = g_encoder; g_encoder = NULL;
    pthread_mutex_unlock(&g_mu);

    pthread_join(t, NULL);
    if (enc) {
        x264_nal_t *nals; int nc = 0;
        x264_picture_t po;
        while (x264_encoder_delayed_frames(enc) > 0)
            x264_encoder_encode(enc, &nals, &nc, NULL, &po);
        x264_encoder_close(enc);
        x264_picture_clean(&g_pic_in);
    }
}
