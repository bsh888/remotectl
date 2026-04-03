// Package capture provides cross-platform screen capture.
// Platform implementations: capture_darwin.go (CGO/CoreGraphics),
// capture_windows.go and capture_linux.go (kbinani/screenshot).
package capture

// Frame holds one captured screenshot as a JPEG byte slice.
type Frame struct {
	Data   []byte
	Width  int
	Height int
}
