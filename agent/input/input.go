// Package input injects mouse and keyboard events into the OS.
// Platform-specific implementations are in inject_darwin.go / inject_windows.go / inject_linux.go.
package input

// Event is the wire format sent by the viewer client.
type Event struct {
	Event  string   `json:"event"`  // mousemove|mousedown|mouseup|click|dblclick|scroll|keydown|keyup|paste_text|viewport
	X      float64  `json:"x,omitempty"`
	Y      float64  `json:"y,omitempty"`
	Button int      `json:"button,omitempty"` // 0=left 1=middle 2=right
	Key    string   `json:"key,omitempty"`
	Code   string   `json:"code,omitempty"` // KeyboardEvent.code
	Mods   []string `json:"mods,omitempty"` // ctrl|shift|alt|meta
	DeltaX float64  `json:"dx,omitempty"`
	DeltaY float64  `json:"dy,omitempty"`
	Text   string   `json:"text,omitempty"` // paste_text: unicode string to type
	// viewport: physical pixel dimensions of the viewer's render area.
	// Agent uses these to compute the optimal capture scale.
	ViewportW int `json:"vw,omitempty"`
	ViewportH int `json:"vh,omitempty"`
}

// Handle dispatches an input event to the OS-level injector.
// Implemented per platform in inject_*.go.
func Handle(e Event) { inject(e) }
