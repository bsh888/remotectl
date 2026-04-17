//go:build windows

package input

import (
	"unsafe"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/registry"
)

var (
	user32            = windows.NewLazySystemDLL("user32.dll")
	pSendInput        = user32.NewProc("SendInput")
	pSetCursorPos     = user32.NewProc("SetCursorPos")
	pGetSystemMetrics = user32.NewProc("GetSystemMetrics")

	// sas.dll — SendSAS() is the only way to trigger Ctrl+Alt+Delete
	// programmatically. Works when SoftwareSASGeneration policy ≥ 1 (service)
	// or ≥ 3 (application). The agent sets this registry value on first run.
	sasDLL   = windows.NewLazySystemDLL("sas.dll")
	pSendSAS = sasDLL.NewProc("SendSAS")
)

const (
	inputMouse    = 0
	inputKeyboard = 1

	mouseeventfMove       = 0x0001
	mouseeventfLeftDown   = 0x0002
	mouseeventfLeftUp     = 0x0004
	mouseeventfRightDown  = 0x0008
	mouseeventfRightUp    = 0x0010
	mouseeventfMiddleDown = 0x0020
	mouseeventfMiddleUp   = 0x0040
	mouseeventfWheel      = 0x0800
	mouseeventfHWheel     = 0x1000
	mouseeventfAbsolute   = 0x8000

	keyeventfKeyup    = 0x0002
	keyeventfScancode = 0x0008
	keyeventfExtended = 0x0001

	smCxScreen = 0
	smCyScreen = 1
)

// INPUT structure for SendInput
// https://docs.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-input
//
// 64-bit Windows memory layout of INPUT:
//   offset 0:  type    (DWORD, 4 bytes)
//   offset 4:  <4-byte alignment padding — the anonymous union is 8-byte aligned>
//   offset 8:  union   (32 bytes, size of the largest member MOUSEINPUT)
//   total: 40 bytes
//
// Both structs below must be exactly 40 bytes with fields at the correct offsets.
// unsafe.Sizeof is passed as cbSize to SendInput; if it ≠ 40 the call fails silently.

type mouseInput struct {
	inputType uint32   // offset  0
	_         uint32   // offset  4 — alignment gap before union
	dx        int32    // offset  8
	dy        int32    // offset 12
	mouseData int32    // offset 16
	flags     uint32   // offset 20
	time      uint32   // offset 24
	_         uint32   // offset 28 — alignment gap before ULONG_PTR
	extraInfo uintptr  // offset 32
	// total: 40 bytes ✓
}

type keyboardInput struct {
	inputType uint32   // offset  0
	_         uint32   // offset  4 — alignment gap before union
	vk        uint16   // offset  8
	scan      uint16   // offset 10
	flags     uint32   // offset 12
	time      uint32   // offset 16
	_         uint32   // offset 20 — alignment gap before ULONG_PTR
	extraInfo uintptr  // offset 24
	_         [8]byte  // offset 32 — pad union to 32 bytes (same as MOUSEINPUT)
	// total: 40 bytes ✓
}

// modVKTable maps modifier names to Windows virtual key codes.
var modVKTable = map[string]uint16{
	"ctrl":  0x11, // VK_CONTROL
	"shift": 0x10, // VK_SHIFT
	"alt":   0x12, // VK_MENU
	"meta":  0x5B, // VK_LWIN
}

func sendModKey(vk uint16, up bool) {
	flags := uint32(0)
	if up {
		flags = keyeventfKeyup
	}
	ki := keyboardInput{inputType: inputKeyboard, vk: vk, flags: flags}
	pSendInput.Call(1, uintptr(unsafe.Pointer(&ki)), unsafe.Sizeof(ki))
}

// sendSAS triggers Ctrl+Alt+Delete via sas.dll.
// Requires SoftwareSASGeneration registry value ≥ 1 (set by enableSAS below).
// Init performs one-time Windows setup (write SoftwareSASGeneration registry key).
func Init() { enableSAS() }

func sendSAS() {
	if err := sasDLL.Load(); err != nil {
		return
	}
	if err := pSendSAS.Find(); err != nil {
		return
	}
	pSendSAS.Call(0) // SendSAS(FALSE) — sent as service/system
}

// enableSAS writes the SoftwareSASGeneration=1 registry value so that
// services/agents can call SendSAS(). Safe to call repeatedly.
func enableSAS() {
	key, _, err := registry.CreateKey(
		registry.LOCAL_MACHINE,
		`SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System`,
		registry.SET_VALUE,
	)
	if err != nil {
		return
	}
	defer key.Close()
	_ = key.SetDWordValue("SoftwareSASGeneration", 1)
}

func hasMod(mods []string, m string) bool {
	for _, v := range mods {
		if v == m {
			return true
		}
	}
	return false
}

