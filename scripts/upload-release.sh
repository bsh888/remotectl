#!/usr/bin/env bash
# upload-release.sh — Upload platform-specific Flutter app to an existing release.
#
# Run on Windows (via Git Bash / WSL) or Linux after building the Flutter app.
# The GitHub Release must already exist (created by release.sh on macOS).
#
# Usage:
#   ./scripts/upload-release.sh v1.2.3

set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-}"
[[ -n "$VERSION" ]] || { echo "Usage: $0 <version>  e.g. $0 v1.0.0" >&2; exit 1; }

command -v gh &>/dev/null || { echo "gh not found. Install: https://cli.github.com" >&2; exit 1; }

# Detect platform and expected artifact
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$OS" in
  linux*)
    ARTIFACT="deploy/bin/remotectl-linux-amd64.tar.gz"
    UPLOAD_AS="remotectl-app-linux-amd64-${VERSION}.tar.gz"
    BUILD_CMD="scripts/build-app-linux.sh"
    ;;
  msys*|mingw*|cygwin*)
    ARTIFACT="deploy/bin/remotectl-windows-amd64.zip"
    UPLOAD_AS="remotectl-app-windows-amd64-${VERSION}.zip"
    BUILD_CMD="scripts/build-app-win.ps1"
    ;;
  *)
    echo "Unsupported platform: $OS" >&2
    exit 1
    ;;
esac

if [[ ! -f "$ARTIFACT" ]]; then
  echo "Artifact not found: $ARTIFACT"
  echo "Build it first:  $BUILD_CMD"
  exit 1
fi

echo "Uploading $UPLOAD_AS to release $VERSION..."
gh release upload "$VERSION" "$ARTIFACT#$UPLOAD_AS" --clobber
echo "Done: $(gh release view "$VERSION" --json url -q .url)"
