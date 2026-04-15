// pipeline_darwin.m — SCStream (BGRA) → VideoToolbox H.264 → Annex-B → Go callback
//
// Flow:
//   SCStream output callback → VTCompressionSessionEncodeFrame
//   VT encode callback       → AVCC→Annex-B conversion → goH264Frame()
//
// Pixel format: 32BGRA (same as the working JPEG capture path, most compatible)

#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <VideoToolbox/VideoToolbox.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

// Forward declarations of Go callbacks (defined via //export in pipeline_darwin.go)
extern void goH264Frame(void *data, int length, int isKeyframe);
extern void goStreamStopped(void);

// ── Permission check ──────────────────────────────────────────────────────────

int rc_check_screen_recording(void) {
    return CGPreflightScreenCaptureAccess() ? 1 : 0;
}

// ── AVCC → Annex-B conversion ─────────────────────────────────────────────────

static NSData *avccToAnnexB(CMSampleBufferRef sb, BOOL *outIsKey) {
    static const uint8_t kStart[] = {0, 0, 0, 1};

    BOOL isKey = YES;
    CFArrayRef atts = CMSampleBufferGetSampleAttachmentsArray(sb, false);
    if (atts && CFArrayGetCount(atts) > 0) {
        CFDictionaryRef d = (CFDictionaryRef)CFArrayGetValueAtIndex(atts, 0);
        if (CFDictionaryContainsKey(d, kCMSampleAttachmentKey_NotSync)) isKey = NO;
    }
    if (outIsKey) *outIsKey = isKey;

    NSMutableData *out = [NSMutableData data];

    if (isKey) {
        CMFormatDescriptionRef fmt = CMSampleBufferGetFormatDescription(sb);
        size_t n = 0;
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(fmt, 0, NULL, NULL, &n, NULL);
        for (size_t i = 0; i < n; i++) {
            const uint8_t *p = NULL; size_t l = 0;
            if (CMVideoFormatDescriptionGetH264ParameterSetAtIndex(fmt, i, &p, &l, NULL, NULL) == noErr) {
                [out appendBytes:kStart length:4];
                [out appendBytes:p length:l];
            }
        }
    }

    CMBlockBufferRef bb = CMSampleBufferGetDataBuffer(sb);
    size_t total = 0; char *ptr = NULL;
    CMBlockBufferGetDataPointer(bb, 0, NULL, &total, &ptr);

    size_t off = 0;
    while (off + 4 <= total) {
        uint32_t len = 0;
        memcpy(&len, ptr + off, 4);
        len = CFSwapInt32BigToHost(len);
        off += 4;
        if (off + len > total) break;
        [out appendBytes:kStart length:4];
        [out appendBytes:ptr + off length:len];
        off += len;
    }
    return out;
}

// ── Diagnostic counters ───────────────────────────────────────────────────────

static volatile int g_stream_frame_count = 0;
static volatile int g_vt_encode_count    = 0;
static volatile int g_vt_callback_count  = 0;
static volatile int g_last_vt_status     = 0;

void rc_get_diag(int *stream_frames, int *vt_calls, int *vt_callbacks, int *last_status) {
    if (stream_frames) *stream_frames = g_stream_frame_count;
    if (vt_calls)      *vt_calls      = g_vt_encode_count;
    if (vt_callbacks)  *vt_callbacks  = g_vt_callback_count;
    if (last_status)   *last_status   = g_last_vt_status;
}

// ── VT compression callback ───────────────────────────────────────────────────

static void vtCallback(void *ref, void *frameRef, OSStatus status,
                       VTEncodeInfoFlags flags, CMSampleBufferRef sb) {
    (void)ref; (void)frameRef; (void)flags;
    __atomic_fetch_add(&g_vt_callback_count, 1, __ATOMIC_RELAXED);
    if (status != noErr) {
        __atomic_store_n(&g_last_vt_status, (int)status, __ATOMIC_RELAXED);
        NSLog(@"[remotectl/pipeline] vtCallback error status: %d", (int)status);
        return;
    }
    if (!sb || !CMSampleBufferDataIsReady(sb)) return;
    BOOL isKey = NO;
    NSData *data = avccToAnnexB(sb, &isKey);
    if (data.length > 0)
        goH264Frame((void *)data.bytes, (int)data.length, isKey ? 1 : 0);
}

// ── Global state ──────────────────────────────────────────────────────────────

