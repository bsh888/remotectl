# RemoteCtl — Flutter 客户端

[English](README.md)

Android / iOS / macOS / Windows / Linux 原生控制端 App，使用 Flutter + flutter_webrtc 构建。

## 初始化项目

```bash
cd app

# 初始化 Flutter 项目（首次）
flutter create . --org com.example --project-name remotectl

# 启用桌面支持（首次，按需）
flutter config --enable-macos-desktop
flutter config --enable-windows-desktop
flutter config --enable-linux-desktop

# 安装依赖
flutter pub get
```

**Linux 额外系统依赖：**
```bash
# Debian/Ubuntu
sudo apt install libpulse-dev libgtk-3-dev liblzma-dev

# Fedora
sudo dnf install pulseaudio-libs-devel gtk3-devel

# Arch
sudo pacman -S libpulse gtk3
```

初始化完成后，用本目录下的文件替换 Flutter 生成的同名文件：

| 文件 | 说明 |
|------|------|
| `android/app/src/main/AndroidManifest.xml` | 网络/摄像头/唤醒锁权限 |
| `ios/Runner/Info.plist` | 摄像头/麦克风使用说明 |
| `macos/Runner/DebugProfile.entitlements` | macOS 沙箱：网络+摄像头+麦克风 |
| `macos/Runner/Release.entitlements` | macOS 发布权限 |
| `windows/runner/package.appxmanifest` | Windows：internetClient/microphone/webcam |

> Linux 无需额外权限配置，`flutter create` 生成的默认文件即可。

## 构建运行

```bash
# 桌面
flutter run -d macos          # macOS
flutter run -d windows        # Windows
flutter run -d linux          # Linux

# 手机（连接后自动检测）
flutter run

# 发布构建
flutter build macos --release
flutter build windows --release
flutter build linux --release
flutter build ios --release           # 需要 macOS + Xcode

# Android APK（按 ABI 拆分，包体更小）
flutter build apk --split-per-abi --release
# 产物：build/app/outputs/flutter-apk/app-arm64-v8a-release.apk 等

# Android AAB（上架 Google Play 用）
flutter build appbundle --release
```

### Android 签名

Release 包需要签名，否则无法安装到设备。

**1. 生成 keystore（一次性）**

```bash
keytool -genkey -v -keystore ~/remotectl.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias remotectl
```

**2. 创建 `android/key.properties`**（不提交到 git）

```
storeFile=/Users/<you>/remotectl.jks
storePassword=your_password
keyAlias=remotectl
keyPassword=your_password
```

**3. 在 `android/app/build.gradle` 中引用**

```groovy
def keystoreProperties = new Properties()
keystoreProperties.load(new FileInputStream(rootProject.file('key.properties')))

android {
    signingConfigs {
        release {
            storeFile     file(keystoreProperties['storeFile'])
            storePassword keystoreProperties['storePassword']
            keyAlias      keystoreProperties['keyAlias']
            keyPassword   keystoreProperties['keyPassword']
        }
    }
    buildTypes {
        release { signingConfig signingConfigs.release }
    }
}
```

> keystore 文件务必妥善备份，丢失后无法为已发布的 App 发布更新。

## iOS 真机调试

1. 用数据线连接 iPhone，iPhone 上点"信任此电脑"
2. 打开 Xcode 项目：`open ios/Runner.xcworkspace`
3. 在 Runner target → Signing & Capabilities 选择开发者 Team（免费 Apple ID 即可）
4. 将 Bundle Identifier 改为唯一值，例如 `com.yourname.remotectl`
5. 回到终端：`flutter run`
6. 首次安装需在 iPhone 上信任证书：**设置 → 通用 → VPN与设备管理 → 信任**

> iPhone 需安装与 Xcode 匹配的 iOS 版本 SDK。如果 Xcode 报"iOS X.X is not installed"，到 **Xcode → Settings → Platforms** 下载对应版本。

## 多语言

App 内置简体中文 / English / 繁體中文，点击右上角地球图标切换，偏好通过 SharedPreferences 持久化。

## 会话内聊天

连接建立后，控制端和被控端可互发文字消息和文件：

