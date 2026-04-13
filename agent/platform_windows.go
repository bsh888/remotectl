//go:build windows

package main

import (
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
	return strings.TrimPrefix(productName, "Microsoft ")
}
