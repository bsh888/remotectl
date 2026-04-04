#!/bin/bash
# build-app-linux.sh -- RemoteCtl Linux one-click build script
#
# Requirements:
#   1. GCC, libx264-dev, libX11-dev, libXext-dev
#      Ubuntu/Debian: sudo apt install gcc libx264-dev libx11-dev libxext-dev
#      Fedora/RHEL:   sudo dnf install gcc x264-devel libX11-devel libXext-devel
#      Arch:          sudo pacman -S gcc x264 libx11 libxext
#   2. Flutter SDK in PATH (flutter.dev)
#
# Usage:
#   ./scripts/build-app-linux.sh
#
# Output:
#   bin/remotectl-linux-amd64.tar.gz  (extract and run bundle/remotectl)

set -euo pipefail

cd "$(dirname "$0")/.."

echo ""
echo "=== RemoteCtl Linux Build ==="
echo ""

mkdir -p bin

# -- 1. Build agent -----------------------------------------------------------
echo "[1/4] Building agent..."
cd agent && CGO_ENABLED=1 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-s -w" \
    -o ../bin/remotectl-agent-linux-amd64 .
cd ..
echo "      OK: bin/remotectl-agent-linux-amd64"
echo ""

# -- 2. Build Flutter Linux app -----------------------------------------------
echo "[2/4] Building Flutter Linux app..."
cd app && flutter build linux --release
cd ..
echo ""

# -- 3. Inject agent into bundle ----------------------------------------------
echo "[3/4] Injecting agent into bundle..."
BUNDLE="app/build/linux/x64/release/bundle"
cp bin/remotectl-agent-linux-amd64 "$BUNDLE/remotectl-agent"
chmod +x "$BUNDLE/remotectl-agent"
echo "      OK: $BUNDLE/remotectl-agent"
echo ""

# -- 4. Package into tar.gz ---------------------------------------------------
echo "[4/4] Packaging into tar.gz..."
ARCHIVE="bin/remotectl-linux-amd64.tar.gz"
rm -f "$ARCHIVE"
cd "app/build/linux/x64/release"
tar -czf "../../../../../$ARCHIVE" bundle/
cd - > /dev/null
echo "      OK: $ARCHIVE"
echo ""

# -- Done ---------------------------------------------------------------------
echo "=== Build complete ==="
echo "  Run in place : $(pwd)/$BUNDLE/remotectl"
echo "  Distribute   : $(pwd)/$ARCHIVE"
echo ""
echo "  Extract on the target machine and run: bundle/remotectl"
echo ""
