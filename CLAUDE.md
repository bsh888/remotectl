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

### server — 两层认证 (main.go)

- Layer 1：viewer 发来的 `server_password` 字段 vs `h.password`（server.yaml `password`，**必填**），先于设备查找进行校验
- Layer 2：viewer 发来的 `password` 字段 vs `agent.sessionPwd`（8 位会话密码）
- `ConnectPayload` 新增 `ServerPassword string json:"server_password,omitempty"`
- 两层均为强制校验，无 dev 模式：`password` 和 `tokens` 均必须配置，否则启动时 fatal
- Agent 认证：仅支持 per-device tokens（`server.yaml` → `tokens: {device_id: secret}`），已移除 `agent_token` 全局 token 和 dev 模式（无 token 直接拒绝）

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
chat_open: {"type":"chat_open"}                   ← Flutter 打开聊天面板时发送，agent 自动打开浏览器
```

**流量控制**：Flutter 每发送 `_kWindowSize=8` 个分块后等待 `file_ack` 再继续（最大在途数据 ~96 KB）。
Completer 必须在发送窗口**之前**注册，否则 ACK 可能在 `await _sendRaw()` 的 Dart 事件循环让步期间到达而被丢弃。

**Flutter 端**
- `ChatService`（`app/lib/services/chat_service.dart`）：ChangeNotifier，attach/detach DC，持有消息列表
- `RemoteSession` 在 `pc.onDataChannel` 中识别 label `"chat"` → `_chat.attach(channel)`
- `session.chat` 暴露给 UI 层
- 桌面（`remote_screen_desktop.dart`）：水平 pill 工具栏（控制面板 + 聊天按钮），`ChatPanel(width:300)` 固定宽右侧覆盖层
- 移动端（`remote_screen.dart`）：工具栏聊天按钮，`ChatPanel`（无 width）作为 `DraggableScrollableSheet`
- 文件保存：macOS/Windows/Linux → `~/Downloads`，iOS/Android → App Documents
- 语音录制功能已移除（`record`/`audioplayers` 包已从 pubspec.yaml 删除）

**Agent 端**（`agent/main.go`，`agent/chatserver.go`，`agent/notify.go`）
- `startRTC()` 中创建 `chat` DC，`handleChatDCMessage()` 处理收到的消息/文件
- 收到文字/文件 → `showNotification()` 调用系统通知（macOS: osascript，Windows: PowerShell WinForms，Linux: notify-send）
- 文件保存到 `~/Downloads`，重名自动加时间戳后缀
- `chatserver.go`：WebSocket 服务（浏览器聊天页面），含历史消息环形缓冲（最近 50 条），新连接自动回放
- 浏览器聊天页面（`chat.html`）支持发送文件，base64 编码后通过 WebSocket 传给 agent 再中转到 Flutter

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
