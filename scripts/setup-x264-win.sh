#!/usr/bin/env bash
# setup-x264-win.sh — Cross-compile x264 for Windows (macOS host).
#
# Uses the mingw-w64 cross-compiler to build a Windows static library and
# places x264.h + libx264.a into agent/pipeline/x264/.
#
# Called automatically by release.sh when the files are missing.
# Can also be run manually: ./scripts/setup-x264-win.sh
#
# Requirements (installed automatically if missing):
#   brew install nasm mingw-w64

set -euo pipefail

DEST="$(cd "$(dirname "$0")/.." && pwd)/agent/pipeline/x264"
mkdir -p "$DEST"

if [[ -f "$DEST/x264.h" && -f "$DEST/libx264.a" ]]; then
  echo "x264 Windows libs already present in $DEST"
  exit 0
fi

echo "Building x264 for Windows (cross-compile with mingw-w64)..."

# ── Ensure tools ──────────────────────────────────────────────────────────────
for tool in nasm x86_64-w64-mingw32-gcc git make; do
  if ! command -v "$tool" &>/dev/null; then
    case "$tool" in
      nasm)                  brew install nasm ;;
      x86_64-w64-mingw32-gcc) brew install mingw-w64 ;;
      git|make)              xcode-select --install 2>/dev/null || true ;;
    esac
  fi
done

# ── Clone x264 ────────────────────────────────────────────────────────────────
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Cloning x264..."
git clone --depth 1 https://code.videolan.org/videolan/x264.git "$TMP/x264"

# ── Configure ─────────────────────────────────────────────────────────────────
PREFIX="$TMP/install"
mkdir -p "$PREFIX"

echo "Configuring..."
cd "$TMP/x264"
CC=x86_64-w64-mingw32-gcc \
./configure \
  --host=x86_64-w64-mingw32 \
  --cross-prefix=x86_64-w64-mingw32- \
  --prefix="$PREFIX" \
  --enable-static \
  --disable-shared \
  --disable-opencl \
  --disable-cli

# ── Build ─────────────────────────────────────────────────────────────────────
echo "Building (this may take a minute)..."
make -j"$(sysctl -n hw.logicalcpu)"
make install

# ── Copy artifacts ────────────────────────────────────────────────────────────
cp "$PREFIX/include/x264.h"        "$DEST/"
cp "$PREFIX/include/x264_config.h" "$DEST/" 2>/dev/null || true
cp "$PREFIX/lib/libx264.a"         "$DEST/"

echo "Done: $DEST/x264.h  $DEST/libx264.a"