func pressModsDown(mods []string) {
	for _, m := range mods {
		if vk, ok := modVKTable[m]; ok {
			sendModKey(vk, false)
		}
	}
}

func releaseModsUp(mods []string) {
	for _, m := range mods {
		if vk, ok := modVKTable[m]; ok {
			sendModKey(vk, true)
		}
	}
}

func inject(e Event) {
	switch e.Event {
	case "mousemove":
		// Use SetCursorPos for absolute positioning (simpler than SendInput ABSOLUTE)
		pSetCursorPos.Call(uintptr(e.X), uintptr(e.Y))

	case "mousedown":
		sendMouseButton(e.Button, true)

	case "mouseup":
		sendMouseButton(e.Button, false)

	case "click":
		sendMouseButton(e.Button, true)
		sendMouseButton(e.Button, false)

	case "dblclick":
		sendMouseButton(e.Button, true)
		sendMouseButton(e.Button, false)
		sendMouseButton(e.Button, true)
		sendMouseButton(e.Button, false)

	case "scroll":
		if e.DeltaY != 0 {
			mi := mouseInput{
				inputType: inputMouse,
				mouseData: int32(-e.DeltaY), // Windows: positive = forward (up)
				flags:     mouseeventfWheel,
			}
			pSendInput.Call(1, uintptr(unsafe.Pointer(&mi)), unsafe.Sizeof(mi))
		}
		if e.DeltaX != 0 {
			mi := mouseInput{
				inputType: inputMouse,
				mouseData: int32(e.DeltaX),
				flags:     mouseeventfHWheel,
			}
			pSendInput.Call(1, uintptr(unsafe.Pointer(&mi)), unsafe.Sizeof(mi))
		}

	case "keydown":
		// Ctrl+Alt+Delete must be sent via SendSAS — SendInput cannot generate SAS.
		if e.Code == "Delete" && hasMod(e.Mods, "ctrl") && hasMod(e.Mods, "alt") {
			sendSAS()
			return
		}
		pressModsDown(e.Mods)
		vk, ext := windowsVK(e.Code)
		if vk == 0 {
			return
		}
		flags := uint32(0)
		if ext {
			flags |= keyeventfExtended
		}
		ki := keyboardInput{
			inputType: inputKeyboard,
			vk:        uint16(vk),
			flags:     flags,
		}
		pSendInput.Call(1, uintptr(unsafe.Pointer(&ki)), unsafe.Sizeof(ki))

	case "keyup":
		if e.Code == "Delete" && hasMod(e.Mods, "ctrl") && hasMod(e.Mods, "alt") {
			return // handled by SendSAS on keydown
		}
		vk, ext := windowsVK(e.Code)
		if vk == 0 {
			releaseModsUp(e.Mods)
			return
		}
		flags := uint32(keyeventfKeyup)
		if ext {
			flags |= keyeventfExtended
		}
		ki := keyboardInput{
			inputType: inputKeyboard,
			vk:        uint16(vk),
			flags:     flags,
		}
		pSendInput.Call(1, uintptr(unsafe.Pointer(&ki)), unsafe.Sizeof(ki))
		releaseModsUp(e.Mods)

	case "paste_text":
		typeUnicodeText(e.Text)
	}
}

const keyeventfUnicode = 0x0004

// typeUnicodeText injects each UTF-16 code unit as a Unicode key event.
func typeUnicodeText(text string) {
	for _, r := range text {
		// Encode rune as UTF-16
		var units [2]uint16
		n := encodeUTF16(r, units[:])
		for i := 0; i < n; i++ {
			down := keyboardInput{
				inputType: inputKeyboard,
				scan:      units[i],
				flags:     keyeventfUnicode,
			}
			up := keyboardInput{
				inputType: inputKeyboard,
				scan:      units[i],
				flags:     keyeventfUnicode | keyeventfKeyup,
			}
			pSendInput.Call(1, uintptr(unsafe.Pointer(&down)), unsafe.Sizeof(down))
			pSendInput.Call(1, uintptr(unsafe.Pointer(&up)), unsafe.Sizeof(up))
		}
	}
}

func encodeUTF16(r rune, buf []uint16) int {
	if r < 0x10000 {
		buf[0] = uint16(r)
		return 1
	}
	r -= 0x10000
	buf[0] = uint16(0xD800 + (r>>10)&0x3FF)
	buf[1] = uint16(0xDC00 + r&0x3FF)
	return 2
}

func sendMouseButton(btn int, down bool) {
	var flags uint32
	switch btn {
	case 2: // right
		if down {
			flags = mouseeventfRightDown
		} else {
			flags = mouseeventfRightUp
		}
	case 1: // middle
		if down {
			flags = mouseeventfMiddleDown
		} else {
			flags = mouseeventfMiddleUp
		}
	default: // left
		if down {
			flags = mouseeventfLeftDown
		} else {
			flags = mouseeventfLeftUp
		}
	}
	mi := mouseInput{inputType: inputMouse, flags: flags}
	pSendInput.Call(1, uintptr(unsafe.Pointer(&mi)), unsafe.Sizeof(mi))
}

