// capture_darwin.m — SCStream-based screen capture, macOS 12.3+
//
// Compiled with -fobjc-arc.
// Uses SCStream (continuous frame stream) instead of SCScreenshotManager,
// which is more stable across macOS versions and avoids AppKit entirely.
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <ImageIO/ImageIO.h>
#import <Foundation/Foundation.h>
#include <ApplicationServices/ApplicationServices.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    uint8_t *data;
    size_t   len;
    int      width;
    int      height;
    int      err; // 1=no permission, 2=capture error
} RCFrame;

// ── Frame output collector ────────────────────────────────────────────────────

@interface RCOutput : NSObject <SCStreamOutput>
- (CMSampleBufferRef)nextFrameTimeout:(double)sec; // caller must CFRelease
@end

@implementation RCOutput {
    pthread_mutex_t      _mu;
    dispatch_semaphore_t _sem;
    CMSampleBufferRef    _latest;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    pthread_mutex_init(&_mu, NULL);
    _sem = dispatch_semaphore_create(0);
    return self;
}

- (void)stream:(SCStream *)stream
    didOutputSampleBuffer:(CMSampleBufferRef)sb
    ofType:(SCStreamOutputType)type {
    static BOOL first = YES;
    if (first) { first = NO; NSLog(@"[remotectl] first frame, type=%ld", (long)type); }
    pthread_mutex_lock(&_mu);
    if (_latest) { CFRelease(_latest); }
    _latest = (CMSampleBufferRef)CFRetain(sb);
    pthread_mutex_unlock(&_mu);
    dispatch_semaphore_signal(_sem);
}

- (CMSampleBufferRef)nextFrameTimeout:(double)sec {
    long r = dispatch_semaphore_wait(
        _sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(sec * NSEC_PER_SEC)));
    if (r != 0) return NULL;
    pthread_mutex_lock(&_mu);
    CMSampleBufferRef buf = _latest;
    _latest = NULL;
    pthread_mutex_unlock(&_mu);
    return buf;
}

- (void)dealloc {
    if (_latest) { CFRelease(_latest); }
    pthread_mutex_destroy(&_mu);
}
@end

// ── Global stream state ───────────────────────────────────────────────────────

static pthread_mutex_t  g_mu  = PTHREAD_MUTEX_INITIALIZER;
static SCStream        *g_stream   = nil;
static RCOutput        *g_output   = nil;
static id               g_delegate = nil;
static CGDirectDisplayID g_dispID  = 0;
static double           g_scale    = 0.5; // default: half physical pixels (logical res on 2x Retina)

void rc_set_scale(double scale) {
    pthread_mutex_lock(&g_mu);
    g_scale = scale;
    // Reset stream so it restarts with new resolution on next capture
    if (g_stream) {
        [g_stream stopCaptureWithCompletionHandler:nil];
        g_stream = nil; g_output = nil; g_delegate = nil;
    }
    pthread_mutex_unlock(&g_mu);
}

// ── Stream error delegate ─────────────────────────────────────────────────────

@interface RCDelegate : NSObject <SCStreamDelegate>
@end
@implementation RCDelegate
- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {
    if (error) {
        NSLog(@"[remotectl] SCStream stopped: %@", error);
    }
    pthread_mutex_lock(&g_mu);
    g_stream   = nil;
    g_output   = nil;
    g_delegate = nil;
    pthread_mutex_unlock(&g_mu);
}
@end

// Must be called with g_mu held.
static void resetStream_locked(void) {
    if (g_stream) {
        [g_stream stopCaptureWithCompletionHandler:nil];
        g_stream = nil;
    }
    g_output   = nil;
    g_delegate = nil;
}

