//go:build cgo && darwin

package input

/*
#cgo LDFLAGS: -framework ApplicationServices
#include <ApplicationServices/ApplicationServices.h>
#include <stdbool.h>

static bool rc_accessibility_trusted(void) {
    return AXIsProcessTrustedWithOptions(NULL);
}

// Scale physical pixel coordinates to logical points for CGEventPost.
// On a Retina display CGDisplayPixelsWide > CGDisplayBounds width (e.g. 2x or 3x).
static CGPoint rc_to_logical(int x, int y) {
    CGDirectDisplayID disp = CGMainDisplayID();
    size_t physW = CGDisplayPixelsWide(disp);
    size_t physH = CGDisplayPixelsHigh(disp);
    CGRect bounds = CGDisplayBounds(disp);
    double sx = (physW > 0) ? bounds.size.width  / (double)physW : 1.0;
    double sy = (physH > 0) ? bounds.size.height / (double)physH : 1.0;
    CGPoint p = { x * sx, y * sy };
    return p;
}

// Mouse helpers
static void rc_mouse_move(int x, int y) {
    CGPoint p = rc_to_logical(x, y);
    CGEventRef e = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, p, kCGMouseButtonLeft);
    CGEventPost(kCGHIDEventTap, e);
    CFRelease(e);
}

static void rc_mouse_button(int x, int y, int btn, int down) {
    CGPoint p = rc_to_logical(x, y);
    CGEventType t;
    CGMouseButton b;
    if (btn == 2) { b = kCGMouseButtonRight;  t = down ? kCGEventRightMouseDown  : kCGEventRightMouseUp; }
    else          { b = kCGMouseButtonLeft;   t = down ? kCGEventLeftMouseDown   : kCGEventLeftMouseUp; }
    CGEventRef e = CGEventCreateMouseEvent(NULL, t, p, b);
    CGEventPost(kCGHIDEventTap, e);
    CFRelease(e);
}

static void rc_mouse_click(int x, int y, int btn, int double_click) {
    CGPoint p = rc_to_logical(x, y);
    CGMouseButton b = (btn == 2) ? kCGMouseButtonRight : kCGMouseButtonLeft;
    CGEventType td = (btn == 2) ? kCGEventRightMouseDown : kCGEventLeftMouseDown;
    CGEventType tu = (btn == 2) ? kCGEventRightMouseUp   : kCGEventLeftMouseUp;
    int clicks = double_click ? 2 : 1;
    CGEventRef ed = CGEventCreateMouseEvent(NULL, td, p, b);
    CGEventRef eu = CGEventCreateMouseEvent(NULL, tu, p, b);
    CGEventSetIntegerValueField(ed, kCGMouseEventClickState, clicks);
    CGEventSetIntegerValueField(eu, kCGMouseEventClickState, clicks);
    CGEventPost(kCGHIDEventTap, ed);
    CGEventPost(kCGHIDEventTap, eu);
    CFRelease(ed);
    CFRelease(eu);
}

static void rc_scroll(int dx, int dy) {
    // dy > 0 → scroll down (positive is "down" in browser, but kCGScrollWheelEventDeltaAxis1 positive = up)
    CGEventRef e = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, 2, -dy, dx);
    CGEventPost(kCGHIDEventTap, e);
    CFRelease(e);
}

// Type a UTF-8 string character by character using CGEventKeyboardSetUnicodeString.
// This works for any Unicode character without needing a keycode lookup.
static void rc_type_text(const char *utf8) {
    if (!utf8 || !*utf8) return;
    CFStringRef str = CFStringCreateWithCString(kCFAllocatorDefault, utf8, kCFStringEncodingUTF8);
    if (!str) return;
    CFIndex len = CFStringGetLength(str);
    for (CFIndex i = 0; i < len; i++) {
        UniChar ch = CFStringGetCharacterAtIndex(str, i);
        CGEventRef down_ev = CGEventCreateKeyboardEvent(NULL, 0, true);
        CGEventRef up_ev   = CGEventCreateKeyboardEvent(NULL, 0, false);
        CGEventKeyboardSetUnicodeString(down_ev, 1, &ch);
        CGEventKeyboardSetUnicodeString(up_ev,   1, &ch);
        CGEventPost(kCGHIDEventTap, down_ev);
        CGEventPost(kCGHIDEventTap, up_ev);
        CFRelease(down_ev);
        CFRelease(up_ev);
    }
    CFRelease(str);
}

// Keyboard helper
// flags: bitmask — bit0=shift, bit1=ctrl, bit2=alt, bit3=cmd
static void rc_key(int keycode, int down, int flags) {
    CGEventFlags f = 0;
    if (flags & 1) f |= kCGEventFlagMaskShift;
    if (flags & 2) f |= kCGEventFlagMaskControl;
    if (flags & 4) f |= kCGEventFlagMaskAlternate;
    if (flags & 8) f |= kCGEventFlagMaskCommand;
    CGEventRef e = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)keycode, down ? 1 : 0);
    CGEventSetFlags(e, f);
    CGEventPost(kCGHIDEventTap, e);
    CFRelease(e);
}
*/
import "C"

import "unsafe"

// CheckAccessibility returns true if the process has Accessibility permission.
// CGEventPost (mouse/keyboard injection) silently fails without it.
func CheckAccessibility() bool {
	return bool(C.rc_accessibility_trusted())
}

