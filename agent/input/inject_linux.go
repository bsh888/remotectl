//go:build linux

package input

import (
	"log"
	"os/exec"
	"strconv"
)

// Linux implementation uses xdotool (requires: apt install xdotool / brew install xdotool).
// For a production agent, replace with direct XTest/XI2 CGO calls.

func inject(e Event) {
	switch e.Event {
	case "mousemove":
		run("xdotool", "mousemove", itoa(e.X), itoa(e.Y))
	case "mousedown":
		run("xdotool", "mousedown", xbtn(e.Button))
	case "mouseup":
		run("xdotool", "mouseup", xbtn(e.Button))
	case "click":
		run("xdotool", "click", xbtn(e.Button))
	case "dblclick":
		run("xdotool", "click", "--repeat", "2", xbtn(e.Button))
	case "scroll":
		if e.DeltaY > 0 {
			run("xdotool", "click", "5") // scroll down
		} else if e.DeltaY < 0 {
			run("xdotool", "click", "4") // scroll up
		}
	case "keydown":
		k := xdoKey(e.Code, e.Mods)
		if k != "" {
			run("xdotool", "keydown", k)
		}
	case "keyup":
		k := xdoKey(e.Code, e.Mods)
		if k != "" {
			run("xdotool", "keyup", k)
		}

	case "paste_text":
		if e.Text != "" {
			run("xdotool", "type", "--clearmodifiers", "--delay", "0", e.Text)
		}
	}
}

func run(name string, args ...string) {
	if err := exec.Command(name, args...).Run(); err != nil {
		log.Printf("xdotool %v: %v", args, err)
	}
}

func itoa(f float64) string { return strconv.Itoa(int(f)) }

func xbtn(b int) string {
	switch b {
	case 1:
		return "2"
	case 2:
		return "3"
	default:
		return "1"
	}
}

func xdoKey(code string, mods []string) string {
	xdoMap := map[string]string{
		"KeyA": "a", "KeyB": "b", "KeyC": "c", "KeyD": "d", "KeyE": "e",
		"KeyF": "f", "KeyG": "g", "KeyH": "h", "KeyI": "i", "KeyJ": "j",
		"KeyK": "k", "KeyL": "l", "KeyM": "m", "KeyN": "n", "KeyO": "o",
		"KeyP": "p", "KeyQ": "q", "KeyR": "r", "KeyS": "s", "KeyT": "t",
		"KeyU": "u", "KeyV": "v", "KeyW": "w", "KeyX": "x", "KeyY": "y",
		"KeyZ": "z",
		"Digit0": "0", "Digit1": "1", "Digit2": "2", "Digit3": "3", "Digit4": "4",
		"Digit5": "5", "Digit6": "6", "Digit7": "7", "Digit8": "8", "Digit9": "9",
		"Space":        "space",
		"Enter":        "Return",
		"Backspace":    "BackSpace",
		"Tab":          "Tab",
		"Escape":       "Escape",
		"Delete":       "Delete",
		"Home":         "Home",
		"End":          "End",
		"PageUp":       "Prior",
		"PageDown":     "Next",
		"ArrowLeft":    "Left",
		"ArrowRight":   "Right",
		"ArrowUp":      "Up",
		"ArrowDown":    "Down",
		"ShiftLeft":    "shift",
		"ShiftRight":   "shift",
		"ControlLeft":  "ctrl",
		"ControlRight": "ctrl",
		"AltLeft":      "alt",
		"AltRight":     "alt",
		"MetaLeft":     "super",
		"MetaRight":    "super",
		"CapsLock":     "Caps_Lock",
		"Minus":        "minus", "Equal": "equal",
		"BracketLeft": "bracketleft", "BracketRight": "bracketright",
		"Backslash": "backslash", "Semicolon": "semicolon", "Quote": "apostrophe",
		"Comma": "comma", "Period": "period", "Slash": "slash", "Backquote": "grave",
		"F1": "F1", "F2": "F2", "F3": "F3", "F4": "F4", "F5": "F5", "F6": "F6",
		"F7": "F7", "F8": "F8", "F9": "F9", "F10": "F10", "F11": "F11", "F12": "F12",
	}
	key, ok := xdoMap[code]
	if !ok {
		return ""
	}
	// Prepend modifiers: ctrl+shift+a
	prefix := ""
	for _, m := range mods {
		switch m {
		case "ctrl":
			prefix += "ctrl+"
		case "shift":
			prefix += "shift+"
		case "alt":
			prefix += "alt+"
		case "meta":
			prefix += "super+"
		}
	}
	return prefix + key
}

func CheckAccessibility() bool         { return true }
func RequestAccessibilityPrompt() bool { return true }

func Init() {}