// Build and start an SCStream. Returns YES on success.
// Must be called with g_mu held.
static BOOL startStream_locked(void) {
    if (!CGPreflightScreenCaptureAccess()) return NO;

    g_dispID = CGMainDisplayID();

    // ── Get shareable content ──
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block SCContentFilter *filter = nil;

    [SCShareableContent getShareableContentWithCompletionHandler:
        ^(SCShareableContent *content, NSError *err) {
            if (!err) {
                for (SCDisplay *d in content.displays) {
                    if (d.displayID == g_dispID) {
                        filter = [[SCContentFilter alloc]
                            initWithDisplay:d excludingWindows:@[]];
                        break;
                    }
                }
            }
            dispatch_semaphore_signal(sem);
        }
    ];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5LL * NSEC_PER_SEC));
    if (!filter) return NO;

    // ── Configure stream ──
    // Capture at physical pixels but allow a scale-down factor (set via rc_set_scale).
    // Mouse coordinates are remapped in inject_darwin.go before CGEventPost.
    SCStreamConfiguration *cfg = [[SCStreamConfiguration alloc] init];
    size_t physW = CGDisplayPixelsWide(g_dispID);
    size_t physH = CGDisplayPixelsHigh(g_dispID);
    cfg.width          = (size_t)(physW * g_scale);
    cfg.height         = (size_t)(physH * g_scale);
    cfg.pixelFormat    = kCVPixelFormatType_32BGRA;
    cfg.capturesAudio  = NO;
    cfg.showsCursor    = YES;

    // ── Create stream + output ──
    g_delegate = [[RCDelegate alloc] init];
    g_output   = [[RCOutput alloc] init];
    SCStream *stream = [[SCStream alloc] initWithFilter:filter
                                          configuration:cfg
                                               delegate:g_delegate];

    NSError *addErr = nil;
    BOOL added = [stream addStreamOutput:g_output
                                    type:SCStreamOutputTypeScreen
                      sampleHandlerQueue:dispatch_get_global_queue(
                                             DISPATCH_QUEUE_PRIORITY_HIGH, 0)
                                   error:&addErr];
    if (!added || addErr) { g_output = nil; g_delegate = nil; return NO; }

    // ── Start capture ──
    dispatch_semaphore_t sem2 = dispatch_semaphore_create(0);
    __block NSError *startErr = nil;
    [stream startCaptureWithCompletionHandler:^(NSError *err) {
        startErr = err;
        dispatch_semaphore_signal(sem2);
    }];
    dispatch_semaphore_wait(sem2, dispatch_time(DISPATCH_TIME_NOW, 5LL * NSEC_PER_SEC));

    if (startErr) { g_output = nil; g_delegate = nil; return NO; }

    g_stream = stream;
    return YES;
}

static BOOL ensureStream(void) {
    pthread_mutex_lock(&g_mu);
    BOOL ok = (g_stream != nil);
    if (!ok) ok = startStream_locked();
    pthread_mutex_unlock(&g_mu);
    return ok;
}

// ── CVPixelBuffer → CGImage ───────────────────────────────────────────────────

static CGImageRef pixelBufferToCGImage(CVPixelBufferRef pb) {
    CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);

    void   *base     = CVPixelBufferGetBaseAddress(pb);
    size_t  width    = CVPixelBufferGetWidth(pb);
    size_t  height   = CVPixelBufferGetHeight(pb);
    size_t  rowBytes = CVPixelBufferGetBytesPerRow(pb);

    // kCVPixelFormatType_32BGRA → BGRA = little-endian ARGB
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(
        base, width, height, 8, rowBytes, cs,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(cs);

    CGImageRef img = ctx ? CGBitmapContextCreateImage(ctx) : NULL;
    if (ctx) CGContextRelease(ctx);

    CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
    return img; // caller must CGImageRelease
}

// ── CGImage → JPEG bytes (ImageIO, no AppKit) ─────────────────────────────────

static NSData *cgImageToJPEG(CGImageRef img, float quality) {
    NSMutableData *buf = [NSMutableData data];
    CGImageDestinationRef dest = CGImageDestinationCreateWithData(
        (__bridge CFMutableDataRef)buf, CFSTR("public.jpeg"), 1, NULL);
    if (!dest) return nil;
    NSDictionary *opts = @{
        (__bridge id)kCGImageDestinationLossyCompressionQuality: @(quality)
    };
    CGImageDestinationAddImage(dest, img, (__bridge CFDictionaryRef)opts);
    BOOL ok = CGImageDestinationFinalize(dest);
    CFRelease(dest);
    return ok ? buf : nil;
}

// ── Public API ────────────────────────────────────────────────────────────────

RCFrame rc_capture_jpeg(int quality) {
    RCFrame f = {0};

    if (!ensureStream()) {
        f.err = 1; // permission not granted or stream failed to start
        return f;
    }

    // Wait up to 1 s for a frame. Don't kill the stream on timeout — it may just
    // be starting up. The delegate resets g_stream if the stream actually stops.
    CMSampleBufferRef sb = [g_output nextFrameTimeout:1.0];
    if (!sb) {
        f.err = 2;
        return f;
    }

    CVPixelBufferRef pb = CMSampleBufferGetImageBuffer(sb);
    if (!pb) { CFRelease(sb); f.err = 2; return f; }

    f.width  = (int)CVPixelBufferGetWidth(pb);
    f.height = (int)CVPixelBufferGetHeight(pb);

    CGImageRef img = pixelBufferToCGImage(pb);
    CFRelease(sb); // releases pb indirectly (CMSampleBuffer owns it)

    if (!img) { f.err = 2; return f; }

    NSData *jpeg = cgImageToJPEG(img, (float)quality / 100.0f);
    CGImageRelease(img);

    if (!jpeg || jpeg.length == 0) { f.err = 2; return f; }

    f.len  = jpeg.length;
    f.data = (uint8_t *)malloc(f.len);
    if (f.data) memcpy(f.data, jpeg.bytes, f.len);
    return f;
}

void rc_free(void *p) { free(p); }
