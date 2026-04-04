.PHONY: all server server-mac server-win server-linux \
        agent-mac agent-win agent-linux \
        app-mac app-win app-linux \
        client dev-server dev-client tidy cert clean

# ── 完整构建 ──────────────────────────────────
# agent-* 需要对应平台的 CGO 工具链，单独调用：
#   make agent-mac / agent-win / agent-linux
all: tidy client server server-all agent-mac

# ── 依赖整理 ──────────────────────────────────
tidy:
	cd server && go mod tidy
	cd agent  && go mod tidy
	cd client && npm install

# ── 前端 (输出到 server/static/) ──────────────
client:
	cd client && npm run build
	@echo "✓ client built → server/static/"

# ── 服务端 ────────────────────────────────────
# 当前平台（用于 Docker 或本机运行）
server: | bin
	cd server && go build -ldflags="-s -w" -o ../bin/remotectl-server .
	@echo "✓ server → bin/remotectl-server"

# 三平台全量构建（纯 Go，无需 CGO，任意平台均可交叉编译）
server-all: server-mac server-win server-linux

server-mac: | bin
	cd server && GOOS=darwin  GOARCH=arm64 CGO_ENABLED=0 \
		go build -ldflags="-s -w" -o ../bin/remotectl-server-mac-arm64 .
	cd server && GOOS=darwin  GOARCH=amd64 CGO_ENABLED=0 \
		go build -ldflags="-s -w" -o ../bin/remotectl-server-mac-amd64 .
	@echo "✓ server → bin/remotectl-server-mac-*"

server-win: | bin
	cd server && GOOS=windows GOARCH=amd64 CGO_ENABLED=0 \
		go build -ldflags="-s -w" -o ../bin/remotectl-server-windows-amd64.exe .
	@echo "✓ server → bin/remotectl-server-windows-amd64.exe"

server-linux: | bin
	cd server && GOOS=linux   GOARCH=amd64 CGO_ENABLED=0 \
		go build -ldflags="-s -w" -o ../bin/remotectl-server-linux-amd64 .
	cd server && GOOS=linux   GOARCH=arm64 CGO_ENABLED=0 \
		go build -ldflags="-s -w" -o ../bin/remotectl-server-linux-arm64 .
	@echo "✓ server → bin/remotectl-server-linux-*"

# ── Agent (被控端) ────────────────────────────
# macOS: CGO_ENABLED=1 required for robotgo + screenshot
agent-mac: | bin
	cd agent && CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 \
		go build -ldflags="-s -w" -o ../bin/remotectl-agent-mac-arm64 .
	cd agent && CGO_ENABLED=1 GOOS=darwin GOARCH=amd64 \
		go build -ldflags="-s -w" -o ../bin/remotectl-agent-mac-amd64 .
	@echo "✓ agent → bin/remotectl-agent-mac-*"

# Windows cross-compile requires mingw-w64:
#   brew install mingw-w64  (macOS host)
agent-win: | bin
	cd agent && CGO_ENABLED=1 GOOS=windows GOARCH=amd64 \
		CC=x86_64-w64-mingw32-gcc \
		go build -ldflags="-s -w -H windowsgui" \
		-o ../bin/remotectl-agent-windows-amd64.exe .
	@echo "✓ agent → bin/remotectl-agent-windows-amd64.exe"

# Linux cross-compile requires a Linux CGO toolchain.
# On macOS host: brew install FiloSottile/musl-cross/musl-cross
#   (provides x86_64-linux-musl-gcc, links statically — no glibc dep)
# On Linux host: apt install gcc libx264-dev libx11-dev libxext-dev
agent-linux: | bin
	cd agent && CGO_ENABLED=1 GOOS=linux GOARCH=amd64 \
		CC=x86_64-linux-musl-gcc \
		CGO_LDFLAGS="-lx264 -lX11 -lXext -static" \
		go build -ldflags="-s -w" \
		-o ../bin/remotectl-agent-linux-amd64 .
	@echo "✓ agent → bin/remotectl-agent-linux-amd64"

bin:
	mkdir -p bin

# ── Flutter 桌面应用打包（agent 注入）─────────────────────────
# 构建 agent + Flutter app，并将 agent 二进制注入到 Flutter 发布包中。
# agent 与 Flutter 可执行文件同目录，运行时自动发现。

