// Package pipeline provides platform-specific screen capture + H.264 encoding.
// Each platform implementation captures the primary display and delivers
// encoded H.264 Annex-B frames via the channel returned by Start.
package pipeline

import "time"

// Frame holds a single H.264 Annex-B encoded output frame.
type Frame struct {
	Data       []byte
	IsKeyframe bool
	Duration   time.Duration
}
