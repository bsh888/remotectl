//go:build linux

package main

import (
	"bufio"
	"os"
	"strings"
)

func detectPlatform() string {
	return "linux"
}

// osVersion parses /etc/os-release and returns e.g. "Ubuntu 22.04.3 LTS"
func osVersion() string {
	f, err := os.Open("/etc/os-release")
	if err != nil {
		return "Linux"
	}
	defer f.Close()
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "PRETTY_NAME=") {
			v := strings.TrimPrefix(line, "PRETTY_NAME=")
			v = strings.Trim(v, `"`)
			return v
		}
	}
	return "Linux"
}