// windowsVK maps browser KeyboardEvent.code → (Windows VK code, extended key flag).
func windowsVK(code string) (int, bool) {
	type vkEntry struct {
		vk  int
		ext bool
	}
	vkMap := map[string]vkEntry{
		// Letters (VK is uppercase ASCII)
		"KeyA": {0x41, false}, "KeyB": {0x42, false}, "KeyC": {0x43, false}, "KeyD": {0x44, false},
		"KeyE": {0x45, false}, "KeyF": {0x46, false}, "KeyG": {0x47, false}, "KeyH": {0x48, false},
		"KeyI": {0x49, false}, "KeyJ": {0x4A, false}, "KeyK": {0x4B, false}, "KeyL": {0x4C, false},
		"KeyM": {0x4D, false}, "KeyN": {0x4E, false}, "KeyO": {0x4F, false}, "KeyP": {0x50, false},
		"KeyQ": {0x51, false}, "KeyR": {0x52, false}, "KeyS": {0x53, false}, "KeyT": {0x54, false},
		"KeyU": {0x55, false}, "KeyV": {0x56, false}, "KeyW": {0x57, false}, "KeyX": {0x58, false},
		"KeyY": {0x59, false}, "KeyZ": {0x5A, false},
		// Digits
		"Digit0": {0x30, false}, "Digit1": {0x31, false}, "Digit2": {0x32, false},
		"Digit3": {0x33, false}, "Digit4": {0x34, false}, "Digit5": {0x35, false},
		"Digit6": {0x36, false}, "Digit7": {0x37, false}, "Digit8": {0x38, false},
		"Digit9": {0x39, false},
		// Symbols
		"Minus":        {0xBD, false},
		"Equal":        {0xBB, false},
		"BracketLeft":  {0xDB, false},
		"BracketRight": {0xDD, false},
		"Backslash":    {0xDC, false},
		"Semicolon":    {0xBA, false},
		"Quote":        {0xDE, false},
		"Comma":        {0xBC, false},
		"Period":       {0xBE, false},
		"Slash":        {0xBF, false},
		"Backquote":    {0xC0, false},
		// Control
		"Space":     {0x20, false},
		"Enter":     {0x0D, false},
		"Return":    {0x0D, false},
		"Backspace": {0x08, false},
		"Tab":       {0x09, false},
		"Escape":    {0x1B, false},
		"CapsLock":  {0x14, false},
		// Navigation (extended)
		"Delete":   {0x2E, true},
		"Insert":   {0x2D, true},
		"Home":     {0x24, true},
		"End":      {0x23, true},
		"PageUp":   {0x21, true},
		"PageDown": {0x22, true},
		// Arrows (extended)
		"ArrowLeft":  {0x25, true},
		"ArrowUp":    {0x26, true},
		"ArrowRight": {0x27, true},
		"ArrowDown":  {0x28, true},
		// Modifiers
		"ShiftLeft":    {0x10, false},
		"ShiftRight":   {0x10, false},
		"ControlLeft":  {0x11, false},
		"ControlRight": {0x11, true},
		"AltLeft":      {0x12, false},
		"AltRight":     {0x12, true},
		"MetaLeft":     {0x5B, true},
		"MetaRight":    {0x5C, true},
		// Function keys
		"F1":  {0x70, false}, "F2": {0x71, false}, "F3": {0x72, false}, "F4": {0x73, false},
		"F5":  {0x74, false}, "F6": {0x75, false}, "F7": {0x76, false}, "F8": {0x77, false},
		"F9":  {0x78, false}, "F10": {0x79, false}, "F11": {0x7A, false}, "F12": {0x7B, false},
		// Numpad
		"Numpad0": {0x60, false}, "Numpad1": {0x61, false}, "Numpad2": {0x62, false},
		"Numpad3": {0x63, false}, "Numpad4": {0x64, false}, "Numpad5": {0x65, false},
		"Numpad6": {0x66, false}, "Numpad7": {0x67, false}, "Numpad8": {0x68, false},
		"Numpad9": {0x69, false},
		"NumpadDecimal":  {0x6E, false},
		"NumpadAdd":      {0x6B, false},
		"NumpadSubtract": {0x6D, false},
		"NumpadMultiply": {0x6A, false},
		"NumpadDivide":   {0x6F, true},
		"NumpadEnter":    {0x0D, true},
	}
	if e, ok := vkMap[code]; ok {
		return e.vk, e.ext
	}
	return 0, false
}

func CheckAccessibility() bool         { return true }
func RequestAccessibilityPrompt() bool { return true }
