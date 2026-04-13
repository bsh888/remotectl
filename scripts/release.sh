#!/usr/bin/env bash
# release.sh — Build all release artifacts and publish a GitHub Release.
#
# Run on macOS. Builds:
#   - server      : linux-amd64, linux-arm64  (pure Go, cross-compile)
#   - agent       : mac universal, win-amd64, linux-amd64  (CGO cross-compile)
#   - Flutter app : macOS (.app → .zip)
#
# Flutter Windows / Linux apps must be built on their native platforms and
# uploaded separately via:  scripts/upload-release.sh <version>
#
# Requirements:
#   brew install mingw-w64 FiloSottile/musl-cross/musl-cross gh
#   flutter SDK in PATH
#
# Usage:
#   ./scripts/release.sh v1.2.3
#   ./scripts/release.sh v1.2.3 --draft      # create as draft first

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)

# ── Args ──────────────────────────────────────────────────────────────────────

VERSION="${1:-}"
[[ -n "$VERSION" ]] || { echo "Usage: $0 <version>  e.g. $0 v1.0.0" >&2; exit 1; }
[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || { echo "Version must be vX.Y.Z (got: $VERSION)" >&2; exit 1; }

DRAFT_FLAG=""
[[ "${2:-}" == "--draft" ]] && DRAFT_FLAG="--draft"

OUT="$ROOT/deploy/release/$VERSION"
rm -rf "$OUT"
mkdir -p "$OUT"

log()  { echo ""; echo "▶ $*"; }
ok()   { echo "  ✓ $*"; }
die()  { echo "✗ $*" >&2; exit 1; }

# ── Checks ───────────────────────────────────────────────────────────────────

command -v gh      &>/dev/null || die "gh not found. brew install gh && gh auth login"
command -v flutter &>/dev/null || die "flutter not found."
command -v x86_64-w64-mingw32-gcc &>/dev/null \
  || die "mingw-w64 not found. brew install mingw-w64"

# Ensure working tree is clean
if [[ -n "$(git status --porcelain)" ]]; then
  die "Working tree is dirty. Commit or stash changes before releasing."
fi

# ── Clean up any previous failed release attempt ──────────────────────────────
if git rev-parse "$VERSION" &>/dev/null; then
  log "Removing existing tag $VERSION (re-release)"
  git tag -d "$VERSION"
  git push origin ":refs/tags/$VERSION" 2>/dev/null || true
  ok "Local + remote tag removed"
fi
if gh release view "$VERSION" --repo bsh888/remotectl-releases &>/dev/null 2>&1; then
  gh release delete "$VERSION" --repo bsh888/remotectl-releases --yes 2>/dev/null || true
  gh api "repos/bsh888/remotectl-releases/git/refs/tags/$VERSION" --method DELETE 2>/dev/null || true
  ok "Release repo tag + release removed"
fi

log "Building release $VERSION"
echo "  Output: $OUT"

# ── Helper: package server ────────────────────────────────────────────────────
# pack_server <binary_src> <os-arch-label>
pack_server() {
  local src="$1" label="$2"
  local name="remotectl-server-${label}-${VERSION}"
  local dir="$OUT/tmp/$name"
  mkdir -p "$dir"
  cp "$src" "$dir/remotectl-server"
  cp deploy/install.sh                  "$dir/"
  cp deploy/remotectl-server.service    "$dir/"
  cp deploy/server.yaml.example         "$dir/"
  cp scripts/gen-cert.sh                "$dir/"
  # Copy static web UI (built below); exclude .gitkeep placeholder
  mkdir -p "$dir/static"
  rsync -a --exclude='.gitkeep' deploy/static/ "$dir/static/"
  chmod +x "$dir/remotectl-server" "$dir/install.sh" "$dir/gen-cert.sh"
  COPYFILE_DISABLE=1 tar -czf "$OUT/${name}.tar.gz" -C "$OUT/tmp" "$name"
  rm -rf "$dir"
  ok "${name}.tar.gz"
}

# ── Helper: package agent ──────────────────────────────────────────────────────
# pack_agent <binary_src> <os-arch-label> [zip|tar]
pack_agent() {
  local src="$1" label="$2" fmt="${3:-tar}"
  local name="remotectl-agent-${label}-${VERSION}"
  local dir="$OUT/tmp/$name"
  mkdir -p "$dir"
  local bname="remotectl-agent"
  [[ "$fmt" == "zip" ]] && bname="remotectl-agent.exe"
  cp "$src" "$dir/$bname"
  cp deploy/agent.yaml.example "$dir/"
  chmod +x "$dir/$bname" 2>/dev/null || true
  if [[ "$fmt" == "zip" ]]; then
    (cd "$OUT/tmp" && zip -r "$OUT/${name}.zip" "$name")
  else
    tar -czf "$OUT/${name}.tar.gz" -C "$OUT/tmp" "$name"
  fi
  rm -rf "$dir"
  ok "${name}.${fmt/tar/tar.gz}"
}

mkdir -p "$OUT/tmp"

# ── 0. Frontend (web UI) ──────────────────────────────────────────────────────

log "Building web client"
(cd client && npm run build)
touch deploy/static/.gitkeep
ok "deploy/static/"

# ── 1. Server — linux amd64 / arm64 ──────────────────────────────────────────

log "Building server (linux-amd64)"
(cd server && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
  go build -ldflags="-s -w" -o "$OUT/tmp/remotectl-server-linux-amd64" .)
pack_server "$OUT/tmp/remotectl-server-linux-amd64" "linux-amd64"

log "Building server (linux-arm64)"
(cd server && GOOS=linux GOARCH=arm64 CGO_ENABLED=0 \
  go build -ldflags="-s -w" -o "$OUT/tmp/remotectl-server-linux-arm64" .)
pack_server "$OUT/tmp/remotectl-server-linux-arm64" "linux-arm64"

# ── 2. Agent — macOS universal ────────────────────────────────────────────────

log "Building agent (mac-arm64)"
(cd agent && CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 \
  go build -ldflags="-s -w" -o "$OUT/tmp/remotectl-agent-mac-arm64" .)

log "Building agent (mac-amd64)"
(cd agent && CGO_ENABLED=1 GOOS=darwin GOARCH=amd64 \
  go build -ldflags="-s -w" -o "$OUT/tmp/remotectl-agent-mac-amd64" .)

lipo -create \
  "$OUT/tmp/remotectl-agent-mac-arm64" \
  "$OUT/tmp/remotectl-agent-mac-amd64" \
  -output "$OUT/tmp/remotectl-agent-mac-universal"
# macOS agent is bundled inside remotectl-app-macos; no standalone package needed.

# ── 3. Agent — Windows amd64 ─────────────────────────────────────────────────

# Ensure Windows x264 cross-compile libs are present.
if [[ ! -f "agent/pipeline/x264/x264.h" || ! -f "agent/pipeline/x264/libx264.a" ]]; then
  log "Fetching Windows x264 cross-compile libs"
  bash "$ROOT/scripts/setup-x264-win.sh"
fi

log "Building agent (windows-amd64)"
x86_64-w64-mingw32-windres agent/resource_windows.rc -O coff -o agent/rsrc_windows.syso
(cd agent && CGO_ENABLED=1 GOOS=windows GOARCH=amd64 \
  CC=x86_64-w64-mingw32-gcc \
  go build -ldflags="-s -w -H windowsgui" \
  -o "$OUT/tmp/remotectl-agent-windows-amd64.exe" .)
# Windows agent is bundled inside remotectl-app-windows; no standalone package needed.

# ── 4. Agent — Linux amd64 ───────────────────────────────────────────────────
# X11 headers are not available on macOS; build on a Linux machine and upload
# via scripts/upload-release.sh after this script completes.
log "Skipping agent (linux-amd64) — build on Linux and upload separately"
echo "  → On Linux: cd agent && CGO_ENABLED=1 go build -ldflags='-s -w' -o remotectl-agent-linux-amd64 ."
echo "  → Then run: scripts/upload-release.sh $VERSION"

# ── 5. Flutter — macOS app ───────────────────────────────────────────────────

log "Building Flutter macOS app"
bash scripts/build-app-mac.sh
# build-app-mac.sh outputs deploy/bin/remotectl-macos.zip
MACOS_ZIP="deploy/bin/remotectl-macos.zip"
[[ -f "$MACOS_ZIP" ]] || die "Flutter macOS build failed: $MACOS_ZIP not found"
cp "$MACOS_ZIP" "$OUT/remotectl-app-macos-${VERSION}.zip"
ok "remotectl-app-macos-${VERSION}.zip"

# ── Cleanup tmp ──────────────────────────────────────────────────────────────

rm -rf "$OUT/tmp"

# ── List artifacts ────────────────────────────────────────────────────────────

log "Artifacts"
ls -lh "$OUT/"*.{tar.gz,zip} 2>/dev/null | awk '{print "  "$NF, $5}'

# ── Tag ───────────────────────────────────────────────────────────────────────

log "Tagging $VERSION"
git tag -a "$VERSION" -m "Release $VERSION"
git push origin "$VERSION"
ok "Tag pushed"

# ── Sync README to releases repo (create on first run, update thereafter) ─────
log "Syncing README to bsh888/remotectl-releases"
README_SHA=$(gh api repos/bsh888/remotectl-releases/contents/README.md --jq '.sha' 2>/dev/null || true)
README_ARGS=()
[[ -n "$README_SHA" ]] && README_ARGS=(-f "sha=$README_SHA")
gh api repos/bsh888/remotectl-releases/contents/README.md \
    --method PUT \
    "${README_ARGS[@]}" \
    -f message="Update README for $VERSION" \
    -f content="$(printf '%s' '# RemoteCtl

跨平台远程桌面工具，支持 macOS / Windows / Linux 被控端，浏览器或原生 App 作为控制端。

## 功能特性

- **H.264 硬件编码**：macOS 使用 VideoToolbox，Windows/Linux 使用 x264
- **WebRTC 传输**：视频流点对点直连，服务器不经手视频数据
- **TURN 中继**：自动为移动网络 / 对称型 NAT 提供中继
- **E2EE 输入加密**：ECDH P-256 + AES-256-GCM 端对端加密输入事件
- **低延迟鼠标**：本地光标叠加层即时反馈，输入走 P2P DataChannel
- **跨平台剪贴板**：控制端粘贴文本到远程，支持中文 / Emoji
- **会话内聊天**：控制端与被控端实时文字消息 + 文件互传
- **会话密码认证**：每次启动随机生成 8 位数字密码，简单安全
- **一体化桌面 App**：macOS/Windows/Linux 原生 App 同时内置"远程控制"和"共享本机"两种模式

## 下载

前往 [Releases](https://github.com/bsh888/remotectl-releases/releases) 页面下载对应平台的安装包。

| 文件 | 说明 |
|------|------|
| `remotectl-app-macos-vX.Y.Z.zip` | macOS App（控制端 + 被控端二合一） |
| `remotectl-app-windows-amd64-vX.Y.Z.zip` | Windows App（控制端 + 被控端二合一） |
| `remotectl-app-linux-amd64-vX.Y.Z.tar.gz` | Linux App（控制端 + 被控端二合一） |
| `remotectl-agent-linux-amd64-vX.Y.Z.tar.gz` | Linux 被控端（无 GUI / headless 服务器） |
| `remotectl-server-linux-amd64-vX.Y.Z.tar.gz` | 信令服务器 Linux x86_64（含 systemd 部署脚本） |
| `remotectl-server-linux-arm64-vX.Y.Z.tar.gz` | 信令服务器 Linux ARM64（含 systemd 部署脚本） |

## 快速开始

### 桌面 App（控制端 + 被控端）

下载对应平台的 `remotectl-app-*` 包，解压直接运行。App 内置两种模式：
- **远程控制**：输入设备 ID + 会话密码，连接并控制远程机器
- **共享本机**：将本机屏幕共享给控制端

### Linux 无 GUI 被控端

适用于无桌面环境的 Linux 服务器，下载 `remotectl-agent-linux-amd64-*` 包：

```bash
tar xzf remotectl-agent-linux-amd64-vX.Y.Z.tar.gz
cd remotectl-agent-linux-amd64-vX.Y.Z
cp agent.yaml.example agent.yaml
vim agent.yaml   # 填入 server 地址和 token
./remotectl-agent --config agent.yaml
```

### 信令服务器（自建）

下载 `remotectl-server-linux-*` 包，解压后一键部署为 systemd 服务：

```bash
tar xzf remotectl-server-linux-amd64-vX.Y.Z.tar.gz
cd remotectl-server-linux-amd64-vX.Y.Z

# （可选）生成自签名 TLS 证书，如已有域名证书可跳过此步
bash gen-cert.sh ./certs 1.2.3.4          # 替换为服务器公网 IP
# 或同时绑定域名：
# bash gen-cert.sh ./certs 1.2.3.4 my.domain.com

sudo bash install.sh     # 安装到 /opt/remotectl，绑定 443 端口，无需 root
sudo vim /opt/remotectl/server.yaml   # 填入 tokens、TLS 证书路径、TURN 配置
sudo systemctl restart remotectl-server
```

## 平台支持

| 平台 | 控制端 | 被控端 |
|------|--------|--------|
| macOS | ✅ App | ✅ App 内置 |
| Windows | ✅ App | ✅ App 内置 |
| Linux | ✅ App | ✅ App 内置 / 独立 agent |
| iOS | ✅ App | ❌ |
| Android | ✅ App | ❌ |
' | base64)" \
    --silent
ok "README synced"

# ── GitHub Release ────────────────────────────────────────────────────────────

log "Creating GitHub Release $VERSION"
NOTES="## $VERSION

### 包含内容

| 文件 | 说明 |
|------|------|
| \`remotectl-server-linux-amd64-${VERSION}.tar.gz\` | 信令服务器 Linux x86_64（含 systemd 部署脚本） |
| \`remotectl-server-linux-arm64-${VERSION}.tar.gz\` | 信令服务器 Linux ARM64 |
| \`remotectl-agent-linux-amd64-${VERSION}.tar.gz\` | 被控端 Linux x86_64（命令行 / 无 GUI 服务器，Linux 上补传） |
| \`remotectl-app-macos-${VERSION}.zip\` | 控制端+被控端 Flutter macOS App |
| \`remotectl-app-windows-amd64-${VERSION}.zip\` | 控制端+被控端 Flutter Windows App（Windows 补传） |
| \`remotectl-app-linux-amd64-${VERSION}.tar.gz\` | 控制端+被控端 Flutter Linux App（Linux 补传） |

> Linux agent、Windows / Linux Flutter App 在各平台编译后通过 \`scripts/upload-release.sh $VERSION\` 追加上传。

### 快速部署（服务器）

\`\`\`bash
# 解压后编辑 server.yaml，再执行安装
tar xzf remotectl-server-linux-amd64-${VERSION}.tar.gz
cd remotectl-server-linux-amd64-${VERSION}
vim server.yaml.example   # 复制并修改
sudo bash install.sh
\`\`\`
"

NOTES_FILE=$(mktemp)
printf '%s' "$NOTES" > "$NOTES_FILE"

GH_EDITOR=true gh release create "$VERSION" \
  --repo bsh888/remotectl-releases \
  $DRAFT_FLAG \
  --title "RemoteCtl $VERSION" \
  --notes-file "$NOTES_FILE" \
  "$OUT"/*.tar.gz \
  "$OUT"/*.zip

rm -f "$NOTES_FILE"

log "Done"
echo ""
echo "  Release: $(gh release view "$VERSION" --repo bsh888/remotectl-releases --json url -q .url)"
echo ""
echo "  Linux agent: on Linux server:"
echo "               cd agent && CGO_ENABLED=1 go build -ldflags='-s -w' -o remotectl-agent-linux-amd64 ."
echo "               scripts/upload-release.sh $VERSION"
echo ""
echo "  Windows App: run  scripts/build-app-win.ps1  on Windows, then"
echo "               run  scripts/upload-release.sh $VERSION  to upload."
echo "  Linux App:   run  scripts/build-app-linux.sh  on Linux, then"
echo "               run  scripts/upload-release.sh $VERSION  to upload."
echo ""
