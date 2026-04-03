//go:build cgo && darwin

package capture

/*
#cgo CFLAGS: -x objective-c -fobjc-arc
#cgo LDFLAGS: -framework ScreenCaptureKit -framework CoreGraphics -framework CoreMedia -framework CoreVideo -framework ImageIO -framework Foundation -framework ApplicationServices
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    uint8_t *data;
    size_t   len;
    int      width;
    int      height;
    int      err;   // 1 = permission denied, 2 = other error
} RCFrame;

// Forward declaration; implemented in capture_darwin.m
RCFrame rc_capture_jpeg(int quality);
void rc_free(void *p);
void rc_set_scale(double scale);
*/
import "C"

import (
	"fmt"
	"unsafe"
)

// SetScale sets the capture resolution scale factor (0.25–1.0).
// 0.5 = half physical pixels (equals logical resolution on 2x Retina), 4x smaller frames.
func SetScale(scale float64) {
	C.rc_set_scale(C.double(scale))
}

// Screen captures the primary display as a JPEG frame.
//
// macOS 15+ requires "Screen Recording" permission:
// System Settings → Privacy & Security → Screen Recording → enable the agent.
func Screen(quality int) (*Frame, error) {
	f := C.rc_capture_jpeg(C.int(quality))
	if f.err == 1 {
		return nil, fmt.Errorf("screen capture: Screen Recording permission not granted — " +
			"grant it in System Settings → Privacy & Security → Screen Recording")
	}
	if f.data == nil || f.err != 0 {
		return nil, fmt.Errorf("screen capture failed (err=%d)", int(f.err))
	}
	defer C.rc_free(unsafe.Pointer(f.data))

	data := make([]byte, int(f.len))
	copy(data, unsafe.Slice((*byte)(unsafe.Pointer(f.data)), int(f.len)))

	return &Frame{
		Data:   data,
		Width:  int(f.width),
		Height: int(f.height),
	}, nil
}
