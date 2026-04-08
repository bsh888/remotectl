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

### agent — 会话密码与认证

- `generateSessionPwd()` 启动时生成 6 位随机数字密码
- 打印 `SESSION_PWD:XXXXXX` 到 stdout，Flutter App 解析后在共享页面显示
- viewer 连接时必须提供会话密码（`h.password` 字段）；server 校验后才放行
- 认证失败时 agent 打印 `AUTH_FAILED:…` 到 stdout（Flutter App 解析后显示错误）并以 exit(1) 退出
- Windows 进程清理：`ProcessSignal.sigkill`（`WidgetsBindingObserver.didChangeAppLifecycleState(detached)`）

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

### app — 会话内聊天功能

**DataChannel 协议**（DataChannel 名：`chat`，reliable+ordered）

```
文字消息:  {"type":"text",       "id":"<hex8>","text":"…","ts":1700000000000}
文件开始:  {"type":"file_start", "id":"<hex8>","name":"photo.jpg","size":12345,"mime":"image/jpeg"}
文件分块:  {"type":"file_chunk", "id":"<hex8>","seq":0,"data":"<base64>","last":false}
最后分块:  {"type":"file_chunk", "id":"<hex8>","seq":N,"data":"<base64>","last":true}
```

**Flutter 端**
- `ChatService`（`app/lib/services/chat_service.dart`）：ChangeNotifier，attach/detach DC，持有消息列表
- `RemoteSession` 在 `pc.onDataChannel` 中识别 label `"chat"` → `_chat.attach(channel)`
- `session.chat` 暴露给 UI 层
- 桌面（`remote_screen_desktop.dart`）：控制面板新增 💬 按钮，`ChatPanel(width:300)` 固定宽右侧覆盖层
- 移动端（`remote_screen.dart`）：工具栏聊天按钮，`ChatPanel`（无 width）作为 `DraggableScrollableSheet`
- 文件保存：桌面 → `~/Downloads`，移动 → App Documents
- 语音录制：`record` 包（AAC 16kHz），播放：`audioplayers` 包

**Agent 端**（`agent/main.go`，`agent/notify.go`）
- `startRTC()` 中创建 `chat` DC，`handleChatDCMessage()` 处理收到的消息/文件
- 收到文字/文件/语音 → `showNotification()` 调用系统通知（macOS: osascript，Windows: PowerShell WinForms，Linux: notify-send）
- 文件保存到 `~/Downloads`，重名自动加时间戳后缀

**iOS/macOS 权限**
- iOS `Info.plist`：已有 `NSMicrophoneUsageDescription`
- macOS `Info.plist`：已加 `NSMicrophoneUsageDescription`
- macOS entitlements：已有 `com.apple.security.device.audio-input`
- Android：已有 `RECORD_AUDIO` 权限

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
