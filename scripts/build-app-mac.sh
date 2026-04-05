#!/bin/bash
# build-app-mac.sh -- RemoteCtl macOS one-click build script
#
# Requirements:
#   1. Xcode Command Line Tools  (xcode-select --install)
#   2. Flutter SDK in PATH       (flutter.dev)
#
# Usage:
#   ./scripts/build-app-mac.sh
#
# Output:
#   bin/remotectl-macos.zip   (unzip and run remotectl.app on any Mac)

set -euo pipefail

cd "$(dirname "$0")/.."

echo ""
echo "=== RemoteCtl macOS Build ==="
echo ""

mkdir -p bin

# -- 1. Build universal agent (arm64 + amd64) ---------------------------------
echo "[1/4] Building agent (arm64)..."
cd agent && CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 \
    go build -ldflags="-s -w" -o ../bin/remotectl-agent-mac-arm64 .
cd ..

echo "[1/4] Building agent (amd64)..."
cd agent && CGO_ENABLED=1 GOOS=darwin GOARCH=amd64 \
    go build -ldflags="-s -w" -o ../bin/remotectl-agent-mac-amd64 .
cd ..

lipo -create \
    bin/remotectl-agent-mac-arm64 \
    bin/remotectl-agent-mac-amd64 \
    -output bin/remotectl-agent-mac
echo "      OK: bin/remotectl-agent-mac (universal)"
echo ""

# -- 2. Build Flutter macOS app -----------------------------------------------
echo "[2/4] Building Flutter macOS app..."
APP="app/build/macos/Build/Products/Release/remotectl.app"
# Remove previously injected agent so Xcode code-signing doesn't choke on an
# unsigned binary left over from a prior build run.
rm -f "$APP/Contents/MacOS/remotectl-agent"
cd app && flutter build macos --release
cd ..
echo ""

# -- 3. Inject agent into .app bundle + re-sign --------------------------------
echo "[3/4] Injecting agent into .app bundle..."
cp bin/remotectl-agent-mac "$APP/Contents/MacOS/remotectl-agent"
chmod +x "$APP/Contents/MacOS/remotectl-agent"
# Ad-hoc sign the agent binary, then re-sign the whole bundle so macOS
# accepts the modified app without Gatekeeper errors.
codesign --force --sign - "$APP/Contents/MacOS/remotectl-agent"
codesign --force --deep --sign - "$APP"
echo "      OK: $APP/Contents/MacOS/remotectl-agent (ad-hoc signed)"
echo ""

# -- 4. Package into zip -------------------------------------------------------
echo "[4/4] Packaging into zip..."
ZIP="$(pwd)/bin/remotectl-macos.zip"
rm -f "$ZIP"
cd "app/build/macos/Build/Products/Release"
zip -r --symlinks "$ZIP" remotectl.app
cd - > /dev/null
echo "      OK: $ZIP"
echo ""

# -- Done ----------------------------------------------------------------------
echo "=== Build complete ==="
echo "  Run in place : $APP"
echo "  Distribute   : $(pwd)/$ZIP"
echo ""
echo "  Unzip on the target Mac and double-click remotectl.app to launch."
echo ""
