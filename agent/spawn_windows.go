//go:build windows

package main

import (
	"os/exec"
	"syscall"
)

// hiddenCmd creates an exec.Cmd with CREATE_NO_WINDOW set so that no console
// or PowerShell window flashes on screen when the process starts.
// Without this flag, even `powershell -WindowStyle Hidden` briefly shows a
// window because Go's exec.Command on Windows does not set CREATE_NO_WINDOW
// by default.
func hiddenCmd(name string, args ...string) *exec.Cmd {
	cmd := exec.Command(name, args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	return cmd
}
