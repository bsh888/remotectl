#!/usr/bin/env bash
# upload-release.sh — Upload Linux/Windows artifacts to an existing GitHub Release.
#
# Run on Linux or Windows (Git Bash) after building locally.
# The GitHub Release must already exist (created by release.sh on macOS).
#
# Usage:
#   ./scripts/upload-release.sh <version> [agent|app|all]
#
#   agent  — upload remotectl-agent-linux-amd64 (Linux only)
#   app    — upload Flutter app bundle for current platform
#   all    — upload both agent and app (Linux default)

set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-}"
[[ -n "$VERSION" ]] || { echo "Usage: $0 <version> [agent|app|all]" >&2; exit 1; }

MODE="${2:-all}"

command -v gh &>/dev/null || { echo "gh not found. Install: https://cli.github.com" >&2; exit 1; }

OS=$(uname -s | tr '[:upper:]' '[:lower:]')

upload() {
  local src="$1" name="$2"
  [[ -f "$src" ]] || { echo "Not found: $src  — build it first." >&2; return 1; }
  echo "Uploading $name..."
  gh release upload "$VERSION" "$src#$name" --repo bsh888/remotectl --clobber
}

case "$OS" in
  linux*)
    if [[ "$MODE" == "agent" || "$MODE" == "all" ]]; then
      # Build agent if not already built
      if [[ ! -f "agent/remotectl-agent-linux-amd64" ]]; then
        echo "Building Linux agent..."
        (cd agent && CGO_ENABLED=1 go build -ldflags="-s -w" -o remotectl-agent-linux-amd64 .)
      fi
      # Package with config example
      TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
      PKGNAME="remotectl-agent-linux-amd64-${VERSION}"
      mkdir "$TMP/$PKGNAME"
      cp agent/remotectl-agent-linux-amd64 "$TMP/$PKGNAME/remotectl-agent"
      cp deploy/agent.yaml.example         "$TMP/$PKGNAME/"
      chmod +x "$TMP/$PKGNAME/remotectl-agent"
      tar -czf "$TMP/${PKGNAME}.tar.gz" -C "$TMP" "$PKGNAME"
      upload "$TMP/${PKGNAME}.tar.gz" "${PKGNAME}.tar.gz"
    fi
    if [[ "$MODE" == "app" || "$MODE" == "all" ]]; then
      upload "deploy/bin/remotectl-linux-amd64.tar.gz" \
             "remotectl-app-linux-amd64-${VERSION}.tar.gz"
    fi
    ;;
  msys*|mingw*|cygwin*)
    upload "deploy/bin/remotectl-windows-amd64.zip" \
           "remotectl-app-windows-amd64-${VERSION}.zip"
    ;;
  *)
    echo "Unsupported platform: $OS" >&2; exit 1 ;;
esac

echo "Done: $(gh release view "$VERSION" --repo bsh888/remotectl --json url -q .url)"
