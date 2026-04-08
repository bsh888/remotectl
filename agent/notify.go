package main

import (
	"os/exec"
	"runtime"
	"strings"
)

// showNotification sends an OS desktop notification on a best-effort basis.
// Errors are silently ignored — notifications are informational only and the
// session must continue regardless.
func showNotification(title, body string) {
	switch runtime.GOOS {
	case "darwin":
		// osascript is available on all modern macOS versions.
		script := `display notification ` + asStr(body) + ` with title ` + asStr(title)
		exec.Command("osascript", "-e", script).Start() //nolint:errcheck
	case "windows":
		// PowerShell balloon-tip via Windows Forms — no third-party dependency.
		ps := `Add-Type -AssemblyName System.Windows.Forms;` +
			`$n=[System.Windows.Forms.NotifyIcon]::new();` +
			`$n.Icon=[System.Drawing.SystemIcons]::Information;` +
			`$n.Visible=$true;` +
			`$n.ShowBalloonTip(4000,'` + psStr(title) + `','` + psStr(body) + `',[System.Windows.Forms.ToolTipIcon]::Info);` +
			`Start-Sleep -Milliseconds 4500;$n.Visible=$false;$n.Dispose()`
		exec.Command("powershell", "-WindowStyle", "Hidden", "-NonInteractive", "-Command", ps).Start() //nolint:errcheck
	case "linux":
		exec.Command("notify-send", "--app-name=RemoteCtl", "--expire-time=5000", title, body).Start() //nolint:errcheck
	}
}

// asStr wraps s in AppleScript double-quote literals, escaping as needed.
func asStr(s string) string {
	s = strings.ReplaceAll(s, "\\", "\\\\")
	s = strings.ReplaceAll(s, `"`, `\"`)
	return `"` + s + `"`
}

// psStr escapes a string for embedding in a single-quoted PowerShell string.
func psStr(s string) string {
	return strings.ReplaceAll(s, "'", "''")
}
