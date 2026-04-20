# RemoteCtl

[![Stars](https://img.shields.io/github/stars/bsh888/remotectl?style=flat-square)](https://github.com/bsh888/remotectl)
&nbsp;[中文文档](README.zh.md)

Cross-platform remote desktop tool. macOS / Windows / Linux as host, browser or native App as controller.

## Features

- **H.264 hardware encoding** — VideoToolbox on macOS, x264 on Windows/Linux
- **WebRTC transport** — peer-to-peer video stream; the server never touches video data
- **TURN relay** — automatic relay for mobile (4G/5G) / symmetric NAT environments
- **E2EE input encryption** — ECDH P-256 + AES-256-GCM end-to-end encrypted input events
- **Low-latency mouse** — local cursor overlay for instant feedback; input over P2P DataChannel
- **Cross-platform clipboard** — paste text (including CJK / Emoji) from controller to remote
- **In-session chat** — real-time text messages and file transfer between controller and host
- **Session password auth** — random 8-digit password generated on each start, simple and secure
- **All-in-one desktop App** — single App for macOS/Windows/Linux with both "Remote Control" and "Share This PC" modes
- **systemd deployment** — release package includes `install.sh` for one-command service setup, no root required for port 443

## vs. Commercial Tools

RemoteCtl shares the same WebRTC technology stack as Sunflower, TeamViewer, etc. The key differences are **control depth** and **data sovereignty**:

| Feature | RemoteCtl | Sunflower |
|---------|:---------:|:---------:|
| Open source | ✓ | — |
| Self-hosted (no third-party server) | ✓ | — |
| Browser control (no client install) | ✓ | Partial |
| Fully custom bitrate / resolution / FPS | ✓ | Partial |
| Full mobile keyboard (modifiers + number row + F1–F12) | ✓ | Partial |
| In-session chat + P2P file transfer | ✓ | — |
| Completely free | ✓ | Partial |

- **Self-hosted**: deploy one public Linux server; video travels over WebRTC P2P and the server only forwards signaling — no audio/video ever passes through it.
- **Quality tuning**: `bitrate`, `scale` (resolution), and `fps` are all independently adjustable. Max out `scale:1.0 bitrate:8M` on LAN; drop to `scale:0.5 bitrate:1M` on mobile 4G.
- **Mobile keyboard**: modifier keys (Ctrl / Shift / Alt / Win / ⌘) can be pressed standalone; number row, arrow keys, and F1–F12 are always visible in the toolbar — enabling combos like Ctrl+B+1 for tmux.
- **In-session chat**: controller and host communicate via WebRTC DataChannel directly (no server), with system notifications on the host side — great for sharing links, screenshots, and config files.

> Sunflower data sourced from public materials; refer to its latest official release for accuracy.

## Download

Go to the [Releases](https://github.com/bsh888/remotectl/releases) page to download the package for your platform.

| File | Description |
|------|-------------|
| `remotectl-app-macos-vX.Y.Z.zip` | macOS App (controller + host in one) |
| `remotectl-app-windows-amd64-vX.Y.Z.zip` | Windows App (controller + host in one) |
| `remotectl-app-linux-amd64-vX.Y.Z.tar.gz` | Linux App (controller + host in one) |
| `remotectl-agent-linux-amd64-vX.Y.Z.tar.gz` | Linux headless agent (no GUI, for servers) |
| `remotectl-server-linux-amd64-vX.Y.Z.tar.gz` | Signaling server — Linux x86_64 (includes systemd scripts) |
| `remotectl-server-linux-arm64-vX.Y.Z.tar.gz` | Signaling server — Linux ARM64 (includes systemd scripts) |

## Quick Start

### Desktop App (controller + host)

Download the `remotectl-app-*` package for your platform, unzip, and run. The App has two modes:

- **Remote Control** — enter a Device ID and session password to connect and control a remote machine
- **Share This PC** — share your screen with a controller

### Linux Headless Agent

For Linux servers without a desktop environment, download `remotectl-agent-linux-amd64-*`:

```bash
tar xzf remotectl-agent-linux-amd64-vX.Y.Z.tar.gz
cd remotectl-agent-linux-amd64-vX.Y.Z
cp agent.yaml.example agent.yaml
vim agent.yaml   # fill in server address and token
./remotectl-agent --config agent.yaml
```

### Signaling Server (self-hosted)

Download the `remotectl-server-linux-*` package and deploy as a systemd service:

```bash
tar xzf remotectl-server-linux-amd64-vX.Y.Z.tar.gz
cd remotectl-server-linux-amd64-vX.Y.Z

# (optional) generate a self-signed TLS cert; skip if you already have one
bash gen-cert.sh ./certs 1.2.3.4          # replace with your server's public IP
# bash gen-cert.sh ./certs 1.2.3.4 my.domain.com   # also bind a domain name

sudo bash install.sh    # installs to /opt/remotectl, adds iptables rule for port 443
sudo vim /opt/remotectl/server.yaml   # fill in tokens, TLS paths, TURN config
sudo systemctl restart remotectl-server
```

### TURN Relay (required for mobile networks)

Needed for 4G/5G and carrier-grade NAT. Install coturn on the same server:

```bash
sudo apt install -y coturn
sudo sed -i 's/#TURNSERVER_ENABLED/TURNSERVER_ENABLED/' /etc/default/coturn
```

Key settings in `/etc/turnserver.conf`:

```
listening-port=3478
external-ip=<server public IP>
realm=<domain or IP>
lt-cred-mech
user=remotectl:changeme
no-multicast-peers
```

```bash
sudo systemctl enable --now coturn
```

Add TURN config to `server.yaml`:

```yaml
turn:
  url:      "turn:1.2.3.4:3478"
  user:     "remotectl"
  password: "changeme"
```

**OS firewall (iptables):**

```bash
sudo iptables -I INPUT -p udp --dport 3478 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 3478 -j ACCEPT
sudo iptables -I INPUT -p udp --dport 49152:65535 -j ACCEPT
sudo netfilter-persistent save
```

**OCI Security List (console):** Networking → Virtual Cloud Networks → your VCN → Security Lists → Default Security List → Add Ingress Rules:

| Source CIDR | Protocol | Destination Port |
|-------------|----------|-----------------|
| `0.0.0.0/0` | UDP | `3478` |
| `0.0.0.0/0` | TCP | `3478` |
| `0.0.0.0/0` | UDP | `49152-65535` |

> OCI has two firewall layers (Security List + instance iptables) — both must allow the ports.

## Platform Support

| Platform | Controller | Host |
|----------|-----------|------|
| macOS | ✅ App | ✅ built into App |
| Windows | ✅ App | ✅ built into App |
| Linux | ✅ App | ✅ App / standalone agent |
| iOS | ✅ App | ❌ |
| Android | ✅ App | ❌ |
| Browser | ✅ Web | ❌ |
