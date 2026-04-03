//go:build !cgo && !windows && !linux

package capture

import "fmt"

// Stub: macOS requires CGO_ENABLED=1 for screen capture.
func Screen(_ int) (*Frame, error) {
	return nil, fmt.Errorf("screen capture requires CGO_ENABLED=1 on this platform")
}

func SetScale(_ float64) {}
