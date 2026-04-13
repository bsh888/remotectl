//go:build darwin

package main

import (
	"os/exec"
	"strings"
)

func detectPlatform() string {
	return "darwin"
}

// osVersion returns e.g. "macOS 15.3"
func osVersion() string {
	name, _ := exec.Command("sw_vers", "-productName").Output()
	ver, _ := exec.Command("sw_vers", "-productVersion").Output()
	n := strings.TrimSpace(string(name))
	v := strings.TrimSpace(string(ver))
	if n == "" {
		n = "macOS"
	}
	if v != "" {
		return n + " " + v
	}
	return n
}
