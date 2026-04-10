//go:build cgo && windows

package pipeline

/*
#cgo CFLAGS: -I${SRCDIR}/x264
#cgo LDFLAGS: -L${SRCDIR}/x264 -lx264 -lgdi32 -lole32

#include <stdint.h>
#include <stdlib.h>
#include <windows.h>

int  rc_win_start(int width, int height, int fps, int bitrate);
void rc_win_stop(void);
void rc_win_get_diag(int *cap_frames, int *enc_frames, int *last_err);
*/
import "C"

import (
	"log"
	"time"
	"unsafe"
)

var (
	gFrameCh chan Frame
	gFPS     int
)

// CheckScreenRecording always returns true on Windows (no permission needed for GDI).
func CheckScreenRecording() bool { return true }

// Start initialises the GDI capture + x264 encode pipeline.
func Start(scale float64, fps, bitrate int) (<-chan Frame, string) {
	gFPS = fps
	gFrameCh = make(chan Frame, 16)

	// Apply scale to reduce capture resolution (bandwidth / CPU savings).
	// GetSystemMetrics(0/1) returns SM_CXSCREEN / SM_CYSCREEN.
	screenW := int(C.GetSystemMetrics(0))
	screenH := int(C.GetSystemMetrics(1))
	if scale <= 0 {
		scale = 1.0
	}
	w := int(float64(screenW)*scale) & ^1 // round down to even
	h := int(float64(screenH)*scale) & ^1
	if w <= 0 {
		w = screenW & ^1
	}
	if h <= 0 {
		h = screenH & ^1
	}
	ret := int(C.rc_win_start(C.int(w), C.int(h), C.int(fps), C.int(bitrate)))
	if ret != 0 {
		return gFrameCh, winError(ret)
	}
	return gFrameCh, ""
}

func winError(code int) string {
	errs := map[int]string{
		1: "already running",
		2: "CreateDC failed",
		3: "CreateCompatibleBitmap failed",
		4: "x264 encoder init failed",
		5: "capture thread failed to start",
	}
	if s, ok := errs[code]; ok {
		return s
	}
	return "unknown error"
}

// Stop shuts down the pipeline.
func Stop() {
	C.rc_win_stop()
}

// Done returns a channel that never closes on Windows (capture thread doesn't stop unexpectedly).
func Done() <-chan struct{} { return make(chan struct{}) }

// RequestKeyframe is a no-op on Windows (keyframe forcing not implemented for x264 path).
func RequestKeyframe() {}

// LogDiag prints diagnostic counters.
func LogDiag() {
	var capFrames, encFrames, lastErr C.int
	C.rc_win_get_diag(&capFrames, &encFrames, &lastErr)
	log.Printf("pipeline diag: cap_frames=%d  enc_frames=%d  last_err=%d",
		int(capFrames), int(encFrames), int(lastErr))
}

//export goH264FrameWin
func goH264FrameWin(data unsafe.Pointer, length C.int, isKeyframe C.int) {
	ch := gFrameCh
	if ch == nil || length == 0 {
		return
	}
	b := make([]byte, int(length))
	copy(b, (*[1 << 30]byte)(data)[:int(length)])

	fps := gFPS
	if fps <= 0 {
		fps = 15
	}
	f := Frame{
		Data:       b,
		IsKeyframe: isKeyframe != 0,
		Duration:   time.Second / time.Duration(fps),
	}
	select {
	case ch <- f:
	default:
	}
}
