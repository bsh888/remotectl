# RemoteCtl

跨平台远程桌面工具，支持 macOS / Windows / Linux 被控端，浏览器或原生 App 作为控制端。

## 功能特性

- **H.264 硬件编码**：macOS 使用 VideoToolbox，Windows/Linux 使用 x264
- **WebRTC 传输**：视频流点对点直连，服务器不经手视频数据
- **TURN 中继**：自动为无法打洞的网络（移动 4G/5G、对称型 NAT）提供中继
- **E2EE 输入加密**：ECDH P-256 + HKDF-SHA256 + AES-256-GCM，或通过 WebRTC DataChannel 的 DTLS 加密传输
- **低延迟鼠标**：输入事件走 WebRTC DataChannel P2P 直连，本地光标叠加层即时反馈
- **跨平台剪贴板**：从控制端粘贴文本到远程（中文/Emoji 均支持）
- **Ctrl ⇄ Cmd 自动转换**：Windows/Linux 连接 Mac 时自动映射快捷键
- **TLS 加密传输**：信令通道全程 TLS，支持自签名证书
- **自动重连**：被控端 pipeline 异常中断后自动重启，无需人工干预
- **YAML 配置文件**：服务端和 agent 均支持配置文件，无需记忆命令行参数
- **Docker 部署**：服务器一键容器化部署

## 架构

```
浏览器 / 原生 App (viewer)
  │  WebSocket (信令 + 输入 E2EE fallback)
  │  WebRTC DataChannel (输入，DTLS 加密，P2P / TURN)
  │  WebRTC Video Track  (H.264，DTLS-SRTP，P2P / TURN)
  ↓
中继服务器 (server)      ← 只转发信令；视频/输入走 P2P 或 TURN
  │  WebSocket
  ↓
被控端 agent (macOS/Win/Linux)
  ├── pipeline: 屏幕采集 + H.264 编码
  └── input:   鼠标/键盘注入
```

## 目录结构

```
remotectl/
├── agent/              # 被控端 (Go + CGO)
│   ├── pipeline/       # 屏幕采集 + 编码（平台相关）
│   └── input/          # 鼠标键盘注入（平台相关）
├── server/             # 中继服务器 (Go)
├── client/             # 控制端前端 (React + TypeScript)
├── app/                # 原生客户端 App (Flutter，全平台)
├── scripts/            # 证书生成工具
├── certs/              # TLS 证书（本地生成，不提交）
├── server.yaml.example # 服务端配置示例
├── agent.yaml.example  # agent 配置示例
└── Makefile
```

---

## 构建依赖

### 服务器 & 前端（所有平台通用）

| 工具 | 版本要求 |
|------|---------|
| Go   | 1.21+   |
| Node.js | 18+  |
| Flutter | 3.19+（原生客户端 app，可选） |

### 被控端 — macOS

| 依赖 | 说明 |
|------|------|
| Xcode Command Line Tools | `xcode-select --install` |
| CGO | 必须启用（`CGO_ENABLED=1`） |

系统框架由 CGO 自动链接，无需额外安装：
`ScreenCaptureKit · VideoToolbox · CoreMedia · CoreVideo · ApplicationServices`

### 被控端 — Windows

| 依赖 | 说明 |
|------|------|
| x264 静态库 | 放在 `agent/pipeline/x264/` 下（`libx264.a` + 头文件） |
| mingw-w64（macOS 交叉编译） | `brew install mingw-w64` |

### 被控端 — Linux

```bash
# Debian/Ubuntu
sudo apt install gcc libx264-dev libx11-dev libxext-dev xdotool

# Fedora/RHEL
sudo dnf install gcc x264-devel libX11-devel libXext-devel xdotool

# Arch
sudo pacman -S gcc x264 libx11 libxext xdotool
```

---

## 快速开始

### 1. 生成 TLS 证书

```bash
# 仅本地访问
make cert

# 指定 IP（支持多个，逗号分隔）
make cert IP=192.168.1.100
make cert IP="10.0.0.1,192.168.1.100"

# IP + 域名
make cert IP="10.0.0.1" DNS=myserver.local
```

证书生成在 `./certs/`，`server.crt` 需分发到所有被控端（`ca_cert` 配置项）。

macOS 将证书加入系统信任：
```bash
make trust-cert
```

### 2. 配置服务端

复制示例配置并编辑：

```bash
cp server.yaml.example server.yaml
```

`server.yaml` 内容说明：

