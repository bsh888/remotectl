# RemoteCtl — 项目上下文

## 项目简介

WebRTC 远程桌面系统。macOS/Windows/Linux 被控端（Go + CGO），浏览器或 Flutter App 作控制端。

## 目录结构

```
remotectl/
├── agent/      # 被控端 (Go + CGO)，含 pipeline/ input/ session/ capture/
├── server/     # 信令服务器 (Go)
├── client/     # Web 控制端 (React + TypeScript)
├── app/        # Flutter 跨平台控制端 (iOS/Android/macOS/Windows/Linux)
├── scripts/    # 证书生成脚本
├── certs/      # TLS 证书（本地，不提交）
└── Makefile
```

## Go 模块名

- server: `github.com/bsh888/remotectl/server`
- agent:  `github.com/bsh888/remotectl/agent`

## 构建命令

```bash
make agent-mac      # macOS agent (arm64 + amd64)
make agent-win      # Windows agent (需要 mingw-w64)
make agent-linux    # Linux agent
make server         # 信令服务器
make client         # 前端 (React)
make all            # 全量构建
```

## 发布 Release

源码不开源，只发布各平台二进制包到 GitHub Releases。分三步在不同平台执行：

**第一步：macOS（主构建）**— server 全平台、agent mac+windows、Flutter macOS App

```bash
# 前置依赖（一次性）：brew install gh mingw-w64 && gh auth login
make release VERSION=v1.0.0
# 草稿模式：make release VERSION=v1.0.0 DRAFT=--draft
```

**第二步：Windows**— Flutter Windows App

```powershell
# 前置依赖：gh CLI (winget install GitHub.cli) && gh auth login
powershell -ExecutionPolicy Bypass -File .\scripts\build-app-win.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\upload-release.ps1 v1.0.0
```

**第三步：Linux**— Linux agent + Flutter Linux App

```bash
# 前置依赖：gcc libx264-dev libx11-dev libxext-dev flutter gh && gh auth login
./scripts/upload-release.sh v1.0.0 agent   # 编译并上传 Linux agent
./scripts/build-app-linux.sh               # 构建 Flutter Linux App
./scripts/upload-release.sh v1.0.0 app     # 上传 Flutter Linux App
```

发布制品清单（macOS 本地存于 `deploy/release/<version>/`，不提交到 git）：

| 文件 | 构建平台 |
|------|---------|
| `remotectl-server-linux-amd64-vX.Y.Z.tar.gz` | macOS |
| `remotectl-server-linux-arm64-vX.Y.Z.tar.gz` | macOS |
| `remotectl-agent-linux-amd64-vX.Y.Z.tar.gz` | Linux（无 GUI / headless 服务器用） |
| `remotectl-app-macos-vX.Y.Z.zip` | macOS（含控制端+被控端） |
| `remotectl-app-windows-amd64-vX.Y.Z.zip` | Windows（含控制端+被控端） |
| `remotectl-app-linux-amd64-vX.Y.Z.tar.gz` | Linux（含控制端+被控端） |

## Linux 服务器部署（systemd）

服务以 `ubuntu` 用户运行，通过 `AmbientCapabilities=CAP_NET_BIND_SERVICE` 绑定 443 端口，无需 root。

发布包（`remotectl-server-linux-*-vX.Y.Z.tar.gz`）已内置所有部署脚本，解压后即可使用：

```
remotectl-server-linux-amd64-vX.Y.Z/
├── remotectl-server          # 服务器二进制
├── install.sh                # 安装/升级/卸载脚本
├── remotectl-server.service  # systemd unit
├── server.yaml.example       # 配置模板
└── gen-cert.sh               # 自签名 TLS 证书生成（需要 openssl）
```

