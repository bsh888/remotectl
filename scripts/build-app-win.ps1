# build-app-win.ps1 -- RemoteCtl Windows one-click build script
#
# Requirements:
#   1. Go installed via official .msi (go.dev/dl)
#   2. MSYS2 + MinGW-w64 installed, C:\msys64\mingw64\bin in PATH
#   3. Flutter SDK installed and in PATH
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\scripts\build-app-win.ps1
#
# Output:
#   app\build\windows\x64\runner\Release\  (remotectl.exe + remotectl-agent.exe)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Switch to repo root
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

Write-Host ""
Write-Host "=== RemoteCtl Windows Build ===" -ForegroundColor Cyan
Write-Host ""

# -- 1. Create bin/ directory -------------------------------------------------
New-Item -ItemType Directory -Force -Path "bin" | Out-Null

# -- 2. Build agent -----------------------------------------------------------
Write-Host "[1/3] Building agent..." -ForegroundColor Yellow

$env:CGO_ENABLED = "1"
$env:GOOS        = "windows"
$env:GOARCH      = "amd64"
$env:CC          = "gcc"   # provided by MSYS2 MinGW-w64

Push-Location "agent"
try {
    go build -ldflags="-s -w -H windowsgui" `
             -o "..\bin\remotectl-agent-windows-amd64.exe" .
} finally {
    Pop-Location
}

Write-Host "      OK: bin\remotectl-agent-windows-amd64.exe" -ForegroundColor Green
Write-Host ""

# -- 3. Build Flutter Windows app ---------------------------------------------
Write-Host "[2/3] Building Flutter Windows app..." -ForegroundColor Yellow

Push-Location "app"
try {
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build failed (exit $LASTEXITCODE)" }
} finally {
    Pop-Location
}

Write-Host ""

# -- 4. Inject agent into Flutter release bundle ------------------------------
Write-Host "[3/3] Injecting agent into release bundle..." -ForegroundColor Yellow

$dest = "app\build\windows\x64\runner\Release"
if (-not (Test-Path $dest)) {
    Write-Error "Flutter build output not found: $dest"
}

Copy-Item "bin\remotectl-agent-windows-amd64.exe" "$dest\remotectl-agent.exe" -Force
Write-Host "      OK: $dest\remotectl-agent.exe" -ForegroundColor Green
Write-Host ""

# -- Done ---------------------------------------------------------------------
Write-Host "=== Build complete ===" -ForegroundColor Cyan
Write-Host "  Output : $((Resolve-Path $dest).Path)" -ForegroundColor White
Write-Host "  Run    : $dest\remotectl.exe" -ForegroundColor White
Write-Host ""