```yaml
addr:     ":8443"
password: "your-viewer-password"   # 控制端连接密码

tls_cert: "/certs/server.crt"
tls_key:  "/certs/server.key"
static:   "/app/static"

# 设备 token：device_id → 密钥
# agent 通过 HMAC-SHA256 认证，留空则接受所有 agent（仅开发用）
tokens:
  my-mac: "replace-with-a-strong-secret"
  my-win: "another-secret"

# TURN 中继（移动网络 / 对称型 NAT 必须配置，局域网可留空）
turn:
  url:      ""            # 例如 turn:1.2.3.4:3478
  user:     "remotectl"
  password: "changeme"
```

### 3. 启动服务器

**Docker 部署（推荐）：**
```bash
docker compose up -d
```

**直接运行：**
```bash
./bin/remotectl-server --config server.yaml
```

服务端所有参数均可通过配置文件或命令行 flag 指定，flag 优先级更高：

| 配置项 | Flag | 说明 | 默认值 |
|--------|------|------|--------|
| `addr` | `--addr` | 监听地址 | `:8080` |
| `password` | `--password` | 控制端连接密码 | `remotectl` |
| `tls_cert` | `--tls-cert` | TLS 证书路径 | — |
| `tls_key` | `--tls-key` | TLS 私钥路径 | — |
| `static` | `--static` | 前端静态文件目录 | `./static` |
| `turn.url` | `--turn-url` | TURN 服务器地址 | — |
| `turn.user` | `--turn-user` | TURN 用户名 | — |
| `turn.password` | `--turn-credential` | TURN 密码 | — |
| `tokens` | — | 仅支持配置文件 | — |

### 4. 配置并启动被控端

```bash
cp agent.yaml.example agent.yaml
```

`agent.yaml` 内容说明：

```yaml
server:   "https://your-server:8443"
id:       "my-mac"          # 与 server.yaml tokens 中的键一致
token:    "replace-with-a-strong-secret"
name:     "My Mac"          # 控制端显示的设备名称

fps:      30
bitrate:  3000000           # 3 Mbps
scale:    0.5               # 采集分辨率缩放比例（0.5 = 半分辨率）
retry:    "5s"              # 断线重连间隔

insecure: false
# ca_cert: "certs/server.crt"   # 使用自签名证书时填写
```

**macOS：**
```bash
./bin/remotectl-agent-mac-arm64 --config agent.yaml
```

**Windows（PowerShell）：**
```powershell
.\remotectl-agent-windows-amd64.exe --config agent.yaml
```

**Linux：**
```bash
./remotectl-agent-linux-amd64 --config agent.yaml
```

命令行 flag 可覆盖配置文件中的任意值：

| 配置项 | Flag | 说明 | 默认值 |
|--------|------|------|--------|
| `server` | `--server` | 中继服务器地址 | 必填 |
| `id` | `--id` | 设备唯一标识 | 必填 |
| `token` | `--token` | 认证 token | — |
| `name` | `--name` | 设备显示名称 | 同 id |
| `ca_cert` | `--ca-cert` | 自签名 CA 证书路径 | — |
| `scale` | `--scale` | 采集分辨率缩放（0.25–1.0） | `0.5` |
| `fps` | `--fps` | 目标帧率 | `30` |
| `bitrate` | `--bitrate` | H.264 目标码率（bps） | `3000000` |
| `insecure` | `--insecure` | 跳过 TLS 验证（仅开发） | `false` |

### 5. 浏览器访问

打开 `https://your-server:8443`，输入服务器地址、设备 ID、连接密码即可。

### 6. 原生客户端 App

在 `app/` 目录下提供了 Flutter 客户端，支持 Android / iOS / macOS / Windows / Linux：

```bash
cd app
flutter pub get

flutter run -d macos     # macOS
flutter run -d windows   # Windows
flutter run -d linux     # Linux
flutter run              # Android / iOS（连接手机后自动选择）
```

详细说明见 [app/README.md](app/README.md)。

---

## TURN 中继配置

### 什么时候需要 TURN

| 网络类型 | P2P 打洞 | 是否需要 TURN |
|---------|---------|-------------|
| 同一局域网 | 直连，不出网 | 否 |
| 家用宽带（有公网 IP） | 大概率成功 | 建议配置 |
| 家用宽带（运营商 NAT） | 约 50% 失败 | 需要 |
| 手机 4G / 5G | 几乎必失败 | **必须** |
| 企业/办公网络 | 大概率失败 | **必须** |

### 部署 coturn

docker-compose.yml 中已内置 coturn 服务，部署时只需在 `server.yaml` 填入 ECS 公网 IP：

```yaml
turn:
  url:      "turn:你的ECS公网IP:3478"
  user:     "remotectl"
  password: "自定义强密码"
```

ECS 安全组需放行：

| 端口 | 协议 | 用途 |
|------|------|------|
| 3478 | UDP + TCP | TURN/STUN |
| 49152–65535 | UDP | TURN 中继数据 |

