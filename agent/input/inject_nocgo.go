// Stub for macOS without CGO (e.g. CI checks). Windows and Linux have pure-Go implementations.
//go:build !cgo && !windows && !linux

package input

import "log"

// inject is a no-op stub used when CGO is disabled (e.g. CI cross-compile checks).
// The agent binary must be built with CGO_ENABLED=1 for real input injection.
func inject(e Event) {
	log.Printf("[input] CGO disabled — cannot inject event: %+v", e)
}

func CheckAccessibility() bool         { return false }
func RequestAccessibilityPrompt() bool { return false }

func Init() {}
