//go:build windows

package main

import (
	"strconv"
	"strings"

	"golang.org/x/sys/windows/registry"
)

func detectPlatform() string {
	return "windows"
}

// osVersion returns e.g. "Windows 11 专业版" by reading the registry,
// which returns UTF-16LE strings and avoids the GBK encoding issue with wmic.
func osVersion() string {
	k, err := registry.OpenKey(registry.LOCAL_MACHINE,
		`SOFTWARE\Microsoft\Windows NT\CurrentVersion`,
		registry.QUERY_VALUE)
	if err != nil {
		return "Windows"
	}
	defer k.Close()

	productName, _, err := k.GetStringValue("ProductName")
	if err != nil || productName == "" {
		return "Windows"
	}
	name := strings.TrimPrefix(productName, "Microsoft ")

	// Windows 11 keeps ProductName as "Windows 10 ..." for compatibility.
	// Check CurrentBuildNumber: builds ≥ 22000 are Windows 11.
	if buildStr, _, err2 := k.GetStringValue("CurrentBuildNumber"); err2 == nil {
		if build, err3 := strconv.Atoi(buildStr); err3 == nil && build >= 22000 {
			name = strings.Replace(name, "Windows 10", "Windows 11", 1)
		}
	}
	return name
}
