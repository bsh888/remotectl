//go:build cgo && darwin

package pipeline

/*
#cgo CFLAGS: -x objective-c -fobjc-arc
#cgo LDFLAGS: -framework ScreenCaptureKit -framework CoreMedia -framework CoreVideo -framework VideoToolbox -framework CoreFoundation -framework Foundation -framework CoreGraphics -framework ApplicationServices

#include <stdint.h>
#include <stdlib.h>

// Declarations only (definitions are in pipeline_darwin.m)
int  rc_pipeline_start(double scale, int fps, int bitrate);
void rc_pipeline_stop(void);
int  rc_check_screen_recording(void);
void rc_get_diag(int *stream_frames, int *vt_calls, int *vt_callbacks, int *last_status);
// goStreamStopped is declared here so the .m file can call it via extern
extern void goStreamStopped(void);
*/
import "C"

import (
	"log"
	"sync"
	"time"
	"unsafe"
)

var (
	gFrameCh chan Frame
	gFPS     int
	gDoneCh  chan struct{}
	gDoneOnce sync.Once
)

// CheckScreenRecording returns true if the process has Screen Recording permission.
func CheckScreenRecording() bool {
	return C.rc_check_screen_recording() != 0
}

var pipelineErrors = map[int]string{
	1: "already running",
	2: "Screen Recording permission not granted — grant in System Settings → Privacy & Security → Screen Recording",
	3: "invalid capture dimensions (display not found?)",
	4: "VideoToolbox H.264 session creation failed",
	5: "SCShareableContent failed — display not found",
	6: "SCStream addStreamOutput failed",
	7: "SCStream startCapture failed",
}

// Done returns a channel that is closed when the pipeline stops unexpectedly
// (e.g. SCStream error). Used by encodePump to trigger a restart.
func Done() <-chan struct{} {
	return gDoneCh
}

// Start initialises the capture + encode pipeline.
// Returns a channel that delivers encoded H.264 Annex-B frames,
// and a non-empty error string if the pipeline failed to start.
func Start(scale float64, fps, bitrate int) (<-chan Frame, string) {
	gFPS = fps
	gFrameCh = make(chan Frame, 16)
	gDoneCh = make(chan struct{})
	gDoneOnce = sync.Once{}
	ret := int(C.rc_pipeline_start(C.double(scale), C.int(fps), C.int(bitrate)))
	if ret != 0 {
		msg := pipelineErrors[ret]
		if msg == "" {
			msg = "unknown error"
		}
		return gFrameCh, msg
	}
	return gFrameCh, ""
}

// Stop shuts down the pipeline and closes the channel returned by Start.
func Stop() {
	C.rc_pipeline_stop()
}

// LogDiag prints internal pipeline counters — call after ~5 s to diagnose zero-frame issues.
func LogDiag() {
	var streamFrames, vtCalls, vtCallbacks, lastStatus C.int
	C.rc_get_diag(&streamFrames, &vtCalls, &vtCallbacks, &lastStatus)
	log.Printf("pipeline diag: scstream_frames=%d  vt_encode_calls=%d  vt_callbacks=%d  last_vt_status=%d",
		int(streamFrames), int(vtCalls), int(vtCallbacks), int(lastStatus))
}

//export goStreamStopped
func goStreamStopped() {
	gDoneOnce.Do(func() {
		if gDoneCh != nil {
			close(gDoneCh)
		}
	})
}

//export goH264Frame
func goH264Frame(data unsafe.Pointer, length C.int, isKeyframe C.int) {
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
		// consumer is slow, drop frame
	}
}