```bash
# 1. 解压发布包
tar xzf remotectl-server-linux-amd64-vX.Y.Z.tar.gz
cd remotectl-server-linux-amd64-vX.Y.Z

# 2.（可选）生成自签名 TLS 证书
#    如已有域名证书（Let's Encrypt 等），跳过此步，直接在 server.yaml 中配置路径
bash gen-cert.sh ./certs 1.2.3.4        # 1.2.3.4 替换为服务器公网 IP
#    或同时绑定域名：
bash gen-cert.sh ./certs 1.2.3.4 my.domain.com
#    证书生成到 ./certs/server.crt 和 ./certs/server.key
#    install.sh 会自动将 certs/ 复制到 /opt/remotectl/certs/

# 3. 安装（需 sudo）
sudo bash install.sh

# 4. 修改配置（addr 改为 :443，填入 tokens / TLS 路径 / TURN 等）
sudo vim /opt/remotectl/server.yaml
sudo systemctl restart remotectl-server

# 查看日志
journalctl -u remotectl-server -f

# 升级（重新解压新版本包，再执行一次 install）
sudo bash install.sh

# 卸载（保留 /opt/remotectl/ 中的配置和证书）
sudo bash install.sh remove
```

相关文件：
- `deploy/remotectl-server.service` — systemd unit（User=ubuntu，含安全加固选项）
- `deploy/install.sh` — 安装/升级/卸载脚本，部署到 `/opt/remotectl/`
- `scripts/gen-cert.sh` — openssl 自签名证书（打包进发布包）

## TURN 服务器部署（coturn）

移动端 5G / 运营商 NAT 环境下 STUN 无法直连，需要 TURN 中继。推荐与信令服务器部署在同一台 Ubuntu 机器。

### 安装

```bash
sudo apt update && sudo apt install -y coturn
sudo sed -i 's/#TURNSERVER_ENABLED/TURNSERVER_ENABLED/' /etc/default/coturn
```

### 配置 `/etc/turnserver.conf`

```
listening-port=3478
tls-listening-port=5349

external-ip=<公网IP>
realm=<域名或IP>

# 静态用户名/密码认证
lt-cred-mech
user=remotectl:changeme        # 与 server.yaml turn.user / turn.password 一致

# 复用 remotectl 的 TLS 证书（可选，用于 turns:）
cert=/opt/remotectl/certs/server.crt
pkey=/opt/remotectl/certs/server.key

no-loopback-peers
no-multicast-peers
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.168.0.0-192.168.255.255

log-file=/var/log/coturn/turn.log
simple-log
```

### 开放防火墙端口

```bash
sudo iptables -I INPUT -p udp --dport 3478 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 3478 -j ACCEPT
sudo iptables -I INPUT -p udp --dport 5349 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 5349 -j ACCEPT
sudo iptables -I INPUT -p udp --dport 49152:65535 -j ACCEPT   # relay 端口范围
sudo netfilter-persistent save
```

### 启动

```bash
sudo systemctl enable --now coturn
sudo journalctl -u coturn -f
```

### 配置 server.yaml

```yaml
turn:
  url:      "turn:<公网IP或域名>:3478"
  user:     "remotectl"    # 与 coturn user= 用户名一致
  password: "changeme"     # 与 coturn user= 密码一致
```

## 关键技术细节

### agent — macOS 视频编码 (pipeline_darwin.m)

- VideoToolbox H.264 **High Profile** (`kVTProfileLevel_H264_High_AutoLevel`)
- 熵编码：**CABAC**（`kVTH264EntropyMode_CABAC`），比 Baseline CAVLC 节省 ~15-20%
- 设置了 `ExpectedFrameRate`、`DataRateLimits`（2× 目标码率/秒，防止关键帧突发）
- `AllowFrameReordering = false`，保证低延迟

### agent — 设备 ID 与会话密码

- 设备 ID：若 `--id` 为空，自动生成 9 位随机数（100000000–999999999），持久化到 `~/.config/remotectl/device.id`（Windows：`%APPDATA%\remotectl\device.id`）
- `generateSessionPwd()` 启动时生成 **8 位**随机数字密码，打印 `SESSION_PWD:XXXXXXXX` 到 stdout
- 认证失败时 agent 打印 `AUTH_FAILED:…` 到 stdout 并以 exit(1) 退出
- Windows 进程清理：`ProcessSignal.sigkill`（`WidgetsBindingObserver.didChangeAppLifecycleState(detached)`）

### server — 认证 (main.go)