# macOS: 生成 universal binary (arm64 + amd64)，注入 .app/Contents/MacOS/
app-mac: | bin
	cd agent && CGO_ENABLED=1 GOOS=darwin GOARCH=arm64 \
		go build -ldflags="-s -w" -o ../bin/remotectl-agent-mac-arm64 .
	cd agent && CGO_ENABLED=1 GOOS=darwin GOARCH=amd64 \
		go build -ldflags="-s -w" -o ../bin/remotectl-agent-mac-amd64 .
	lipo -create \
		bin/remotectl-agent-mac-arm64 \
		bin/remotectl-agent-mac-amd64 \
		-output bin/remotectl-agent-mac
	cd app && flutter build macos --release
	cp bin/remotectl-agent-mac \
		app/build/macos/Build/Products/Release/remotectl.app/Contents/MacOS/remotectl-agent
	chmod +x \
		app/build/macos/Build/Products/Release/remotectl.app/Contents/MacOS/remotectl-agent
	@echo "✓ remotectl.app → app/build/macos/Build/Products/Release/remotectl.app"

# Windows: agent.exe 与 Flutter exe 同目录
# 在 Windows 上运行时将 CC= 改为 gcc（MSYS2）；
# 在 macOS 上交叉编译时保持 mingw-w64 toolchain。
app-win: | bin
	cd agent && CGO_ENABLED=1 GOOS=windows GOARCH=amd64 \
		CC=x86_64-w64-mingw32-gcc \
		go build -ldflags="-s -w -H windowsgui" \
		-o ../bin/remotectl-agent-windows-amd64.exe .
	cd app && flutter build windows --release
	cp bin/remotectl-agent-windows-amd64.exe \
		app/build/windows/x64/runner/Release/remotectl-agent.exe
	@echo "✓ Windows app → app/build/windows/x64/runner/Release/"

# Linux: agent 与 Flutter 可执行文件同目录（bundle/）
app-linux: | bin
	cd agent && CGO_ENABLED=1 GOOS=linux GOARCH=amd64 \
		CC=x86_64-linux-musl-gcc \
		CGO_LDFLAGS="-lx264 -lX11 -lXext -static" \
		go build -ldflags="-s -w" \
		-o ../bin/remotectl-agent-linux-amd64 .
	cd app && flutter build linux --release
	cp bin/remotectl-agent-linux-amd64 \
		app/build/linux/x64/release/bundle/remotectl-agent
	chmod +x app/build/linux/x64/release/bundle/remotectl-agent
	@echo "✓ Linux app → app/build/linux/x64/release/bundle/"

# ── TLS 证书 ─────────────────────────────────
# 用 Go 原生 crypto/x509 生成，100% 兼容 Go TLS 合规检查
#
# 用法:
#   make cert                         # 仅 localhost + 127.0.0.1
#   make cert IP=10.200.10.1          # 加局域网 IP
#   make cert IP=1.2.3.4,10.0.0.1    # 多个 IP
#   make cert IP=1.2.3.4 DNS=my.host # IP + 域名
cert:
	go run scripts/gen-cert.go \
		-out  ./certs \
		-ip   "127.0.0.1$(if $(IP),$(comma)$(IP),)" \
		-dns  "localhost$(if $(DNS),$(comma)$(DNS),)"

comma := ,

# macOS: 将证书加入系统信任（浏览器和 agent 均无需 --insecure）
trust-cert:
	sudo security add-trusted-cert \
		-d -r trustRoot \
		-k /Library/Keychains/System.keychain \
		./certs/server.crt
	@echo "Certificate trusted. Restart your browser."

untrust-cert:
	sudo security delete-certificate -c "remotectl" \
		/Library/Keychains/System.keychain 2>/dev/null || true
	@echo "Certificate removed from trust store."

# ── 开发模式 ──────────────────────────────────
dev-server:
	cd server && go run . \
		--addr :8080 \
		--password remotectl \
		--static ./static

dev-server-tls:
	cd server && go run . \
		--addr :8443 \
		--password remotectl \
		--static ./static \
		--tls-cert ../certs/server.crt \
		--tls-key  ../certs/server.key

dev-client:
	cd client && npm run dev

# ── Docker ────────────────────────────────────
docker-build:
	docker compose build

docker-up:
	docker compose up -d

# ── 清理 ──────────────────────────────────────
clean:
	rm -rf bin server/static
