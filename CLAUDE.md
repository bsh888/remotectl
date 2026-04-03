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

### agent — WebRTC SDP (main.go)

- SDP profile-level-id 保持 `42e01f`（Baseline），保证与 Flutter WebRTC 协商兼容
- VT 编码器实际输出 High Profile，iOS/浏览器解码器均能解
- 注册了 RTX (PT 103, apt=102) 用于丢包重传

### app — Flutter 移动端 (app/lib/screens/remote_screen.dart)

- 键盘输入：隐藏 TextField + zero-width space (`\u200b`) sentinel 方案
- 光标始终钉在末尾（cursor pinning），防止 iOS 光标跑偏
- 修饰键行包含数字键 1-9/0，避免切换数字键盘导致 TextField 失焦
- 双指手势：`onSecondFingerDown` 时重置 `_prevCentroid` 和 `_prevPinchDist`
- 竖屏居中：`ListenableBuilder(listenable: renderer)` 监听 videoWidth/videoHeight 变化

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
