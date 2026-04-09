//go:build cgo && linux

package pipeline

/*
#cgo CFLAGS: -I/usr/include/x264
#cgo LDFLAGS: -lx264 -lX11 -lXext

#include <stdint.h>
#include <stdlib.h>

int  rc_linux_start(int fps, int bitrate);
void rc_linux_stop(void);
int  rc_linux_check(void);
void rc_linux_get_diag(int *cap_frames, int *enc_frames, int *last_err);
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

// CheckScreenRecording always returns true on Linux (no permission system).
func CheckScreenRecording() bool {
	return C.rc_linux_check() != 0
}

// Start initialises the X11 capture + x264 encode pipeline.
func Start(scale float64, fps, bitrate int) (<-chan Frame, string) {
	gFPS = fps
	gFrameCh = make(chan Frame, 16)
	_ = scale
	ret := int(C.rc_linux_start(C.int(fps), C.int(bitrate)))
	if ret != 0 {
		return gFrameCh, linuxError(ret)
	}
	return gFrameCh, ""
}

func linuxError(code int) string {
	errs := map[int]string{
		1: "already running",
		2: "cannot open X11 display (DISPLAY not set?)",
		3: "XShmCreateImage failed",
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
	C.rc_linux_stop()
}

// Done returns a channel that never closes on Linux.
func Done() <-chan struct{} { return make(chan struct{}) }

// RequestKeyframe is a no-op on Linux (keyframe forcing not implemented for x264 path).
func RequestKeyframe() {}

// LogDiag prints diagnostic counters.
func LogDiag() {
	var capFrames, encFrames, lastErr C.int
	C.rc_linux_get_diag(&capFrames, &encFrames, &lastErr)
	log.Printf("pipeline diag: cap_frames=%d  enc_frames=%d  last_err=%d",
		int(capFrames), int(encFrames), int(lastErr))
}

//export goH264FrameLinux
func goH264FrameLinux(data unsafe.Pointer, length C.int, isKeyframe C.int) {
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
