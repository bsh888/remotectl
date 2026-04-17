# RemoteCtl

跨平台远程桌面工具，支持 macOS / Windows / Linux 被控端，浏览器或原生 App 作为控制端。

## 功能特性

- **H.264 硬件编码**：macOS 使用 VideoToolbox，Windows/Linux 使用 x264
- **WebRTC 传输**：视频流点对点直连，服务器不经手视频数据
- **TURN 中继**：自动为移动网络（4G/5G）/ 对称型 NAT 提供中继
- **E2EE 输入加密**：ECDH P-256 + AES-256-GCM 端对端加密输入事件
- **低延迟鼠标**：本地光标叠加层即时反馈，输入走 P2P DataChannel
- **跨平台剪贴板**：控制端粘贴文本到远程，支持中文 / Emoji
- **会话内聊天**：控制端与被控端实时文字消息 + 文件互传
- **会话密码认证**：每次启动随机生成 8 位数字密码，简单安全
- **一体化桌面 App**：macOS/Windows/Linux 原生 App 同时内置"远程控制"和"共享本机"两种模式
- **systemd 部署**：发布包内置 install.sh，一键部署为系统服务，无需 root 绑定 443 端口

## 下载

前往 [Releases](https://github.com/bsh888/remotectl/releases) 页面下载对应平台的安装包。

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
# bash gen-cert.sh ./certs 1.2.3.4 my.domain.com   # 同时绑定域名

sudo bash install.sh    # 安装到 /opt/remotectl，自动添加 iptables 443 规则
sudo vim /opt/remotectl/server.yaml   # 填入 tokens、TLS 证书路径、TURN 配置
sudo systemctl restart remotectl-server
```

### TURN 中继（移动网络必配）

手机 4G/5G、运营商 NAT 环境下需要 TURN 中继，在同一台服务器上安装 coturn：

```bash
sudo apt install -y coturn
sudo sed -i 's/#TURNSERVER_ENABLED/TURNSERVER_ENABLED/' /etc/default/coturn
```

`/etc/turnserver.conf` 关键配置：

```
listening-port=3478
external-ip=<服务器公网IP>
realm=<域名或IP>
lt-cred-mech
user=remotectl:changeme
no-multicast-peers
```

```bash
sudo systemctl enable --now coturn
```

在 `server.yaml` 填入 TURN 配置：

```yaml
turn:
  url:      "turn:1.2.3.4:3478"
  user:     "remotectl"
  password: "changeme"
```

**OS 防火墙（iptables）：**

```bash
sudo iptables -I INPUT -p udp --dport 3478 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 3478 -j ACCEPT
sudo iptables -I INPUT -p udp --dport 49152:65535 -j ACCEPT
sudo netfilter-persistent save
```

**OCI 安全列表（控制台）：** 网络 → 虚拟云网络 → 你的 VCN → 安全列表 → 默认安全列表 → 添加入站规则：

| 源 CIDR | 协议 | 目标端口范围 |
|---------|------|------------|
| `0.0.0.0/0` | UDP | `3478` |
| `0.0.0.0/0` | TCP | `3478` |
| `0.0.0.0/0` | UDP | `49152-65535` |

> OCI 有两层防火墙（安全列表 + 实例 iptables），两层都必须放行，缺一不可。

## 平台支持

| 平台 | 控制端 | 被控端 |
|------|--------|--------|
| macOS | ✅ App | ✅ App 内置 |
| Windows | ✅ App | ✅ App 内置 |
| Linux | ✅ App | ✅ App 内置 / 独立 agent |
| iOS | ✅ App | ❌ |
| Android | ✅ App | ❌ |
| 浏览器 | ✅ Web | ❌ |