- viewer 连接：发来的 `password` 字段 vs `agent.sessionPwd`（8 位会话密码），无需服务器密码
- `ConnectPayload`：仅 `device_id` + `password`，已移除 `server_password` 字段
- `tokens` 必须配置，否则启动时 fatal；已移除 `password` / `agent_token` 字段及 dev 模式
- Agent 认证：仅支持 per-device tokens（`server.yaml` → `tokens: {device_id: secret}`）

### agent — WebRTC SDP (main.go)

- SDP profile-level-id 保持 `42e01f`（Baseline），保证与 Flutter WebRTC 协商兼容
- VT 编码器实际输出 High Profile，iOS/浏览器解码器均能解
- 注册了 RTX (PT 103, apt=102) 用于丢包重传
- DataChannels：`input`（reliable+ordered）、`input-move`（unreliable+unordered）、`chat`（reliable+ordered）

### app — Flutter 移动端 (app/lib/screens/remote_screen.dart)

- 键盘输入：隐藏 TextField + zero-width space (`\u200b`) sentinel 方案
- 光标始终钉在末尾（cursor pinning），防止 iOS 光标跑偏
- 修饰键行包含数字键 1-9/0，避免切换数字键盘导致 TextField 失焦
- 双指手势：`onSecondFingerDown` 时重置 `_prevCentroid` 和 `_prevPinchDist`
- 竖屏居中：`ListenableBuilder(listenable: renderer)` 监听 videoWidth/videoHeight 变化

### agent — WebRTC PLI / 首帧黑屏修复 (main.go, pipeline_darwin.m)

- `pc.AddTrack` 返回的 `RTPSender` 必须保存并在 goroutine 中持续 `Read()`，否则 pion 内部 RTCP 缓冲区满导致 PLI 丢失
- 收到任意 RTCP 包 → `pipeline.RequestKeyframe()`（原子标志位），下一帧编码时强制 IDR
- 各平台 pipeline stub（darwin/windows/linux/stub）均已实现 `RequestKeyframe()` 接口

### app — 会话内聊天功能

**DataChannel 协议**（DataChannel 名：`chat`，reliable+ordered）

```
文字消息:  {"type":"text",       "id":"<hex8>","text":"…","ts":1700000000000}
文件开始:  {"type":"file_start", "id":"<hex8>","name":"photo.jpg","size":12345,"mime":"image/jpeg"}
文件分块:  {"type":"file_chunk", "id":"<hex8>","seq":0,"data":"<base64>","last":false}
最后分块:  {"type":"file_chunk", "id":"<hex8>","seq":N,"data":"<base64>","last":true}
ACK:       {"type":"file_ack",   "id":"<hex8>"}   ← 每 8 个分块由 agent 回复一次
chat_open: {"type":"chat_open"}                   ← 控制端打开聊天面板时发送
```

**流量控制**：Flutter 每发送 `_kWindowSize=8` 个分块后等待 `file_ack` 再继续（最大在途数据 ~96 KB）。
Completer 必须在发送窗口**之前**注册，否则 ACK 可能在 `await _sendRaw()` 的 Dart 事件循环让步期间到达而被丢弃。

**控制端 Flutter（`remote_screen.dart` / `remote_screen_desktop.dart`）**
- `ChatServiceBase`（`chat_service.dart`）：抽象基类，`ChatService` 和 `HostedChatService` 均继承它，`ChatPanel` 接受此类型
- `ChatService`：ChangeNotifier，attach/detach DataChannel，持有消息列表
- `RemoteSession` 在 `pc.onDataChannel` 中识别 label `"chat"` → `_chat.attach(channel)`
- `session.chat` 暴露给 UI 层
- 桌面（`remote_screen_desktop.dart`）：水平 pill 工具栏（控制面板 + 聊天按钮），`ChatPanel(width:300)` 固定宽右侧覆盖层
- 移动端（`remote_screen.dart`）：工具栏聊天按钮，`ChatPanel`（无 width）作为 `DraggableScrollableSheet`
- 文件保存：macOS/Windows/Linux → `~/Downloads`，iOS/Android → App Documents
- 语音录制功能已移除（`record`/`audioplayers` 包已从 pubspec.yaml 删除）

