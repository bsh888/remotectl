#!/usr/bin/env bash
# Generate all platform icons from scripts/icon-source.svg
# Requires: rsvg-convert, magick (ImageMagick 7)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/scripts/icon-source.svg"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

rsvg() { rsvg-convert "$@"; }

echo "▶ icon source: $SRC"

# ── helper: render SVG at given size ────────────────────────────────────────
render() {
  local size="$1" out="$2"
  rsvg -w "$size" -h "$size" "$SRC" -o "$out"
}

# ── helper: render maskable (icon scaled to 80% safe zone, bg fill) ─────────
render_maskable() {
  local total="$1" out="$2"
  local safe=$(echo "$total * 0.80 / 1" | bc)
  local pad=$(( (total - safe) / 2 ))
  local tmp_icon="$TMP/mask_inner_${total}.png"
  rsvg -w "$safe" -h "$safe" "$SRC" -o "$tmp_icon"
  magick -size "${total}x${total}" xc:"#070A0F" \
    "$tmp_icon" -geometry "+${pad}+${pad}" -composite \
    "$out"
}

echo "▶ web favicons → client/public/"
WEB="$ROOT/client/public"
render 16  "$WEB/favicon-16.png"
render 32  "$WEB/favicon-32.png"
render 180 "$WEB/apple-touch-icon.png"

echo "▶ flutter web icons → app/web/icons/"
FWEB="$ROOT/app/web/icons"
render 192 "$FWEB/Icon-192.png"
render 512 "$FWEB/Icon-512.png"
render_maskable 192 "$FWEB/Icon-maskable-192.png"
render_maskable 512 "$FWEB/Icon-maskable-512.png"

echo "▶ macOS app icons → app/macos/…/AppIcon.appiconset/"
MAC="$ROOT/app/macos/Runner/Assets.xcassets/AppIcon.appiconset"
render 16   "$MAC/app_icon_16.png"
render 32   "$MAC/app_icon_32.png"
render 64   "$MAC/app_icon_64.png"
render 128  "$MAC/app_icon_128.png"
render 256  "$MAC/app_icon_256.png"
render 512  "$MAC/app_icon_512.png"
render 1024 "$MAC/app_icon_1024.png"

echo "▶ iOS app icons → app/ios/…/AppIcon.appiconset/"
IOS="$ROOT/app/ios/Runner/Assets.xcassets/AppIcon.appiconset"
render 20  "$IOS/Icon-App-20x20@1x.png"
render 40  "$IOS/Icon-App-20x20@2x.png"
render 60  "$IOS/Icon-App-20x20@3x.png"
render 29  "$IOS/Icon-App-29x29@1x.png"
render 58  "$IOS/Icon-App-29x29@2x.png"
render 87  "$IOS/Icon-App-29x29@3x.png"
render 40  "$IOS/Icon-App-40x40@1x.png"
render 80  "$IOS/Icon-App-40x40@2x.png"
render 120 "$IOS/Icon-App-40x40@3x.png"
render 120 "$IOS/Icon-App-60x60@2x.png"
render 180 "$IOS/Icon-App-60x60@3x.png"
render 76  "$IOS/Icon-App-76x76@1x.png"
render 152 "$IOS/Icon-App-76x76@2x.png"
render 167 "$IOS/Icon-App-83.5x83.5@2x.png"
render 1024 "$IOS/Icon-App-1024x1024@1x.png"

echo "▶ Android mipmap icons → app/android/…/res/"
AND="$ROOT/app/android/app/src/main/res"
render 48  "$AND/mipmap-mdpi/ic_launcher.png"
render 72  "$AND/mipmap-hdpi/ic_launcher.png"
render 96  "$AND/mipmap-xhdpi/ic_launcher.png"
render 144 "$AND/mipmap-xxhdpi/ic_launcher.png"
render 192 "$AND/mipmap-xxxhdpi/ic_launcher.png"

echo "▶ Windows ICO → app/windows/runner/resources/app_icon.ico"
WIN_ICO="$ROOT/app/windows/runner/resources/app_icon.ico"
ICO_TMP="$TMP"
for sz in 16 32 48 64 128 256; do
  render "$sz" "$ICO_TMP/win_${sz}.png"
done
magick "$ICO_TMP/win_256.png" "$ICO_TMP/win_128.png" \
       "$ICO_TMP/win_64.png"  "$ICO_TMP/win_48.png"  \
       "$ICO_TMP/win_32.png"  "$ICO_TMP/win_16.png"  \
       "$WIN_ICO"

echo "✓ all icons generated"
