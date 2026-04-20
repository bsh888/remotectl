# RemoteCtl — Flutter Client

[中文文档](README.zh.md)

Android / iOS / macOS / Windows / Linux native controller App, built with Flutter + flutter_webrtc.

## Project Setup

```bash
cd app

# Initialize Flutter project (first time only)
flutter create . --org com.example --project-name remotectl

# Enable desktop support (first time, as needed)
flutter config --enable-macos-desktop
flutter config --enable-windows-desktop
flutter config --enable-linux-desktop

# Install dependencies
flutter pub get
```

**Linux extra system dependencies:**
```bash
# Debian/Ubuntu
sudo apt install libpulse-dev libgtk-3-dev liblzma-dev

# Fedora
sudo dnf install pulseaudio-libs-devel gtk3-devel

# Arch
sudo pacman -S libpulse gtk3
```

After initialization, replace Flutter-generated files with the ones in this directory:

| File | Purpose |
|------|---------|
| `android/app/src/main/AndroidManifest.xml` | Network / camera / wake-lock permissions |
| `ios/Runner/Info.plist` | Camera / microphone usage descriptions |
| `macos/Runner/DebugProfile.entitlements` | macOS sandbox: network + camera + microphone |
| `macos/Runner/Release.entitlements` | macOS release permissions |
| `windows/runner/package.appxmanifest` | Windows: internetClient / microphone / webcam |

> Linux requires no extra permission configuration — the default files from `flutter create` work as-is.

## Build & Run

```bash
# Desktop
flutter run -d macos          # macOS
flutter run -d windows        # Windows
flutter run -d linux          # Linux

# Mobile (auto-detected when device is connected)
flutter run

# Release builds
flutter build macos --release
flutter build windows --release
flutter build linux --release
flutter build ios --release           # requires macOS + Xcode

# Android APK (split by ABI for smaller size)
flutter build apk --split-per-abi --release
# Output: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk, etc.

# Android AAB (for Google Play)
flutter build appbundle --release
```

### Android Signing

Release builds must be signed to install on devices.

**1. Generate a keystore (one-time)**

```bash
keytool -genkey -v -keystore ~/remotectl.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias remotectl
```

**2. Create `android/key.properties`** (do not commit to git)

```
storeFile=/Users/<you>/remotectl.jks
storePassword=your_password
keyAlias=remotectl
keyPassword=your_password
```

**3. Reference it in `android/app/build.gradle`**

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

> Back up the keystore file carefully — if lost, you cannot publish updates to an already-released App.

## iOS Device Testing

1. Connect your iPhone with a cable; tap "Trust This Computer" on the device
2. Open the Xcode project: `open ios/Runner.xcworkspace`
3. Under Runner target → Signing & Capabilities, select your developer Team (free Apple ID works)
4. Change the Bundle Identifier to something unique, e.g. `com.yourname.remotectl`
5. Back in terminal: `flutter run`
6. First install: trust the certificate on iPhone under **Settings → General → VPN & Device Management → Trust**

> The iPhone must have an iOS version supported by your installed Xcode SDK. If Xcode reports "iOS X.X is not installed", download it from **Xcode → Settings → Platforms**.

## Localization

The App ships with Simplified Chinese / English / Traditional Chinese. Tap the globe icon in the top-right corner to switch; the preference is persisted via SharedPreferences.

## In-Session Chat

After a session is established, the controller and host can exchange text messages and files:

- **Controller** (`remote_screen.dart` / `remote_screen_desktop.dart`): chat button in toolbar opens `ChatPanel`
  - Mobile: slides up as a `DraggableScrollableSheet`
  - Desktop: fixed 300 px overlay on the right side
- **Host** (`hosted_screen.dart`): chat icon appears while agent is running; communicates with the agent subprocess via stdio IPC
- Files are saved to `~/Downloads`; iOS/Android saves to the App's Documents directory

## Platform Comparison

| Platform | Controller UI | Keyboard capture | Right-click |
|----------|--------------|-----------------|-------------|
| Browser | Web | Limited (F5/Ctrl+T etc. intercepted) | Supported |
| macOS App | Desktop | **Full capture** | Supported |
| Windows App | Desktop | **Full capture** | Supported |
| Linux App | Desktop | **Full capture** | Supported |
| Android / iOS | Mobile touch | Via soft keyboard | Long-press 600 ms |

## Desktop Usage

### Mouse

| Action | Effect |
|--------|--------|
| Move | Moves remote cursor (local cursor auto-hidden) |
| Left single/double click | Remote left single/double click |
| Right click | Remote right-click menu |
| Scroll wheel | Remote scroll |

### Keyboard

All key events are forwarded directly, including:
- F1–F12, PrintScreen, Pause, and other function keys
- Shortcuts intercepted by browsers (Ctrl+C / Ctrl+W / F5, etc.)
- IME composition input

### Ctrl ⇄ Cmd Toggle (toolbar)

| Scenario | Default |
|----------|---------|
| Mac controller → Mac remote | Off (Cmd sends Cmd) |
| Mac controller → Windows / Linux remote | **On** (Cmd auto-converted to Ctrl) |
| Windows / Linux controller → Mac remote | **On** (Ctrl auto-converted to Cmd) |
| Windows / Linux controller → Windows / Linux remote | Off |

### Mobile Gestures

| Gesture | Action |
|---------|--------|
| Single tap | Left mouse click |
| Long press (600 ms) | Right mouse click (haptic feedback) |
| Single finger drag | Mouse move |
| Two-finger pinch/spread | Zoom view |
| Two-finger drag | Scroll wheel |
| Keyboard button in toolbar | Open system keyboard (supports IME / CJK input) |
| Paste button in toolbar | Paste phone clipboard content to remote |

### Modifier Key Toolbar

When the keyboard is open, a modifier row appears at the top for keyboard shortcuts:

| Key | Notes |
|-----|-------|
| `Ctrl` `Shift` `Alt` `Win` `Cmd` | Tap to activate (highlighted); tap again to deactivate |
| `1`–`9` `0` | Send digit keys directly (no keyboard layout switch needed) |
| `Tab` `Esc` `←` `→` `↑` `↓` | Common editing / navigation keys |
| `F1`–`F12` | Function keys |

> Example: tap `Ctrl` → tap `B` → tap `1` to send the Ctrl+B+1 shortcut (tmux window switching)

## iOS Notes

### Use Release Build

The default install via Xcode is a Debug build; launching the App from the home screen after closing it will crash.
Switch to Release mode:

**Xcode:** Product → Scheme → Edit Scheme → Run → Build Configuration → **Release**

Or via command line:
```bash
flutter build ios --release
# Then install to device with Cmd+R in Xcode
```

### First-Launch Permissions

- **Local Network Access**: required for WebRTC ICE; tap "Allow" when prompted
- **Camera / Microphone**: requested by flutter_webrtc on init; the App does not actually use the local camera or microphone

## App Icon

Icon source: `scripts/icon-source.svg` (SIGNAL DARK style — dark background + orange accent)

After editing the SVG, regenerate all platform icons (requires `rsvg-convert` + `magick`):

```bash
# macOS: install dependencies (one-time)
brew install librsvg imagemagick

bash scripts/gen-icons.sh
```

Covers macOS / iOS / Android / Windows at all required sizes.