- **控制端**（`remote_screen.dart` / `remote_screen_desktop.dart`）：工具栏/底栏聊天按钮打开 `ChatPanel`
  - 移动端：`DraggableScrollableSheet` 底部弹出
  - 桌面端：右侧固定宽 300px 覆盖层
- **被控端**（`hosted_screen.dart`）：agent 运行中聊天图标出现，通过 stdio IPC 与 agent 子进程通信
- 文件保存到 `~/Downloads`；iOS/Android 保存到 App Documents 目录

## 平台对比

| 平台 | 控制端界面 | 键盘捕获 | 鼠标右键 |
|------|-----------|---------|---------|
| 浏览器 | Web | 受限（F5/Ctrl+T 等被拦截） | 支持 |
| macOS App | 桌面 | **完整捕获** | 支持 |
| Windows App | 桌面 | **完整捕获** | 支持 |
| Linux App | 桌面 | **完整捕获** | 支持 |
| Android / iOS | 移动触屏 | 通过软键盘 | 长按 600ms |

## 桌面端操作说明

### 鼠标

| 操作 | 效果 |
|------|------|
| 移动 | 移动远程鼠标（本地光标自动隐藏） |
| 左键单/双击 | 远程左键单/双击 |
| 右键单击 | 远程右键菜单 |
| 滚轮 | 远程滚轮 |

### 键盘

全部键盘事件直接转发，包括：
- F1–F12、PrintScreen、Pause 等功能键
- Ctrl+C / Ctrl+W / F5 等被浏览器拦截的快捷键
- 输入法（IME）组合输入

### Ctrl ⇄ Cmd 开关（工具栏）

| 场景 | 默认行为 |
|------|---------|
| Mac 客户端 → Mac 远程 | 关闭（Cmd 发 Cmd） |
| Mac 客户端 → Windows / Linux 远程 | **开启**（Cmd 自动转 Ctrl） |
| Windows / Linux 客户端 → Mac 远程 | **开启**（Ctrl 自动转 Cmd） |
| Windows / Linux 客户端 → Windows / Linux 远程 | 关闭 |

### 手机端手势

| 手势 | 操作 |
|------|------|
| 单指点击 | 鼠标左键单击 |
| 单指长按（600ms） | 鼠标右键单击（震动反馈） |
| 单指拖动 | 鼠标移动 |
| 双指捏合/张开 | 缩放视图 |
| 双指拖动 | 滚轮滚动 |
| 工具栏键盘按钮 | 弹出系统键盘（支持 IME 中文输入） |
| 工具栏粘贴按钮 | 将手机剪贴板内容粘贴到远程 |

### 修饰键工具栏

键盘弹出后顶部显示修饰键行，支持组合快捷键：

| 按键 | 说明 |
|------|------|
| `Ctrl` `Shift` `Alt` `Win` `Cmd` | 点击激活（高亮），再次点击取消 |
| `1`–`9` `0` | 直接发送数字键（无需切换键盘布局） |
| `Tab` `Esc` `←` `→` `↑` `↓` | 常用编辑/导航键 |
| `F1`–`F12` | 功能键 |

> 组合示例：点击 `Ctrl` → 点击 `B` → 点击 `1`，发送 Ctrl+B+1 快捷键

## iOS 注意事项

### 使用 Release 构建

通过 Xcode 安装的默认是 Debug 构建，关闭 App 后再从桌面点击图标会崩溃。
必须改用 Release 模式：

**Xcode：** Product → Scheme → Edit Scheme → Run → Build Configuration → **Release**

或命令行：
```bash
flutter build ios --release
# 然后在 Xcode 中 Cmd+R 安装到真机
```

### 首次启动权限

- **本地网络访问**：WebRTC ICE 打洞需要，首次弹窗时选"允许"
- **摄像头 / 麦克风**：flutter_webrtc 初始化时请求，实际不会使用本机摄像头和麦克风

## App 图标

图标源文件：`scripts/icon-source.svg`（SIGNAL DARK 风格，深色背景 + 橙色 accent）

修改图标后运行以下命令重新生成所有平台图标（需要 `rsvg-convert` + `magick`）：

```bash
# macOS 安装依赖（一次性）
brew install librsvg imagemagick

bash scripts/gen-icons.sh
```

覆盖 macOS / iOS / Android / Windows 全平台尺寸。
