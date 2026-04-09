//go:build !windows

package main

import "os/exec"

// hiddenCmd creates an exec.Cmd that runs without any visible window.
// On non-Windows platforms this is the same as exec.Command.
func hiddenCmd(name string, args ...string) *exec.Cmd {
	return exec.Command(name, args...)
}
