//go:build windows

package main

import (
	"os/exec"
	"strings"
)

func detectPlatform() string {
	return "windows"
}

// osVersion returns e.g. "Windows 11 Pro"
func osVersion() string {
	out, err := exec.Command("wmic", "os", "get", "Caption", "/value").Output()
	if err != nil {
		return "Windows"
	}
	for _, line := range strings.Split(string(out), "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "Caption=") {
			v := strings.TrimPrefix(line, "Caption=")
			v = strings.TrimPrefix(v, "Microsoft ")
			return strings.TrimSpace(v)
		}
	}
	return "Windows"
}
