//go:build windows

package capture

import (
	"bytes"
	"fmt"
	"image/jpeg"

	"github.com/kbinani/screenshot"
)

func Screen(quality int) (*Frame, error) {
	n := screenshot.NumActiveDisplays()
	if n == 0 {
		return nil, fmt.Errorf("no active displays")
	}
	bounds := screenshot.GetDisplayBounds(0)
	img, err := screenshot.CaptureRect(bounds)
	if err != nil {
		return nil, fmt.Errorf("capture: %w", err)
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: quality}); err != nil {
		return nil, fmt.Errorf("jpeg: %w", err)
	}
	return &Frame{Data: buf.Bytes(), Width: bounds.Dx(), Height: bounds.Dy()}, nil
}

func SetScale(_ float64) {}
