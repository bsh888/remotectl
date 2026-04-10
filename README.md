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
- **一体化桌面 App**：macOS/Windows/Linux 原生 App 同时内置"远程控制"和"共享本机"两种模式，一个程序搞定；iOS/Android 作纯控制端
- **两层认证**：服务器密码（Layer 1）+ 每次启动随机生成的 8 位会话密码（Layer 2），防暴力猜测
- **自动设备 ID**：被控端首次运行自动生成 9 位随机数字 ID 并持久化，无需手动配置
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
| Go | 官方安装包（`.msi`），从 [go.dev/dl](https://go.dev/dl/) 下载，**不要手动解压源码** |
| x264 静态库 | 放在 `agent/pipeline/x264/` 下（`libx264.a` + `x264.h`） |
| MSYS2 + MinGW-w64（Windows 本机编译） | 见下方说明 |
| mingw-w64（macOS 交叉编译） | `brew install mingw-w64` |

#### 在 Windows 本机编译 agent

**1. 安装 Go**

从 [go.dev/dl](https://go.dev/dl/) 下载 Windows `.msi` 安装包，按向导安装。
安装完成后打开新终端，验证：

```powershell
go version   # 应输出版本号，如 go1.22.x windows/amd64
go env GOROOT  # 应指向安装目录，如 C:\Program Files\Go
```

> **常见错误**：若出现 `package context is not in std (D:\go\src\context)` 等报错，
> 说明 `GOROOT` 环境变量被手动设置成了错误路径。
> 删除系统环境变量 `GOROOT`，重新安装 Go，或将其修正为 Go 的实际安装目录。

**2. 安装 MSYS2 + MinGW-w64 及 x264**

从 [msys2.org](https://www.msys2.org/) 安装 MSYS2，然后在 **MSYS2 MINGW64** 终端执行：

```bash
pacman -S mingw-w64-x86_64-gcc mingw-w64-x86_64-x264
```

将 x264 文件复制到项目：

```powershell
mkdir agent\pipeline\x264
copy C:\msys64\mingw64\include\x264.h    agent\pipeline\x264\
copy C:\msys64\mingw64\lib\libx264.a     agent\pipeline\x264\
```

**3. 将 MinGW bin 目录加入 PATH**

永久生效（管理员 PowerShell）：

```powershell
[System.Environment]::SetEnvironmentVariable(
  "PATH",
  "C:\msys64\mingw64\bin;" + [System.Environment]::GetEnvironmentVariable("PATH","Machine"),
  "Machine"
)
```

重开终端后验证：`gcc --version`

**4. 编译**

在项目 `agent/` 目录下（PowerShell）：

```powershell
$env:CGO_ENABLED = "1"
$env:CC          = "C:\msys64\mingw64\bin\gcc.exe"
go build -ldflags="-s -w -H windowsgui" -o remotectl-agent-windows-amd64.exe
```

> **注意**：Windows CMD 不支持 `VAR=val cmd` 的 Unix 语法，必须用 `set VAR=val`
> 或 PowerShell 的 `$env:VAR = "val"` 分行设置。

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

# Layer 1（服务器密码）：控制端连接服务器时必须提供此密码，防止未授权方扫描设备。
# 控制端 App"服务器密码"字段 / Web 端"服务器密码"输入框填此值。
# 留空 → 不检查（dev 模式，不推荐生产）。
password: "your-server-password"

# Layer 2（会话密码）：agent 每次启动自动生成 8 位随机数字，显示在"共享本机"页。
# 由 agent 自动管理，此处无需配置。

tls_cert: "/certs/server.crt"
tls_key:  "/certs/server.key"
static:   "/app/static"

# Agent 认证（三选一）：
#
# 推荐：全局 token — 任意设备只要持有此 token 就能注册，新增设备无需改配置。
#   App"共享本机"→"设备密钥"填这个值。
agent_token: "replace-with-a-strong-secret"

# 可选：按设备单独配置（优先级高于 agent_token，需要细粒度控制时使用）
# tokens:
#   123456789: "device-specific-secret"   # key = 9位设备 ID

# 两者均留空 → dev 模式，接受所有 agent（仅本地开发）

# TURN 中继（移动网络 / 对称型 NAT 必须配置，否则出现 WebRTC connection failed）
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
token:    "replace-with-a-strong-secret"   # 与 server.yaml agent_token 一致
name:     "My Mac"                         # 控制端显示的设备名称（可选）

# id 字段可留空：首次运行自动生成 9 位随机数字 ID 并持久化到本地文件。
# 若需固定 ID（按设备配置 token 时），在此填入：
# id: "123456789"

fps:      30
bitrate:  6000000           # 6 Mbps
scale:    0.75              # 采集分辨率缩放比例（0.75 = 75% 分辨率）
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
| `id` | `--id` | 设备唯一标识（留空自动生成 9 位数字） | 自动生成 |
| `token` | `--token` | 认证 token | — |
| `name` | `--name` | 设备显示名称 | 同 id |
| `ca_cert` | `--ca-cert` | 自签名 CA 证书路径 | — |
| `scale` | `--scale` | 采集分辨率缩放（0.25–1.0） | `0.75` |
| `fps` | `--fps` | 目标帧率 | `30` |
| `bitrate` | `--bitrate` | H.264 目标码率（bps） | `6000000` |
| `insecure` | `--insecure` | 跳过 TLS 验证（仅开发） | `false` |

### 5. 浏览器访问

打开 `https://your-server:8443`，填入：

| 字段 | 来源 |
|------|------|
| 服务器地址 | 部署服务器的地址 |
| **服务器密码** | `server.yaml` 中的 `password`（Layer 1） |
| 设备 ID | 被控端 App"共享本机"页面显示的 9 位数字 |
| **会话密码** | 被控端每次启动生成的 8 位数字（Layer 2） |

### 6. 原生客户端 App

Flutter 客户端支持全平台，且在桌面平台（macOS/Windows/Linux）上同时内置**远程控制**和**共享本机**两种模式，一个 App 无需分别安装。

#### 开发运行

```bash
cd app
flutter pub get

flutter run -d macos     # macOS
flutter run -d windows   # Windows
flutter run -d linux     # Linux
flutter run              # Android / iOS（连接手机后自动选择）
```

> 开发模式下测试被控端功能，需先编译 agent 二进制：
> ```bash
> make agent-mac      # macOS
> make agent-win      # Windows
> make agent-linux    # Linux
> ```
> `AgentService` 会自动在项目 `bin/` 目录中寻找二进制作为 fallback。

#### 发布打包（一键脚本）

编译 agent + 构建 Flutter app + 注入 agent + 打包压缩，全部自动完成。

**macOS**

前提：Xcode Command Line Tools、Flutter
```bash
./scripts/build-app-mac.sh
# 输出：bin/remotectl-macos.zip
# 发布：将 zip 拷贝到目标 Mac，解压后双击 remotectl.app 即可运行
```

**Windows**

前提：Go（.msi）、MSYS2 MinGW-w64（`C:\msys64\mingw64\bin` 在 PATH）、Flutter、开发者模式已开启
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-app-win.ps1
# 输出：bin\remotectl-windows-amd64.zip
# 发布：将 zip 拷贝到目标 Windows，解压后运行 remotectl.exe 即可
```

> `-ExecutionPolicy Bypass` 仅对本次执行有效，不修改系统策略。
> 若提示"禁止运行脚本"，也可永久允许：`Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`

**Linux**

前提：GCC、libx264-dev、libX11-dev、Flutter
```bash
./scripts/build-app-linux.sh
# 输出：bin/remotectl-linux-amd64.tar.gz
# 发布：将 tar.gz 拷贝到目标 Linux，解压后运行 bundle/remotectl 即可
```

> **注意**：Flutter 桌面应用依赖旁边的 DLL / .so 和 `data/` 目录，不能只发单个可执行文件。
> 以上脚本已将完整运行目录打包，目标机器无需安装任何运行时，解压即用。

#### App 密码说明

连接一台被控端需要两个密码，各自作用不同，请勿混淆：

| 字段 | 来源 | 说明 |
|------|------|------|
| **服务器密码**（"远程控制"页） | `server.yaml` → `password` | Layer 1：访问信令服务器的密码，阻止未授权方扫描设备 |
| **会话密码**（"远程控制"页） | 被控端每次启动自动生成 | Layer 2：8 位随机数字，显示在"共享本机"页，重启后更新 |
| **设备密钥**（"共享本机"页） | `server.yaml` → `agent_token` | 被控端向服务器注册时的 HMAC 鉴权密钥（≠ 以上两个密码） |

#### 设备 ID

首次运行时自动生成 9 位随机数字 ID（如 `372 918 405`），永久保存到本地：

- macOS / Linux：`~/.config/remotectl/device.id`
- Windows：`%APPDATA%\remotectl\device.id`

ID 显示在"共享本机"页面顶部，点击复制图标可复制。如需固定 ID（例如按设备配置 token），
在"共享本机" → **连接配置** 中指定，或通过 `agent.yaml` 的 `id:` 字段配置。

#### CA 证书配置（被控端）

使用自签名证书时，在"共享本机" → **高级设置** → **CA 证书路径** 中填入 `server.crt` 的绝对路径，
等同于命令行 `--ca-cert /path/to/server.crt`，无需打开 `--insecure`。

#### 各平台被控端支持

| 平台 | 控制端 | 被控端 |
|------|--------|--------|
| macOS | ✅ | ✅ |
| Windows | ✅ | ✅ |
| Linux | ✅ | ✅ |
| iOS | ✅ | ❌（系统沙箱限制） |
| Android | ✅ | ❌（系统沙箱限制） |

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
make agent-mac       # macOS agent 二进制（arm64 + amd64，输出到 bin/）
make agent-win       # Windows agent（需要 mingw-w64）
make agent-linux     # Linux agent（需要 musl-cross 或在 Linux 上直接构建）

# Flutter App 一体化打包（agent 自动注入到发布包）
make app-mac         # macOS：universal agent + flutter build macos
make app-win         # Windows：agent.exe + flutter build windows
make app-linux       # Linux：agent + flutter build linux

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
| 清晰优先（局域网） | `scale: 1.0   fps: 30  bitrate: 8000000` |
| 均衡（默认） | `scale: 0.75  fps: 30  bitrate: 6000000` |
| 流量节省 | `scale: 0.5   fps: 24  bitrate: 2000000` |
| 极低带宽 | `scale: 0.5  fps: 15  bitrate: 800000` |

---

## 安全说明

### 两层身份认证

连接一台被控设备需要通过两层独立校验：

1. **Layer 1 — 服务器密码**：控制端必须知道 `server.yaml` 中的 `password` 才能与信令服务器交互，阻止未授权方枚举在线设备。
2. **Layer 2 — 会话密码**：agent 每次启动随机生成 8 位数字（10⁸ 空间），控制端还需输入此密码才能接入具体设备。

两者独立校验，只知道其中一个无法连接。设备 ID 为 9 位随机数（10⁹ 空间），首次运行自动生成，不再使用可猜测的主机名。

### 三条通道的加密机制

#### 1. 信令通道（Agent ↔ Server ↔ Viewer，WebSocket）

```
Agent ──WSS/TLS 1.2+──▶ Server ──WSS/TLS 1.2+──▶ Viewer
```

传输层使用 TLS（`wss://`）加密，内容包括认证握手、SDP offer/answer、ICE 候选地址。
**Server 可以读取这些信令明文**，但信令中不含任何屏幕内容或输入内容。

#### 2. 视频通道（Agent ↔ Viewer，WebRTC Video Track）

```
Agent ──DTLS-SRTP──▶ Viewer（P2P 直连，或经 TURN 中继转发加密包）
```

WebRTC 强制要求 DTLS-SRTP，端对端加密。Server 和 TURN 中继只转发加密后的 UDP 包，
**无法解密视频内容**。每次会话 DTLS 握手生成新的临时密钥，无法重放。

#### 3. 输入通道（Viewer → Agent，两条路）

**主路：WebRTC DataChannel（DTLS）**

```
Viewer ──DTLS DataChannel──▶ Agent（P2P 直连）
```

鼠标移动走 `input-move`（unreliable/unordered，低延迟），点击/键盘/滚轮走 `input`
（reliable/ordered）。Server 只见加密 UDP 包，**无法看到按键内容**。

**备路：WebSocket E2EE fallback**（DataChannel 不可用时）

```
Viewer ──AES-256-GCM 密文──▶ Server（只转发密文）──▶ Agent
```

实现在 `agent/session/session.go`，协议如下：

1. Agent 生成临时 ECDH P-256 密钥对，将公钥经 Server 转发给 Viewer
2. Viewer 生成自己的临时密钥对，公钥回送 Agent
3. 双方独立 ECDH 计算共享密钥 → HKDF-SHA256（`info="remotectl-v1"`）→ 256-bit AES 密钥
4. 每条输入消息用 **AES-256-GCM + 随机 12 字节 nonce** 加密，nonce 前置于密文
5. 私钥从不离开各自端点，Server 只见密文，**无法解密**

### Server 能看到什么

| 数据 | 路径 | Server 可见性 |
|------|------|-------------|
| 视频流 | WebRTC DTLS-SRTP | ❌ 只见加密 UDP 包 |
| 鼠标/键盘（主路） | WebRTC DataChannel DTLS | ❌ 只见加密 UDP 包 |
| 鼠标/键盘（备路） | WebSocket + AES-256-GCM | ❌ 只见密文 |
| 信令（SDP/ICE 候选） | WebSocket TLS | ✅ 可见（设备 ID、网络地址） |
| Agent 认证 | HMAC-SHA256 挑战响应 | ✅ 可见 HMAC，原始 token 不可见 |

> 如果希望信令也不经过第三方，将 Server 部署在自己控制的机器上即可（也是推荐方式）。

---

## 已知限制

- **浏览器快捷键冲突**：`Ctrl+T/W/N/L`、`F5/F11/F12` 等被浏览器拦截，使用原生 App 无此问题
- **多显示器**：目前仅采集主显示器
- **Linux 依赖 X11**：Wayland 桌面需通过 XWayland 兼容层运行
- **Windows 编码**：使用软件 x264，高分辨率时 CPU 占用较高
- **音频**：暂不支持音频传输
