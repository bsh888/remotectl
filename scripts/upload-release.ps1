# upload-release.ps1 — Upload Windows Flutter App to an existing GitHub Release.
#
# Run on Windows after build-app-win.ps1 completes.
# The GitHub Release must already exist (created by release.sh on macOS).
#
# Requirements:
#   gh CLI installed: https://cli.github.com  (winget install GitHub.cli)
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\scripts\upload-release.ps1 v1.2.3

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

# ── Args ──────────────────────────────────────────────────────────────────────

$VERSION = $args[0]
if (-not $VERSION) {
    Write-Error "Usage: upload-release.ps1 <version>  e.g. upload-release.ps1 v1.0.0"
    exit 1
}
if ($VERSION -notmatch '^v\d+\.\d+\.\d+$') {
    Write-Error "Version must be vX.Y.Z (got: $VERSION)"
    exit 1
}

# ── Check gh ──────────────────────────────────────────────────────────────────

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "gh not found. Install: winget install GitHub.cli  then  gh auth login"
    exit 1
}

# ── Check artifact ────────────────────────────────────────────────────────────

$artifact = "deploy\bin\remotectl-windows-amd64.zip"
if (-not (Test-Path $artifact)) {
    Write-Error "Artifact not found: $artifact`nBuild it first: powershell -ExecutionPolicy Bypass -File .\scripts\build-app-win.ps1"
    exit 1
}

$uploadAs = "remotectl-app-windows-amd64-${VERSION}.zip"

# ── Upload ────────────────────────────────────────────────────────────────────

Write-Host "Uploading $uploadAs to release $VERSION..." -ForegroundColor Cyan
gh release upload $VERSION "${artifact}#${uploadAs}" --repo bsh888/remotectl --clobber

$url = gh release view $VERSION --repo bsh888/remotectl --json url -q .url
Write-Host "Done: $url" -ForegroundColor Green