TURN 配置只需在服务端设置一次，服务端会在信令握手时自动下发给所有 agent 和控制端。

### 带宽费用估算

TURN 中继仅在 P2P 打洞失败时启用。使用阿里云/腾讯云按流量计费时：

| 编码码率 | 每小时流量 | 参考费用（¥0.8/GB） |
|---------|-----------|-------------------|
| 1 Mbps  | ~450 MB   | ~¥0.36/h |
| 3 Mbps  | ~1.3 GB   | ~¥1.05/h |
| 6 Mbps  | ~2.7 GB   | ~¥2.16/h |

> 高频使用建议选购包月固定带宽，比按流量划算。

---

## 构建

```bash
# 完整构建（前端 + 服务器 + macOS agent）
make all

# 单独构建
make server          # 服务器
make client          # 前端
make agent-mac       # macOS agent（arm64 + amd64）
make agent-win       # Windows agent（需要 mingw-w64）
make agent-linux     # Linux agent（需要 musl-cross 或在 Linux 上直接构建）

# 整理依赖
make tidy
```

Linux 交叉编译（macOS 宿主机）：
```bash
brew install FiloSottile/musl-cross/musl-cross
make agent-linux
```

---

## 平台特性对比

| 功能 | macOS | Windows | Linux |
|------|-------|---------|-------|
| 屏幕采集 | ScreenCaptureKit (SCStream) | GDI BitBlt | X11 XShm |
| 视频编码 | VideoToolbox H.264 High Profile（硬件，CABAC） | x264（软件） | x264（软件） |
| 鼠标注入 | CGEventPost | SendInput | xdotool |
| 键盘注入 | CGEventPost | SendInput | xdotool |
| 文本粘贴 | CGEventKeyboardSetUnicodeString | SendInput KEYEVENTF_UNICODE | xdotool type |
| 权限要求 | 辅助功能 + 屏幕录制 | 无需特殊权限 | 需要 X11 显示 |

---

## macOS 权限配置

首次运行需要在系统设置中授权：

1. **屏幕录制**：`系统设置 → 隐私与安全性 → 屏幕录制` → 开启 remotectl-agent
2. **辅助功能**：`系统设置 → 隐私与安全性 → 辅助功能` → 开启 remotectl-agent

未授权时 agent 会打印警告：
```
WARNING: Screen Recording permission not granted
WARNING: Accessibility permission not granted — mouse/keyboard injection will fail
```

---

## 控制端操作说明

### 键盘快捷键

工具栏提供 **`Ctrl ⇄ ⌘`** 开关：
- **开启**（非 Mac 连接 Mac 时默认）：Ctrl+C/V/Z/A 等自动转换为 Cmd+C/V/Z/A
- **关闭**：按键原样发送

> 注意：浏览器控制端的 `Ctrl+T`、`Ctrl+W`、`F5/F11/F12` 等快捷键会被浏览器拦截，原生 App 不受此限制。

### 剪贴板粘贴

两种方式将本地内容粘贴到远程：

1. **鼠标移入视频区域，直接按 Ctrl+V**（推荐）
2. **点击工具栏"粘贴"按钮**（需要浏览器剪贴板权限）

支持任意 Unicode 内容（中文、日文、Emoji 等）。

### 画质与流畅度调节

通过 `agent.yaml` 调整：

| 需求 | 推荐配置 |
|------|---------|
| 清晰优先（局域网） | `scale: 1.0  fps: 30  bitrate: 6000000` |
| 均衡（默认） | `scale: 0.5  fps: 30  bitrate: 3000000` |
| 流量节省 | `scale: 0.75  fps: 24  bitrate: 1500000` |
| 极低带宽 | `scale: 0.5  fps: 15  bitrate: 800000` |

---

## 安全说明

| 通道 | 加密方式 |
|------|---------|
| 信令（WebSocket） | TLS 1.3 |
| 视频流（WebRTC） | DTLS-SRTP，端对端，服务器不可见 |
| 鼠标/键盘输入（DataChannel） | DTLS，端对端，服务器不可见 |
| 键盘输入（WebSocket fallback） | ECDH P-256 + HKDF-SHA256 + AES-256-GCM |
| Agent 认证 | 每设备独立 token（HMAC-SHA256 挑战响应） |

---

## 已知限制

- **浏览器快捷键冲突**：`Ctrl+T/W/N/L`、`F5/F11/F12` 等被浏览器拦截，使用原生 App 无此问题
- **多显示器**：目前仅采集主显示器
- **Linux 依赖 X11**：Wayland 桌面需通过 XWayland 兼容层运行
- **Windows 编码**：使用软件 x264，高分辨率时 CPU 占用较高
- **音频**：暂不支持音频传输