**被控端 Flutter（`hosted_screen.dart`）**
- `HostedChatService`（`hosted_chat_service.dart`）：继承 `ChatServiceBase`，通过 stdio IPC 与 agent 通信，不开任何网络端口
- `AgentService` 持有 `HostedChatService chat`，通过 `chat` getter 暴露给 UI
- agent running 时 `chat.isOpen == true`，`hosted_screen.dart` 据此显示聊天按钮
- 发送：`sendText` / `sendFile` 调用 `_onSend` 回调 → `AgentService` 写 `CHAT_SEND:<json>` 到 agent stdin；同时立即将消息插入本地列表（右侧显示）
- 接收：`AgentService._appendLog` 解析 `CHAT_MSG:<json>` → `chat.receive(json)` → 追加到消息列表（左侧显示）

**Agent stdio IPC 协议**（被控端 Flutter ↔ agent 子进程）

```
# agent → Flutter stdout
CHAT_MSG:{"type":"text",       "from":"viewer","id":"…","text":"…","ts":…}
CHAT_MSG:{"type":"file_start", "from":"viewer","id":"…","name":"…","size":…,"mime":"…"}
CHAT_MSG:{"type":"file_saved", "from":"viewer","id":"…","name":"…","path":"/…/Downloads/…"}
CHAT_MSG:{"type":"chat_open"}

# Flutter → agent stdin
CHAT_SEND:{"action":"send_text","text":"…"}
CHAT_SEND:{"action":"send_file","name":"photo.jpg","path":"/…/photo.jpg"}
```

- `send_file`：agent 读本地文件，分 12 KB 块通过 DataChannel 广播给所有 viewer
- `from="agent"` → 被控端自己发的（右侧蓝色）；`from="viewer"` → 控制端发来的（左侧灰色）

**Agent 端**（`agent/main.go`，`agent/notify.go`）
- `startRTC()` 中创建 `chat` DC，`handleChatDCMessage()` 处理收到的消息/文件
- 收到文字/文件 → `showNotification()` 调用系统通知（macOS: osascript，Windows: PowerShell WinForms，Linux: notify-send）
- 收到消息/文件时同时打印 `CHAT_MSG:` 到 stdout，供被控端 Flutter 显示
- `readStdinChatCommands()`：goroutine 扫描 stdin，处理 `CHAT_SEND:` 命令
- 文件保存到 `~/Downloads`，重名自动加时间戳后缀

**权限配置**
- iOS `Info.plist`：`NSCameraUsageDescription`、`NSMicrophoneUsageDescription`、`NSLocalNetworkUsageDescription`、`NSBonjourServices`
- macOS `Info.plist`：`NSMicrophoneUsageDescription`
- macOS entitlements：`com.apple.security.device.audio-input`、`com.apple.security.device.camera`、`com.apple.security.network.client`、`com.apple.security.files.downloads.read-write`（聊天文件接收保存到 Downloads）
- Android `AndroidManifest.xml`：`INTERNET`、`CAMERA`、`RECORD_AUDIO`、`MODIFY_AUDIO_SETTINGS`、`WAKE_LOCK`
- Windows `package.appxmanifest`：`internetClient`、`microphone`、`webcam`

### app — iOS

- `NSLocalNetworkUsageDescription` + `NSBonjourServices` 已加入 Info.plist（WebRTC mDNS ICE）
- **必须 Release 构建**才能独立启动（Debug 构建从桌面点击会崩溃，VSyncClient 空指针）
  - Xcode: Product → Scheme → Edit Scheme → Run → Build Configuration → Release

### client — Web 端 (client/src/components/RemoteScreen.tsx)

- 双指→单指切换时重置 `prevCentroid` 和 `prevPinchDist`，修复手势残留

## 敏感文件（不提交）

| 文件 | 原因 |
|------|------|
| `agent.yaml` | 含真实服务器 IP 和 token |
| `certs/` | TLS 私钥 |
| `bin/` | 编译产物 |

提交的是 `agent.yaml.example`、`server.yaml.example`、`.env.example`。