static pthread_mutex_t       g_mu        = PTHREAD_MUTEX_INITIALIZER;
static VTCompressionSessionRef g_vtSession = NULL;
static SCStream             *g_stream    = nil;
static id                    g_output    = nil;
static BOOL                  g_running   = NO;
static volatile int          g_force_keyframe = 0;

// rc_pipeline_request_keyframe sets a flag that causes the next encoded frame
// to be forced as a keyframe (IDR). Called when a viewer sends a PLI/FIR.
void rc_pipeline_request_keyframe(void) {
    __atomic_store_n(&g_force_keyframe, 1, __ATOMIC_RELAXED);
}

// ── SCStream delegate + output ────────────────────────────────────────────────

@interface RCPipelineOutput : NSObject <SCStreamOutput, SCStreamDelegate>
@end

@implementation RCPipelineOutput

- (void)stream:(SCStream *)stream
    didOutputSampleBuffer:(CMSampleBufferRef)sb
    ofType:(SCStreamOutputType)type {
    if (type != SCStreamOutputTypeScreen) return;
    __atomic_fetch_add(&g_stream_frame_count, 1, __ATOMIC_RELAXED);
    pthread_mutex_lock(&g_mu);
    VTCompressionSessionRef vt = g_vtSession;
    pthread_mutex_unlock(&g_mu);
    if (!vt) return;

    CVPixelBufferRef pb = CMSampleBufferGetImageBuffer(sb);
    if (!pb) return;
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sb);
    CMTime dur = CMSampleBufferGetDuration(sb);
    VTEncodeInfoFlags fl = 0;
    __atomic_fetch_add(&g_vt_encode_count, 1, __ATOMIC_RELAXED);

    // If a keyframe was requested (e.g. via RTCP PLI), pass ForceKeyFrame option.
    CFDictionaryRef frameProps = NULL;
    if (__atomic_exchange_n(&g_force_keyframe, 0, __ATOMIC_RELAXED)) {
        CFTypeRef keys[]   = { kVTEncodeFrameOptionKey_ForceKeyFrame };
        CFTypeRef values[] = { kCFBooleanTrue };
        frameProps = CFDictionaryCreate(NULL, keys, values, 1,
                                        &kCFTypeDictionaryKeyCallBacks,
                                        &kCFTypeDictionaryValueCallBacks);
    }
    OSStatus encSt = VTCompressionSessionEncodeFrame(vt, pb, pts, dur, frameProps, NULL, &fl);
    if (frameProps) CFRelease(frameProps);
    if (encSt != noErr) {
        __atomic_store_n(&g_last_vt_status, (int)encSt, __ATOMIC_RELAXED);
        NSLog(@"[remotectl/pipeline] VTCompressionSessionEncodeFrame error: %d", (int)encSt);
    }
}

- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {
    NSLog(@"[remotectl/pipeline] SCStream stopped: %@", error ?: @"(no error)");
    // Clean up state without calling rc_pipeline_stop to avoid mutex re-entry
    pthread_mutex_lock(&g_mu);
    g_running = NO;
    if (g_stream == stream) g_stream = nil;
    g_output = nil;
    if (g_vtSession) {
        VTCompressionSessionInvalidate(g_vtSession);
        CFRelease(g_vtSession);
        g_vtSession = NULL;
    }
    pthread_mutex_unlock(&g_mu);
    // Notify Go side so encodePump can restart
    goStreamStopped();
}
@end

// ── rc_pipeline_start ─────────────────────────────────────────────────────────
//
// Returns: 0 = success
//          1 = already running
//          2 = no Screen Recording permission
//          3 = invalid dimensions
//          4 = VTCompressionSessionCreate failed (OSStatus in NSLog)
//          5 = SCShareableContent failed / display not found
//          6 = addStreamOutput failed
//          7 = startCapture failed (NSError in NSLog)

