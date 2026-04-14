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
#   app\build\windows\x64\runner\Release\   (run in place)
#   deploy\bin\remotectl-windows-amd64.zip  (distribute this)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Switch to repo root
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

Write-Host ""
Write-Host "=== RemoteCtl Windows Build ===" -ForegroundColor Cyan
Write-Host ""

# -- 1. Create deploy/bin/ directory ------------------------------------------
New-Item -ItemType Directory -Force -Path "deploy\bin" | Out-Null

# -- 2. Build agent -----------------------------------------------------------
Write-Host "[1/4] Building agent..." -ForegroundColor Yellow

$env:CGO_ENABLED = "1"
$env:GOOS        = "windows"
$env:GOARCH      = "amd64"
$env:CC          = "gcc"   # provided by MSYS2 MinGW-w64

Push-Location "agent"
try {
    go build -ldflags="-s -w -H windowsgui" `
             -o "..\deploy\bin\remotectl-agent-windows-amd64.exe" .
} finally {
    Pop-Location
}

Write-Host "      OK: deploy\bin\remotectl-agent-windows-amd64.exe" -ForegroundColor Green
Write-Host ""

# -- 3. Build Flutter Windows app ---------------------------------------------
Write-Host "[2/4] Building Flutter Windows app..." -ForegroundColor Yellow

Push-Location "app"
try {
    # flutter clean resets CMake cache and internal build state.
    # Without it, stale cmake_install.cmake or native-assets state can cause
    # MSB3073 / cmake_install.cmake exit-1 errors on incremental builds.
    flutter clean
    if ($LASTEXITCODE -ne 0) { throw "flutter clean failed (exit $LASTEXITCODE)" }
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed (exit $LASTEXITCODE)" }
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build failed (exit $LASTEXITCODE)" }
} finally {
    Pop-Location
}

Write-Host ""

# -- 4. Inject agent into Flutter release bundle ------------------------------
Write-Host "[3/4] Injecting agent into release bundle..." -ForegroundColor Yellow

$dest = "app\build\windows\x64\runner\Release"
if (-not (Test-Path $dest)) {
    Write-Error "Flutter build output not found: $dest"
}

Copy-Item "deploy\bin\remotectl-agent-windows-amd64.exe" "$dest\remotectl-agent.exe" -Force
Write-Host "      OK: $dest\remotectl-agent.exe" -ForegroundColor Green
Write-Host ""

# -- 5. Package into zip ------------------------------------------------------
Write-Host "[4/4] Packaging into zip..." -ForegroundColor Yellow

$zip = "deploy\bin\remotectl-windows-amd64.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path "$dest\*" -DestinationPath $zip
Write-Host "      OK: $zip" -ForegroundColor Green
Write-Host ""

# -- Done ---------------------------------------------------------------------
Write-Host "=== Build complete ===" -ForegroundColor Cyan
Write-Host "  Run in place : $((Resolve-Path $dest).Path)\remotectl.exe" -ForegroundColor White
Write-Host "  Distribute   : $((Resolve-Path $zip).Path)" -ForegroundColor White
Write-Host ""
Write-Host "  Unzip on the target machine and run remotectl.exe directly." -ForegroundColor Gray
Write-Host ""
