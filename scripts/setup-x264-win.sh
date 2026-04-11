#!/usr/bin/env bash
# setup-x264-win.sh — Download Windows x264 static library for cross-compilation.
#
# Fetches the mingw-w64-x86_64-x264 package from the MSYS2 mirror and
# extracts x264.h + libx264.a into agent/pipeline/x264/.
#
# Called automatically by release.sh when the files are missing.
# Can also be run manually: ./scripts/setup-x264-win.sh

set -euo pipefail

DEST="$(cd "$(dirname "$0")/.." && pwd)/agent/pipeline/x264"
mkdir -p "$DEST"

if [[ -f "$DEST/x264.h" && -f "$DEST/libx264.a" ]]; then
  echo "x264 Windows libs already present in $DEST"
  exit 0
fi

echo "Setting up x264 Windows cross-compile libs..."

# ── Ensure zstd is available (needed to unpack .pkg.tar.zst) ─────────────────
if ! command -v zstd &>/dev/null; then
  echo "Installing zstd via Homebrew..."
  brew install zstd
fi

# ── Find latest package URL from MSYS2 mingw64 ───────────────────────────────
BASE="https://repo.msys2.org/mingw/mingw64"
echo "Querying MSYS2 package list..."
PKG=$(curl -fsSL "$BASE/" \
  | grep -o 'mingw-w64-x86_64-x264-[0-9][^"]*\.pkg\.tar\.zst' \
  | sort -V | tail -1)

[[ -n "$PKG" ]] || { echo "ERROR: Could not find x264 package on MSYS2 mirror." >&2; exit 1; }
echo "Found: $PKG"

# ── Download ──────────────────────────────────────────────────────────────────
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Downloading..."
curl -fL "$BASE/$PKG" -o "$TMP/x264.pkg.tar.zst"

# ── Extract ───────────────────────────────────────────────────────────────────
echo "Extracting..."
zstd -d --quiet "$TMP/x264.pkg.tar.zst" -o "$TMP/x264.pkg.tar"
tar xf "$TMP/x264.pkg.tar" -C "$TMP"

# ── Copy header and static library ───────────────────────────────────────────
cp "$TMP/mingw64/include/x264.h" "$DEST/"
cp "$TMP/mingw64/lib/libx264.a"  "$DEST/"

echo "Done: $DEST/x264.h  $DEST/libx264.a"
