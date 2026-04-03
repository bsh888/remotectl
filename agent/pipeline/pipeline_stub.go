//go:build !cgo || (!darwin && !windows && !linux)

package pipeline

// CheckScreenRecording always returns true on unsupported platforms.
func CheckScreenRecording() bool { return true }

// Start is a no-op on unsupported platforms.
func Start(_ float64, _, _ int) (<-chan Frame, string) {
	return make(chan Frame), ""
}

// Stop is a no-op on unsupported platforms.
func Stop() {}

// LogDiag is a no-op on unsupported platforms.
func LogDiag() {}

// Done returns a channel that never closes on unsupported platforms.
func Done() <-chan struct{} { return make(chan struct{}) }