func inject(e Event) {
	x, y := C.int(e.X), C.int(e.Y)

	switch e.Event {
	case "mousemove":
		C.rc_mouse_move(x, y)

	case "mousedown":
		C.rc_mouse_button(x, y, C.int(e.Button), 1)

	case "mouseup":
		C.rc_mouse_button(x, y, C.int(e.Button), 0)

	case "click":
		C.rc_mouse_click(x, y, C.int(e.Button), 0)

	case "dblclick":
		C.rc_mouse_click(x, y, C.int(e.Button), 1)

	case "scroll":
		C.rc_scroll(C.int(e.DeltaX), C.int(e.DeltaY))

	case "keydown":
		kc := darwinKeyCode(e.Code)
		if kc < 0 {
			return
		}
		C.rc_key(C.int(kc), 1, C.int(modFlags(e.Mods)))

	case "keyup":
		kc := darwinKeyCode(e.Code)
		if kc < 0 {
			return
		}
		C.rc_key(C.int(kc), 0, C.int(modFlags(e.Mods)))

	case "paste_text":
		if e.Text != "" {
			cs := C.CString(e.Text)
			C.rc_type_text(cs)
			C.free(unsafe.Pointer(cs))
		}
	}
}

// modFlags converts ["shift","ctrl","alt","meta"] to a bitmask (bit0-3).
func modFlags(mods []string) int {
	f := 0
	for _, m := range mods {
		switch m {
		case "shift":
			f |= 1
		case "ctrl":
			f |= 2
		case "alt":
			f |= 4
		case "meta":
			f |= 8
		}
	}
	return f
}

// darwinKeyCode maps browser KeyboardEvent.code → macOS CGKeyCode.
// Returns -1 for unknown keys.
func darwinKeyCode(code string) int {
	// https://github.com/phracker/MacOSX-SDKs/blob/master/MacOSX10.13.sdk/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/Headers/Events.h
	kVK := map[string]int{
		// Alphabet
		"KeyA": 0x00, "KeyS": 0x01, "KeyD": 0x02, "KeyF": 0x03,
		"KeyH": 0x04, "KeyG": 0x05, "KeyZ": 0x06, "KeyX": 0x07,
		"KeyC": 0x08, "KeyV": 0x09, "KeyB": 0x0B, "KeyQ": 0x0C,
		"KeyW": 0x0D, "KeyE": 0x0E, "KeyR": 0x0F, "KeyY": 0x10,
		"KeyT": 0x11, "KeyO": 0x1F, "KeyU": 0x20, "KeyI": 0x22,
		"KeyP": 0x23, "KeyL": 0x25, "KeyJ": 0x26, "KeyK": 0x28,
		"KeyN": 0x2D, "KeyM": 0x2E,
		// Numbers
		"Digit1": 0x12, "Digit2": 0x13, "Digit3": 0x14, "Digit4": 0x15,
		"Digit6": 0x16, "Digit5": 0x17, "Digit9": 0x19, "Digit7": 0x1A,
		"Digit8": 0x1C, "Digit0": 0x1D,
		// Symbols
		"Equal":        0x18,
		"Minus":        0x1B,
		"BracketRight": 0x1E,
		"BracketLeft":  0x21,
		"Quote":        0x27,
		"Semicolon":    0x29,
		"Backslash":    0x2A,
		"Comma":        0x2B,
		"Slash":        0x2C,
		"Period":       0x2F,
		"Backquote":    0x32,
		// Control
		"Return":    0x24,
		"Enter":     0x24,
		"Tab":       0x30,
		"Space":     0x31,
		"Backspace": 0x33,
		"Escape":    0x35,
		"Delete":    0x75, // Forward delete
		"Home":      0x73,
		"End":       0x77,
		"PageUp":    0x74,
		"PageDown":  0x79,
		// Arrows
		"ArrowLeft":  0x7B,
		"ArrowRight": 0x7C,
		"ArrowDown":  0x7D,
		"ArrowUp":    0x7E,
		// Modifiers
		"ShiftLeft":    0x38,
		"ShiftRight":   0x3C,
		"ControlLeft":  0x3B,
		"ControlRight": 0x3E,
		"AltLeft":      0x3A,
		"AltRight":     0x3D,
		"MetaLeft":     0x37,
		"MetaRight":    0x36,
		"CapsLock":     0x39,
		// Function keys
		"F1":  0x7A, "F2": 0x78, "F3": 0x63, "F4": 0x76,
		"F5":  0x60, "F6": 0x61, "F7": 0x62, "F8": 0x64,
		"F9":  0x65, "F10": 0x6D, "F11": 0x67, "F12": 0x6F,
		// Numpad
		"Numpad0": 0x52, "Numpad1": 0x53, "Numpad2": 0x54, "Numpad3": 0x55,
		"Numpad4": 0x56, "Numpad5": 0x57, "Numpad6": 0x58, "Numpad7": 0x59,
		"Numpad8": 0x5B, "Numpad9": 0x5C,
		"NumpadDecimal":  0x41,
		"NumpadAdd":      0x45,
		"NumpadSubtract": 0x4E,
		"NumpadMultiply": 0x43,
		"NumpadDivide":   0x4B,
		"NumpadEnter":    0x4C,
	}
	if kc, ok := kVK[code]; ok {
		return kc
	}
	return -1
}
