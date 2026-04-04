# build-app-win.ps1 — Windows 一键打包脚本
#
# 前提：
#   1. Go 已通过官方 .msi 安装（go.dev/dl）
#   2. MSYS2 + MinGW-w64 已安装，且 C:\msys64\mingw64\bin 在 PATH
#   3. Flutter SDK 已安装并在 PATH
#
# 用法（PowerShell）：
#   powershell -ExecutionPolicy Bypass -File .\scripts\build-app-win.ps1
#
# 输出：
#   app\build\windows\x64\runner\Release\   （含 remotectl.exe + remotectl-agent.exe）

# 设置控制台输出为 UTF-8，避免中文乱码
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# 切换到仓库根目录
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

Write-Host ""
Write-Host "=== RemoteCtl Windows 一键打包 ===" -ForegroundColor Cyan
Write-Host ""

# ── 1. 创建 bin/ 目录 ─────────────────────────────────────────
New-Item -ItemType Directory -Force -Path "bin" | Out-Null

# ── 2. 构建 Windows agent ─────────────────────────────────────
Write-Host "▶ 构建 agent..." -ForegroundColor Yellow

$env:CGO_ENABLED = "1"
$env:GOOS        = "windows"
$env:GOARCH      = "amd64"
$env:CC          = "gcc"   # MSYS2 MinGW-w64 提供

Push-Location "agent"
try {
    go build -ldflags="-s -w -H windowsgui" `
             -o "..\bin\remotectl-agent-windows-amd64.exe" .
} finally {
    Pop-Location
}

Write-Host "  ✓ bin\remotectl-agent-windows-amd64.exe" -ForegroundColor Green
Write-Host ""

# ── 3. 构建 Flutter Windows app ──────────────────────────────
Write-Host "▶ flutter build windows --release ..." -ForegroundColor Yellow

Push-Location "app"
try {
    flutter build windows --release
} finally {
    Pop-Location
}

Write-Host ""

# ── 4. 将 agent 注入 Flutter 发布目录 ────────────────────────
$dest = "app\build\windows\x64\runner\Release"
if (-not (Test-Path $dest)) {
    Write-Error "Flutter 构建目录不存在：$dest"
}

Copy-Item "bin\remotectl-agent-windows-amd64.exe" "$dest\remotectl-agent.exe" -Force
Write-Host "  ✓ agent 已注入 $dest" -ForegroundColor Green
Write-Host ""

# ── 完成 ─────────────────────────────────────────────────────
Write-Host "=== 打包完成 ===" -ForegroundColor Cyan
Write-Host "  发布目录：$((Resolve-Path $dest).Path)" -ForegroundColor White
Write-Host "  直接运行：$dest\remotectl.exe" -ForegroundColor White
Write-Host ""