int rc_pipeline_start(double scale, int fps, int bitrate) {
    pthread_mutex_lock(&g_mu);
    if (g_running) { pthread_mutex_unlock(&g_mu); return 1; }

    if (!CGPreflightScreenCaptureAccess()) {
        pthread_mutex_unlock(&g_mu);
        return 2;
    }

    CGDirectDisplayID disp = CGMainDisplayID();

    // ── Resolve display via SCShareableContent first ──────────────────────────
    // This must happen before VT session creation so we know the actual capture
    // dimensions. If the preferred display is unavailable (e.g. external monitor
    // disconnected or screen locked), fall back to any available display.
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block SCContentFilter *filter = nil;
    __block CGDirectDisplayID actualDisp = disp;
    [SCShareableContent getShareableContentWithCompletionHandler:
        ^(SCShareableContent *c, NSError *e) {
            if (!e) {
                for (SCDisplay *d in c.displays) {
                    if (d.displayID == disp) {
                        filter = [[SCContentFilter alloc] initWithDisplay:d excludingWindows:@[]];
                        break;
                    }
                }
                // Fallback: target display not found, use the first available display
                if (!filter && c.displays.count > 0) {
                    SCDisplay *fallback = c.displays.firstObject;
                    NSLog(@"[remotectl/pipeline] display %u not found, falling back to display %u",
                          disp, fallback.displayID);
                    filter = [[SCContentFilter alloc] initWithDisplay:fallback excludingWindows:@[]];
                    actualDisp = fallback.displayID;
                }
            }
            dispatch_semaphore_signal(sem);
        }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5LL * NSEC_PER_SEC));

    if (!filter) {
        NSLog(@"[remotectl/pipeline] failed to get shareable content for display %u", disp);
        pthread_mutex_unlock(&g_mu);
        return 5;
    }

    // Compute capture dimensions from the actual display we will capture.
    size_t physW = CGDisplayPixelsWide(actualDisp);
    size_t physH = CGDisplayPixelsHigh(actualDisp);
    int w = (int)(physW * scale);
    int h = (int)(physH * scale);
    if (w <= 0 || h <= 0) {
        NSLog(@"[remotectl/pipeline] invalid dimensions %dx%d (physW=%zu physH=%zu scale=%.2f)",
              w, h, physW, physH, scale);
        pthread_mutex_unlock(&g_mu);
        return 3;
    }

    // ── VideoToolbox H.264 session ────────────────────────────────────────────
    // Use BGRA pixel format: most compatible with SCStream + VT on all macOS versions.
    CFMutableDictionaryRef pbAttr = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    int32_t pixFmt = kCVPixelFormatType_32BGRA;
    CFNumberRef fmtNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &pixFmt);
    CFDictionarySetValue(pbAttr, kCVPixelBufferPixelFormatTypeKey, fmtNum);
    CFRelease(fmtNum);

    VTCompressionSessionRef vt = NULL;
    OSStatus st = VTCompressionSessionCreate(
        kCFAllocatorDefault, w, h,
        kCMVideoCodecType_H264,
        NULL, pbAttr, NULL,
        vtCallback, NULL, &vt);
    CFRelease(pbAttr);

    if (st != noErr || !vt) {
        NSLog(@"[remotectl/pipeline] VTCompressionSessionCreate failed: %d", (int)st);
        pthread_mutex_unlock(&g_mu);
        return 4;
    }

    // Real-time, no B-frames (zero reorder delay)
    VTSessionSetProperty(vt, kVTCompressionPropertyKey_RealTime,             kCFBooleanTrue);
    VTSessionSetProperty(vt, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse);

    // High Profile: CABAC entropy coding gives ~15-20% better compression than
    // Baseline CAVLC at the same bitrate — noticeably clearer image.
    VTSessionSetProperty(vt, kVTCompressionPropertyKey_ProfileLevel,
                         kVTProfileLevel_H264_High_AutoLevel);
    VTSessionSetProperty(vt, kVTCompressionPropertyKey_H264EntropyMode,
                         kVTH264EntropyMode_CABAC);

    // Tell VT the expected frame rate so its rate-control model is accurate.
    int32_t fpsI = fps;
    CFNumberRef fpsNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &fpsI);
    VTSessionSetProperty(vt, kVTCompressionPropertyKey_ExpectedFrameRate, fpsNum);
    CFRelease(fpsNum);

    // Average bitrate target
    int64_t br = bitrate;
    CFNumberRef brNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt64Type, &br);
    VTSessionSetProperty(vt, kVTCompressionPropertyKey_AverageBitRate, brNum);
    CFRelease(brNum);

    // Peak bitrate cap: allow at most 2× target per second to keep keyframe
    // bursts from stalling the network and spiking RTT.
    CFNumberRef limitBytes = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt64Type,
                                           &(int64_t){br * 2 / 8});
    CFNumberRef limitSecs  = CFNumberCreate(kCFAllocatorDefault, kCFNumberFloat64Type,
                                           &(double){1.0});
    CFTypeRef limitPair[2] = {limitBytes, limitSecs};
    CFArrayRef limits = CFArrayCreate(kCFAllocatorDefault, limitPair, 2, &kCFTypeArrayCallBacks);
    VTSessionSetProperty(vt, kVTCompressionPropertyKey_DataRateLimits, limits);
    CFRelease(limitBytes); CFRelease(limitSecs); CFRelease(limits);

    // Keyframe every 2 s — short enough to recover quickly after packet loss.
    int32_t gop = fps * 2;
    CFNumberRef gopNum = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &gop);
    VTSessionSetProperty(vt, kVTCompressionPropertyKey_MaxKeyFrameInterval, gopNum);
    CFRelease(gopNum);

    VTCompressionSessionPrepareToEncodeFrames(vt);

    // ── SCStream ──────────────────────────────────────────────────────────────
    SCStreamConfiguration *cfg = [[SCStreamConfiguration alloc] init];
    cfg.width         = (size_t)w;
    cfg.height        = (size_t)h;
    cfg.pixelFormat   = kCVPixelFormatType_32BGRA;
    cfg.capturesAudio = NO;
    cfg.showsCursor   = YES;
    cfg.minimumFrameInterval = CMTimeMake(1, fps);
    // Reduce the internal frame queue from the default (8) to 2.
    // A smaller queue means the encoder always works on the freshest frame
    // rather than draining a backlog, cutting capture→encode latency.
    // queueDepth was added in macOS 14.0.
    if (@available(macOS 14.0, *)) {
        cfg.queueDepth = 2;
    }

    RCPipelineOutput *output = [[RCPipelineOutput alloc] init];
    SCStream *stream = [[SCStream alloc] initWithFilter:filter configuration:cfg delegate:output];

    NSError *addErr = nil;
    BOOL added = [stream addStreamOutput:output
                                    type:SCStreamOutputTypeScreen
                      sampleHandlerQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0)
                                   error:&addErr];
    if (!added || addErr) {
        NSLog(@"[remotectl/pipeline] addStreamOutput failed: %@", addErr);
        VTCompressionSessionInvalidate(vt); CFRelease(vt);
        pthread_mutex_unlock(&g_mu);
        return 6;
    }

    dispatch_semaphore_t sem2 = dispatch_semaphore_create(0);
    __block NSError *startErr = nil;
    [stream startCaptureWithCompletionHandler:^(NSError *e) {
        startErr = e;
        dispatch_semaphore_signal(sem2);
    }];
    dispatch_semaphore_wait(sem2, dispatch_time(DISPATCH_TIME_NOW, 5LL * NSEC_PER_SEC));

    if (startErr) {
        NSLog(@"[remotectl/pipeline] SCStream start failed: %@", startErr);
        VTCompressionSessionInvalidate(vt); CFRelease(vt);
        pthread_mutex_unlock(&g_mu);
        return 7;
    }

    g_vtSession = vt;
    g_stream    = stream;
    g_output    = output;
    g_running   = YES;
    g_stream_frame_count = 0;
    g_vt_encode_count    = 0;
    g_vt_callback_count  = 0;
    g_last_vt_status     = 0;
    NSLog(@"[remotectl/pipeline] started %dx%d @%dfps %dbps", w, h, fps, bitrate);
    pthread_mutex_unlock(&g_mu);
    return 0;
}

void rc_pipeline_stop(void) {
    pthread_mutex_lock(&g_mu);
    if (!g_running) { pthread_mutex_unlock(&g_mu); return; }
    g_running = NO;
    SCStream *s = g_stream; g_stream = nil;
    g_output = nil;
    VTCompressionSessionRef vt = g_vtSession; g_vtSession = NULL;
    pthread_mutex_unlock(&g_mu);

    // Release outside the lock so delegate callbacks don't deadlock
    if (s) [s stopCaptureWithCompletionHandler:nil];
    if (vt) {
        VTCompressionSessionCompleteFrames(vt, kCMTimeInvalid);
        VTCompressionSessionInvalidate(vt);
        CFRelease(vt);
    }
    NSLog(@"[remotectl/pipeline] stopped");
}

void rc_native_size(int *w, int *h) {
    CGDirectDisplayID disp = CGMainDisplayID();
    *w = (int)CGDisplayPixelsWide(disp);
    *h = (int)CGDisplayPixelsHigh(disp);
}
