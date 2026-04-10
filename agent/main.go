package main

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"math/big"
	"net/url"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/gorilla/websocket"
	"github.com/pion/webrtc/v3"
	"github.com/pion/webrtc/v3/pkg/media"
	"github.com/bsh888/remotectl/agent/input"
	"github.com/bsh888/remotectl/agent/pipeline"
	"github.com/bsh888/remotectl/agent/session"
	"gopkg.in/yaml.v3"
)

// ── Protocol types (must match server) ───────────────────────────────────────

const (
	TypeChallenge    = "challenge"
	TypeAuth         = "auth"
	TypeRegistered   = "registered"
	TypeViewerJoined  = "viewer_joined"
	TypeViewerLeft    = "viewer_left"
	TypeRejectViewer  = "reject_viewer" // agent → server: refuse a specific viewer
	TypeError         = "error"

	// E2EE key exchange (input events only)
	TypeKeyOffer  = "key_offer"
	TypeKeyAnswer = "key_answer"
	TypeInputEnc  = "input_enc"

	// WebRTC signaling
	TypeRTCOffer    = "rtc_offer"
	TypeRTCAnswer   = "rtc_answer"
	TypeRTCIceAgent = "rtc_ice_agent" // agent → viewer (via server)
)

type Message struct {
	Type    string          `json:"type"`
	Payload json.RawMessage `json:"payload,omitempty"`
}

type ChallengePayload struct {
	Nonce string `json:"nonce"`
}

type AuthPayload struct {
	DeviceID   string `json:"device_id"`
	HMAC       string `json:"hmac"`
	Platform   string `json:"platform"`
	Name       string `json:"name"`
	SessionPwd string `json:"session_pwd"` // ephemeral per-session numeric password
}

type ViewerEventPayload struct {
	ViewerID    string `json:"viewer_id"`
	ViewerCount int    `json:"viewer_count"`
}

type KeyOfferAgentPayload struct {
	ViewerID  string `json:"viewer_id"`
	PublicKey string `json:"public_key"`
}

type KeyAnswerAgentPayload struct {
	ViewerID  string `json:"viewer_id"`
	PublicKey string `json:"public_key"`
}

type InputEncAgentPayload struct {
	ViewerID string `json:"viewer_id"`
	Data     string `json:"data"`
}

// WebRTC signaling payloads
type RTCOfferPayload struct {
	ViewerID string `json:"viewer_id"`
	SDP      string `json:"sdp"`
}

type RTCAnswerPayload struct {
	ViewerID string `json:"viewer_id"`
	SDP      string `json:"sdp"`
}

type RTCIceAgentPayload struct {
	ViewerID  string `json:"viewer_id"`
	Candidate string `json:"candidate"`
	SDPMid    string `json:"sdp_mid"`
}

type RTCIceViewerPayload struct {
	ViewerID  string `json:"viewer_id"`
	Candidate string `json:"candidate"`
	SDPMid    string `json:"sdp_mid"`
}

// ── Config file ──────────────────────────────────────────────────────────────

type AgentConfig struct {
	Server   string  `yaml:"server"`
	ID       string  `yaml:"id"`
	Token    string  `yaml:"token"`
	Name     string  `yaml:"name"`
	FPS      int     `yaml:"fps"`
	Bitrate  int     `yaml:"bitrate"`
	Scale    float64 `yaml:"scale"`
	Retry    string  `yaml:"retry"`
	CACert        string  `yaml:"ca_cert"`
	AllowControl  bool    `yaml:"allow_control"`
}

func defaultAgentConfig() AgentConfig {
	return AgentConfig{
		Server:       "http://localhost:8080",
		FPS:          30,
		Bitrate:      3_000_000,
		Scale:        0.5,
		Retry:        "5s",
		AllowControl: true,
	}
}

func loadAgentConfig(path string) (AgentConfig, error) {
	cfg := defaultAgentConfig()
	if path == "" {
		return cfg, nil
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return cfg, fmt.Errorf("read config %q: %w", path, err)
	}
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return cfg, fmt.Errorf("parse config %q: %w", path, err)
	}
	return cfg, nil
}

func findConfigFlag() string {
	for i, a := range os.Args[1:] {
		if s, ok := strings.CutPrefix(a, "--config="); ok {
			return s
		}
		if (a == "--config" || a == "-config") && i+2 <= len(os.Args)-1 {
			return os.Args[i+2]
		}
	}
	return ""
}

// ICEServerConfig mirrors the server's wire type for JSON decoding.
type ICEServerConfig struct {
	URLs       []string `json:"urls"`
	Username   string   `json:"username,omitempty"`
	Credential string   `json:"credential,omitempty"`
}

// ── Agent ─────────────────────────────────────────────────────────────────────

type Agent struct {
	serverURL   string
	deviceID    string
	token       string
	name        string
	platform    string
	fps         int
	bitrate     int
	scale       float64
	caCert       string
	allowControl bool

	sessionPwd  string // random 6-digit numeric password, generated once per run

	conn        *websocket.Conn
	send        chan []byte
	viewerCount atomic.Int32

	// ICE servers received from the relay server (includes TURN when configured)
	iceServers   []ICEServerConfig
	iceServersMu sync.RWMutex

	// E2EE sessions (for input encryption only)
	sessions   map[string]*session.Session
	sessionsMu sync.RWMutex

	// WebRTC
	webrtcAPI  *webrtc.API
	videoTrack *webrtc.TrackLocalStaticSample
	rtcPeers   map[string]*webrtc.PeerConnection
	rtcMu      sync.RWMutex

	// Chat DataChannels (one per connected viewer)
	chatDCs  map[string]*webrtc.DataChannel
	chatMu   sync.RWMutex

	// In-flight inbound file transfers (chat)
	fileRx   map[string]*chatFileReceiver
	fileRxMu sync.Mutex

	// Browser-based chat UI
	chatSrv *chatServer
}


// chatFileReceiver buffers incoming file chunks until the transfer completes.
type chatFileReceiver struct {
	name     string
	size     int64
	mime     string
	buf      []byte
	seqCount int // total chunks received, used for ACK windowing
}

// chatFileAckWindow must match _kWindowSize in chat_service.dart.
// The agent sends one ACK per window; Flutter pauses after each window waiting
// for that ACK before sending the next batch.
const chatFileAckWindow = 8

// generateSessionPwd returns a random 8-digit numeric string used as the
// ephemeral session password viewers must provide to connect.
func generateSessionPwd() string {
	n, err := rand.Int(rand.Reader, big.NewInt(100_000_000))
	if err != nil {
		return "00000000"
	}
	return fmt.Sprintf("%08d", n)
}

// isValidDeviceID reports whether id is a valid 9-digit numeric device ID.
func isValidDeviceID(id string) bool {
	if len(id) != 9 {
		return false
	}
	for _, c := range id {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

// deviceIDFilePath returns the path where the auto-generated device ID is persisted.
func deviceIDFilePath() (string, error) {
	// Windows: %APPDATA%\remotectl\device.id
	if appdata := os.Getenv("APPDATA"); appdata != "" {
		return filepath.Join(appdata, "remotectl", "device.id"), nil
	}
	// macOS / Linux: ~/.config/remotectl/device.id
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, ".config", "remotectl", "device.id"), nil
}

// loadOrGenerateDeviceID reads the persisted device ID or creates a new 9-digit one.
func loadOrGenerateDeviceID() string {
	path, err := deviceIDFilePath()
	if err == nil {
		if data, err := os.ReadFile(path); err == nil {
			id := strings.TrimSpace(string(data))
			if len(id) == 9 {
				return id
			}
		}
	}
	// Generate: 100000000 – 999999999
	n, err := rand.Int(rand.Reader, big.NewInt(900_000_000))
	if err != nil {
		n = big.NewInt(0)
	}
	id := fmt.Sprintf("%d", 100_000_000+n.Int64())
	if path != "" {
		_ = os.MkdirAll(filepath.Dir(path), 0o700)
		_ = os.WriteFile(path, []byte(id), 0o600)
	}
	return id
}

// ── WebRTC helpers ─────────────────────────────────────────────────────────────

func newWebRTCAPI() *webrtc.API {
	m := &webrtc.MediaEngine{}
	// profile-level-id=42e01f (Baseline) for broad SDP negotiation compatibility.
	// The VideoToolbox encoder actually outputs High Profile (CABAC) — all modern
	// H.264 decoders (iOS, Chrome, Safari) handle High Profile regardless of what
	// profile-level-id is advertised in SDP.
	if err := m.RegisterCodec(webrtc.RTPCodecParameters{
		RTPCodecCapability: webrtc.RTPCodecCapability{
			MimeType:    webrtc.MimeTypeH264,
			ClockRate:   90000,
			SDPFmtpLine: "level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e01f",
		},
		PayloadType: 102,
	}, webrtc.RTPCodecTypeVideo); err != nil {
		log.Fatalf("register H264 codec: %v", err)
	}
	// RTX retransmission for PT 102 — recovers lost packets without waiting for the next keyframe.
	if err := m.RegisterCodec(webrtc.RTPCodecParameters{
		RTPCodecCapability: webrtc.RTPCodecCapability{
			MimeType:    "video/rtx",
			ClockRate:   90000,
			SDPFmtpLine: "apt=102",
		},
		PayloadType: 103,
	}, webrtc.RTPCodecTypeVideo); err != nil {
		log.Fatalf("register RTX codec: %v", err)
	}
	return webrtc.NewAPI(webrtc.WithMediaEngine(m))
}

func (a *Agent) newPeerConnection() (*webrtc.PeerConnection, error) {
	a.iceServersMu.RLock()
	cfgs := a.iceServers
	a.iceServersMu.RUnlock()

	// Fall back to public STUN if the server hasn't sent ICE config yet.
	if len(cfgs) == 0 {
		cfgs = []ICEServerConfig{{URLs: []string{"stun:stun.l.google.com:19302"}}}
	}
	servers := make([]webrtc.ICEServer, len(cfgs))
	for i, c := range cfgs {
		servers[i] = webrtc.ICEServer{
			URLs:       c.URLs,
			Username:   c.Username,
			Credential: c.Credential,
		}
	}
	return a.webrtcAPI.NewPeerConnection(webrtc.Configuration{ICEServers: servers})
}

// startRTC creates a WebRTC peer connection for the viewer, creates an offer,
// and sends it. Also initiates the ECDH key exchange for encrypted input.
func (a *Agent) startRTC(viewerID string) {
	// --- ECDH for input E2EE ---
	s, err := session.New(viewerID)
	if err != nil {
		log.Printf("session.New for %s: %v", viewerID, err)
		return
	}
	a.sessionsMu.Lock()
	a.sessions[viewerID] = s
	a.sessionsMu.Unlock()
	keyPayload, _ := json.Marshal(KeyOfferAgentPayload{ViewerID: viewerID, PublicKey: s.PublicKeyBase64()})
	a.enqueue(Message{Type: TypeKeyOffer, Payload: keyPayload})

	// --- WebRTC ---
	pc, err := a.newPeerConnection()
	if err != nil {
		log.Printf("NewPeerConnection for %s: %v", viewerID, err)
		return
	}

	sender, err := pc.AddTrack(a.videoTrack)
	if err != nil {
		log.Printf("AddTrack for %s: %v", viewerID, err)
		pc.Close()
		return
	}
	// Drain RTCP packets from the sender. Without this the pion/webrtc
	// internal buffer fills up and PLI/FIR requests from the viewer are
	// silently dropped. Any RTCP packet (PLI, FIR, NACK, SR) is treated as
	// a hint to produce a keyframe so the viewer gets a clean picture immediately.
	go func() {
		buf := make([]byte, 1500)
		for {
			if _, _, err := sender.Read(buf); err != nil {
				return
			}
			pipeline.RequestKeyframe()
		}
	}()

	// Trickle ICE — send candidates as they arrive
	pc.OnICECandidate(func(c *webrtc.ICECandidate) {
		if c == nil {
			return
		}
		ci := c.ToJSON()
		sdpMid := ""
		if ci.SDPMid != nil {
			sdpMid = *ci.SDPMid
		}
		payload, _ := json.Marshal(RTCIceAgentPayload{
			ViewerID:  viewerID,
			Candidate: ci.Candidate,
			SDPMid:    sdpMid,
		})
		a.enqueue(Message{Type: TypeRTCIceAgent, Payload: payload})
	})

	pc.OnConnectionStateChange(func(s webrtc.PeerConnectionState) {
		log.Printf("RTC %s state: %s", viewerID, s)
		if s == webrtc.PeerConnectionStateFailed || s == webrtc.PeerConnectionStateClosed {
			a.rtcMu.Lock()
			delete(a.rtcPeers, viewerID)
			a.rtcMu.Unlock()
		}
	})

	// input: reliable+ordered DataChannel for clicks, keys, scroll, paste.
	dc, err := pc.CreateDataChannel("input", nil)
	if err != nil {
		log.Printf("CreateDataChannel(input) for %s: %v", viewerID, err)
	} else {
		dc.OnMessage(func(msg webrtc.DataChannelMessage) { a.handleDCMessage(msg) })
	}

	// input-move: unreliable+unordered DataChannel for mousemove only.
	// Old cursor positions are stale the moment a newer one arrives — no need
	// to retransmit lost packets, which would add latency for no benefit.
	ordered := false
	maxRetransmits := uint16(0)
	dcMove, err := pc.CreateDataChannel("input-move", &webrtc.DataChannelInit{
		Ordered:        &ordered,
		MaxRetransmits: &maxRetransmits,
	})
	if err != nil {
		log.Printf("CreateDataChannel(input-move) for %s: %v", viewerID, err)
	} else {
		dcMove.OnMessage(func(msg webrtc.DataChannelMessage) { a.handleDCMessage(msg) })
	}

	// chat: reliable+ordered DataChannel for text messages, file transfer, and
	// voice messages. Created by the agent (offerer) so flutter_webrtc receives
	// it via pc.onDataChannel on the viewer side.
	chatDC, err := pc.CreateDataChannel("chat", nil)
	if err != nil {
		log.Printf("CreateDataChannel(chat) for %s: %v", viewerID, err)
	} else {
		chatDC.OnOpen(func() {
			log.Printf("[chat] channel open with viewer %s", viewerID[:min(8, len(viewerID))])
		})
		chatDC.OnMessage(func(msg webrtc.DataChannelMessage) {
			a.handleChatDCMessage(viewerID, chatDC, msg)
		})
		a.chatMu.Lock()
		a.chatDCs[viewerID] = chatDC
		a.chatMu.Unlock()
	}

	offer, err := pc.CreateOffer(nil)
	if err != nil {
		log.Printf("CreateOffer for %s: %v", viewerID, err)
		pc.Close()
		return
	}

	if err := pc.SetLocalDescription(offer); err != nil {
		log.Printf("SetLocalDescription for %s: %v", viewerID, err)
		pc.Close()
		return
	}

	a.rtcMu.Lock()
	a.rtcPeers[viewerID] = pc
	a.rtcMu.Unlock()

	payload, _ := json.Marshal(RTCOfferPayload{ViewerID: viewerID, SDP: offer.SDP})
	a.enqueue(Message{Type: TypeRTCOffer, Payload: payload})
	log.Printf("RTC offer sent to %s", viewerID)
}

// handleDCMessage decodes an input event arriving on any DataChannel and injects it.
func (a *Agent) handleDCMessage(msg webrtc.DataChannelMessage) {
	var ev input.Event
	if json.Unmarshal(msg.Data, &ev) != nil {
		return
	}
	if a.scale > 0 && a.scale != 1.0 {
		ev.X /= a.scale
		ev.Y /= a.scale
	}
	input.Handle(ev)
}

// broadcastChat sends raw DataChannel bytes to all connected viewers.
func (a *Agent) broadcastChat(data []byte) {
	a.chatMu.RLock()
	defer a.chatMu.RUnlock()
	for _, dc := range a.chatDCs {
		dc.SendText(string(data)) //nolint:errcheck
	}
}

// handleChatDCMessage processes an incoming chat DataChannel message from a viewer.
func (a *Agent) handleChatDCMessage(viewerID string, dc *webrtc.DataChannel, msg webrtc.DataChannelMessage) {
	var ev map[string]interface{}
	if json.Unmarshal(msg.Data, &ev) != nil {
		return
	}
	switch ev["type"] {
	case "chat_open":
		// Viewer opened the chat panel — open the browser if not already open.
		if !a.chatSrv.hasClients() {
			a.chatSrv.openBrowser()
		}

	case "text":
		text, _ := ev["text"].(string)
		if text == "" {
			return
		}
		log.Printf("[chat] message from %s: %s", viewerID[:min(8, len(viewerID))], text)
		ts, _ := ev["ts"].(float64)
		if ts == 0 {
			ts = float64(time.Now().UnixMilli())
		}
		a.chatSrv.push(chatMsgWire{Type: "text", From: "viewer", Text: text, Ts: int64(ts)})
		if !a.chatSrv.hasClients() {
			a.chatSrv.openBrowser()
		}
		showNotification("RemoteCtl 新消息", text)

	case "file_start":
		id, _ := ev["id"].(string)
		name, _ := ev["name"].(string)
		size, _ := ev["size"].(float64)
		mime, _ := ev["mime"].(string)
		if id == "" || name == "" {
			return
		}
		// Pre-allocate the buffer to the full expected size to avoid
		// repeated reallocation and copying as chunks arrive.
		buf := make([]byte, 0, int64(size))
		a.fileRxMu.Lock()
		a.fileRx[id] = &chatFileReceiver{name: name, size: int64(size), mime: mime, buf: buf}
		a.fileRxMu.Unlock()
		log.Printf("[chat] incoming file from %s: %s (%.0f bytes, %s)", viewerID[:min(8, len(viewerID))], name, size, mime)

	case "file_chunk":
		id, _ := ev["id"].(string)
		if id == "" {
			return
		}
		a.fileRxMu.Lock()
		rx := a.fileRx[id]
		a.fileRxMu.Unlock()
		if rx == nil {
			return
		}
		dataB64, _ := ev["data"].(string)
		decoded, err := base64.StdEncoding.DecodeString(dataB64)
		if err != nil {
			return
		}
		seq, _ := ev["seq"].(float64)
		isLast, _ := ev["last"].(bool)
		a.fileRxMu.Lock()
		rx.buf = append(rx.buf, decoded...)
		rx.seqCount++
		shouldAck := isLast || rx.seqCount%chatFileAckWindow == 0
		a.fileRxMu.Unlock()
		if shouldAck {
			ackData, _ := json.Marshal(map[string]interface{}{
				"type": "file_ack",
				"id":   id,
				"seq":  int(seq),
			})
			dc.SendText(string(ackData)) //nolint:errcheck
		}
		if isLast {
			// Run in a goroutine so the OnMessage callback returns promptly
			// and does not block pion/webrtc from processing further messages.
			go a.saveChatFile(id, rx)
		}
	}
}

// saveChatFile writes a completed inbound file to the Downloads directory.
func (a *Agent) saveChatFile(id string, rx *chatFileReceiver) {
	a.fileRxMu.Lock()
	data := make([]byte, len(rx.buf))
	copy(data, rx.buf)
	name := rx.name
	mime := rx.mime
	delete(a.fileRx, id)
	a.fileRxMu.Unlock()

	dir := chatDownloadsDir()
	path := filepath.Join(dir, name)
	// Avoid overwriting an existing file with the same name.
	if _, err := os.Stat(path); err == nil {
		ext := filepath.Ext(name)
		base := strings.TrimSuffix(name, ext)
		path = filepath.Join(dir, fmt.Sprintf("%s-%d%s", base, time.Now().UnixMilli(), ext))
	}
	if err := os.WriteFile(path, data, 0o644); err != nil {
		log.Printf("[chat] failed to save %s: %v", name, err)
		return
	}
	log.Printf("[chat] saved: %s", path)
	// Push to browser chat UI
	a.chatSrv.push(chatMsgWire{
		Type:    "file",
		From:    "viewer",
		Name:    name,
		Mime:    mime,
		Size:    int64(len(data)),
		FileURL: a.chatSrv.fileURL(path),
	})
	if !a.chatSrv.hasClients() {
		a.chatSrv.openBrowser()
	}
	if strings.HasPrefix(mime, "audio/") {
		showNotification("RemoteCtl 语音消息", "已保存到: "+path)
	} else {
		showNotification("RemoteCtl 文件已接收", name+" 已保存到下载目录")
	}
}

// chatDownloadsDir returns the best directory for saving received files.
func chatDownloadsDir() string {
	home, _ := os.UserHomeDir()
	if home != "" {
		dl := filepath.Join(home, "Downloads")
		if _, err := os.Stat(dl); err == nil {
			return dl
		}
	}
	return os.TempDir()
}

// enqueue marshals and queues a message for the write pump (non-blocking).
func (a *Agent) enqueue(msg Message) {
	data, _ := json.Marshal(msg)
	select {
	case a.send <- data:
	default:
	}
}

// ── Handshake ─────────────────────────────────────────────────────────────────

func (a *Agent) dial() error {
	u, err := url.Parse(a.serverURL)
	if err != nil {
		return err
	}
	switch u.Scheme {
	case "http":
		u.Scheme = "ws"
	case "https":
		u.Scheme = "wss"
	}
	u.Path = "/ws/agent"

	tlsCfg, err := a.buildTLSConfig()
	if err != nil {
		return fmt.Errorf("tls config: %w", err)
	}

	dialer := *websocket.DefaultDialer
	dialer.TLSClientConfig = tlsCfg

	log.Printf("connecting to %s", u)
	conn, _, err := dialer.Dial(u.String(), nil)
	if err != nil {
		return err
	}
	a.conn = conn
	a.send = make(chan []byte, 256)
	return nil
}

func (a *Agent) buildTLSConfig() (*tls.Config, error) {
	if a.caCert == "" {
		return &tls.Config{MinVersion: tls.VersionTLS12}, nil
	}
	caPEM, err := os.ReadFile(a.caCert)
	if err != nil {
		return nil, fmt.Errorf("read CA cert %q: %w", a.caCert, err)
	}
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(caPEM) {
		return nil, fmt.Errorf("no valid certificates in %q", a.caCert)
	}
	log.Printf("using custom CA cert: %s", a.caCert)
	return &tls.Config{RootCAs: pool, MinVersion: tls.VersionTLS12}, nil
}

// errAuthRejected is a sentinel returned by authenticate() when the server
// explicitly rejects the device token. The caller should not retry.
var errAuthRejected = fmt.Errorf("authentication rejected by server")

func (a *Agent) authenticate() error {
	// Step 1: receive challenge
	a.conn.SetReadDeadline(time.Now().Add(15 * time.Second))
	_, data, err := a.conn.ReadMessage()
	if err != nil {
		return err
	}
	var msg Message
	if err := json.Unmarshal(data, &msg); err != nil || msg.Type != TypeChallenge {
		return fmt.Errorf("expected challenge, got %s", msg.Type)
	}
	var chal ChallengePayload
	if err := json.Unmarshal(msg.Payload, &chal); err != nil {
		return err
	}
	nonce, err := hex.DecodeString(chal.Nonce)
	if err != nil {
		return err
	}

	// Step 2: send auth
	mac := hmac.New(sha256.New, []byte(a.token))
	mac.Write(nonce)
	macHex := hex.EncodeToString(mac.Sum(nil))
	payload, _ := json.Marshal(AuthPayload{
		DeviceID: a.deviceID, HMAC: macHex, Platform: a.platform, Name: a.name,
		SessionPwd: a.sessionPwd,
	})
	authMsg, _ := json.Marshal(Message{Type: TypeAuth, Payload: payload})
	a.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
	if err := a.conn.WriteMessage(websocket.TextMessage, authMsg); err != nil {
		return err
	}

	// Step 3: wait for registered confirmation (or error)
	a.conn.SetReadDeadline(time.Now().Add(15 * time.Second))
	_, data, err = a.conn.ReadMessage()
	if err != nil {
		return err
	}
	var resp Message
	if err := json.Unmarshal(data, &resp); err != nil {
		return fmt.Errorf("invalid response: %w", err)
	}
	switch resp.Type {
	case TypeRegistered:
		return nil
	case TypeError:
		return errAuthRejected
	default:
		return fmt.Errorf("expected registered, got %s", resp.Type)
	}
}

// ── Main loop ─────────────────────────────────────────────────────────────────

func (a *Agent) run(ctx context.Context) {
	if err := a.dial(); err != nil {
		log.Printf("dial: %v", err)
		return
	}
	defer a.conn.Close()

	if err := a.authenticate(); err != nil {
		if err == errAuthRejected {
			// Machine-readable marker for the Flutter app (do not change format)
			fmt.Printf("AUTH_FAILED:设备密钥不正确，请检查配置\n")
			log.Printf("认证失败：设备密钥不正确，请检查配置后重新启动")
			os.Exit(1)
		}
		log.Printf("auth: %v", err)
		return
	}
	a.conn.SetReadDeadline(time.Time{})

	// runCtx is cancelled when this connection ends (readPump returns).
	// This ensures encodePump stops the pipeline before the next reconnect
	// attempt, preventing "already running" errors.
	runCtx, runCancel := context.WithCancel(ctx)
	defer runCancel()

	go a.writePump(a.conn, a.send)
	go a.encodePump(runCtx)
	a.readPump()
}

func (a *Agent) readPump() {
	a.conn.SetReadLimit(64 << 10) // 64 KB for signaling messages
	a.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	a.conn.SetPongHandler(func(string) error {
		a.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		return nil
	})

	for {
		_, data, err := a.conn.ReadMessage()
		if err != nil {
			log.Printf("read: %v", err)
			return
		}
		var msg Message
		if err := json.Unmarshal(data, &msg); err != nil {
			continue
		}

		switch msg.Type {

		case TypeRegistered:
			log.Printf("registered as %s", a.deviceID)
			var reg struct {
				ICEServers []ICEServerConfig `json:"ice_servers"`
			}
			if json.Unmarshal(msg.Payload, &reg) == nil && len(reg.ICEServers) > 0 {
				a.iceServersMu.Lock()
				a.iceServers = reg.ICEServers
				a.iceServersMu.Unlock()
				log.Printf("ICE servers: %d configured (TURN=%v)", len(reg.ICEServers), len(reg.ICEServers) > 1)
			}

		case TypeViewerJoined:
			var e ViewerEventPayload
			json.Unmarshal(msg.Payload, &e)
			a.viewerCount.Store(int32(e.ViewerCount))
			if !a.allowControl {
				log.Printf("viewer %s rejected (allow_control=false)", e.ViewerID)
				payload, _ := json.Marshal(map[string]string{"viewer_id": e.ViewerID})
				a.enqueue(Message{Type: TypeRejectViewer, Payload: payload})
				break
			}
			log.Printf("viewer joined (%s), total=%d", e.ViewerID, e.ViewerCount)
			go a.startRTC(e.ViewerID)

		case TypeViewerLeft:
			var e ViewerEventPayload
			json.Unmarshal(msg.Payload, &e)
			a.viewerCount.Store(int32(e.ViewerCount))
			// Clean up RTC peer
			a.rtcMu.Lock()
			if pc, ok := a.rtcPeers[e.ViewerID]; ok {
				pc.Close()
				delete(a.rtcPeers, e.ViewerID)
			}
			a.rtcMu.Unlock()
			// Clean up E2EE session
			a.sessionsMu.Lock()
			delete(a.sessions, e.ViewerID)
			a.sessionsMu.Unlock()
			// Clean up chat DC
			a.chatMu.Lock()
			delete(a.chatDCs, e.ViewerID)
			a.chatMu.Unlock()
			log.Printf("viewer left (%s), total=%d", e.ViewerID, e.ViewerCount)

		// E2EE key exchange: viewer replied with its public key
		case TypeKeyAnswer:
			var p KeyAnswerAgentPayload
			if err := json.Unmarshal(msg.Payload, &p); err != nil {
				continue
			}
			// Empty public key means the viewer could not complete key exchange
			// (e.g. platform crypto not available). Drop the session silently —
			// input will still work via WebRTC DataChannel (DTLS-encrypted).
			if p.PublicKey == "" {
				log.Printf("key exchange skipped for %s (viewer sent empty key, WS fallback disabled)", p.ViewerID)
				a.sessionsMu.Lock()
				delete(a.sessions, p.ViewerID)
				a.sessionsMu.Unlock()
				continue
			}
			a.sessionsMu.Lock()
			s, ok := a.sessions[p.ViewerID]
			a.sessionsMu.Unlock()
			if !ok {
				continue
			}
			if err := s.Complete(p.PublicKey); err != nil {
				log.Printf("key exchange failed for %s: %v", p.ViewerID, err)
				a.sessionsMu.Lock()
				delete(a.sessions, p.ViewerID)
				a.sessionsMu.Unlock()
				continue
			}
			log.Printf("E2EE session established with %s", p.ViewerID)

		// Encrypted input from viewer
		case TypeInputEnc:
			var p InputEncAgentPayload
			if err := json.Unmarshal(msg.Payload, &p); err != nil {
				continue
			}
			a.sessionsMu.RLock()
			s, ok := a.sessions[p.ViewerID]
			a.sessionsMu.RUnlock()
			if !ok || !s.Ready() {
				continue
			}
			plaintext, err := s.Decrypt(p.Data)
			if err != nil {
				log.Printf("decrypt input from %s: %v", p.ViewerID, err)
				continue
			}
			var ev input.Event
			if err := json.Unmarshal(plaintext, &ev); err == nil {
				// Client sends coordinates in video-frame pixels.
				// Scale back to physical screen pixels before injecting.
				if a.scale > 0 && a.scale != 1.0 {
					ev.X /= a.scale
					ev.Y /= a.scale
				}
				input.Handle(ev)
			}

		// WebRTC answer from viewer
		case TypeRTCAnswer:
			var p RTCAnswerPayload
			if err := json.Unmarshal(msg.Payload, &p); err != nil {
				continue
			}
			a.rtcMu.RLock()
			pc, ok := a.rtcPeers[p.ViewerID]
			a.rtcMu.RUnlock()
			if !ok {
				continue
			}
			answer := webrtc.SessionDescription{Type: webrtc.SDPTypeAnswer, SDP: p.SDP}
			if err := pc.SetRemoteDescription(answer); err != nil {
				log.Printf("SetRemoteDescription for %s: %v", p.ViewerID, err)
			}

		// ICE candidate from viewer
		case "rtc_ice_viewer":
			var p RTCIceViewerPayload
			if err := json.Unmarshal(msg.Payload, &p); err != nil {
				continue
			}
			if p.Candidate == "" {
				// end-of-candidates marker — ignore
				continue
			}
			a.rtcMu.RLock()
			pc, ok := a.rtcPeers[p.ViewerID]
			a.rtcMu.RUnlock()
			if !ok {
				continue
			}
			log.Printf("ICE candidate from viewer %s: %s", p.ViewerID, p.Candidate)
			sdpMid := p.SDPMid
			if err := pc.AddICECandidate(webrtc.ICECandidateInit{
				Candidate: p.Candidate,
				SDPMid:    &sdpMid,
			}); err != nil {
				log.Printf("AddICECandidate for %s: %v", p.ViewerID, err)
			}

		case TypeError:
			log.Printf("server error: %s", string(msg.Payload))
		}
	}
}

// writePump owns the write side of conn for one connection lifetime.
// conn and send are captured at start time — not read from the struct — so a
// reconnect that replaces a.conn/a.send never causes two goroutines to write
// to the same connection concurrently.
func (a *Agent) writePump(conn *websocket.Conn, send <-chan []byte) {
	ticker := time.NewTicker(54 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case msg, ok := <-send:
			conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if !ok {
				return
			}
			if err := conn.WriteMessage(websocket.TextMessage, msg); err != nil {
				return
			}
		case <-ticker.C:
			conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// encodePump starts the capture/encode pipeline and distributes H.264 frames
// to all connected viewers via their WebRTC tracks. Restarts automatically on
// unexpected stop (e.g. SCStream kicked by macOS) with exponential backoff:
// if the pipeline ran < 5 s before dying, double the wait (up to 30 s) so the
// system has time to fully release resources before we try again.
func (a *Agent) encodePump(ctx context.Context) {
	const (
		baseDelay   = 3 * time.Second
		maxDelay    = 30 * time.Second
		stableAfter = 5 * time.Second // reset backoff if ran longer than this
	)
	delay := baseDelay
	for {
		if ctx.Err() != nil {
			return
		}
		log.Printf("pipeline: starting capture at scale=%.2f fps=%d bitrate=%d", a.scale, a.fps, a.bitrate)
		startedAt := time.Now()
		frames, pErr := pipeline.Start(a.scale, a.fps, a.bitrate)
		if pErr != "" {
			log.Printf("pipeline ERROR: %s — retrying in %s", pErr, delay)
			select {
			case <-ctx.Done():
				return
			case <-time.After(delay):
			}
			delay = min(delay*2, maxDelay)
			continue
		}

		// Log pipeline diagnostics after 5 s to detect silent VT failures.
		diagCtx, diagCancel := context.WithCancel(ctx)
		go func() {
			select {
			case <-diagCtx.Done():
			case <-time.After(5 * time.Second):
				pipeline.LogDiag()
			}
		}()

		stopped := a.drainPipeline(ctx, frames, pipeline.Done())
		diagCancel()
		pipeline.Stop()

		if !stopped {
			return // ctx cancelled — clean exit
		}

		runFor := time.Since(startedAt)
		if runFor >= stableAfter {
			delay = baseDelay // ran long enough — reset backoff
		} else {
			delay = min(delay*2, maxDelay) // crashed fast — back off
		}
		log.Printf("pipeline: stopped after %s, restarting in %s...", runFor.Round(time.Millisecond), delay)
		select {
		case <-ctx.Done():
			return
		case <-time.After(delay):
		}
	}
}

// drainPipeline reads frames until the pipeline stops or ctx is cancelled.
// Returns true if the pipeline stopped on its own (restart warranted),
// false if ctx was cancelled.
//
// A watchdog timer fires if no frame arrives within 5 s — this catches the
// Windows case where the GDI capture thread dies silently without closing the
// frame channel or the Done() channel.
func (a *Agent) drainPipeline(ctx context.Context, frames <-chan pipeline.Frame, done <-chan struct{}) bool {
	const noFrameTimeout = 5 * time.Second
	watchdog := time.NewTimer(noFrameTimeout)
	defer watchdog.Stop()

	var frameCount int64
	for {
		select {
		case <-ctx.Done():
			return false
		case <-done:
			return true
		case <-watchdog.C:
			log.Printf("pipeline: no frame for %s — assuming capture died, restarting", noFrameTimeout)
			return true
		case f, ok := <-frames:
			if !ok {
				return true
			}
			// Reset watchdog each time a frame arrives.
			if !watchdog.Stop() {
				select {
				case <-watchdog.C:
				default:
				}
			}
			watchdog.Reset(noFrameTimeout)

			frameCount++
			if frameCount == 1 {
				log.Printf("pipeline: first H.264 frame received (keyframe=%v, %d bytes)", f.IsKeyframe, len(f.Data))
			}
			if a.viewerCount.Load() == 0 {
				continue
			}
			if err := a.videoTrack.WriteSample(media.Sample{
				Data:     f.Data,
				Duration: f.Duration,
			}); err != nil {
				log.Printf("WriteSample: %v", err)
			}
		}
	}
}

// ── main ──────────────────────────────────────────────────────────────────────

func main() {
	cfg, err := loadAgentConfig(findConfigFlag())
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	_ = flag.String("config", "", "path to YAML config file")
	serverURL := flag.String("server", cfg.Server, "relay server URL")
	deviceID := flag.String("id", cfg.ID, "unique device ID (required)")
	token := flag.String("token", cfg.Token, "agent auth token (HMAC secret)")
	name := flag.String("name", cfg.Name, "human-readable device name")
	platform := flag.String("platform", detectPlatform(), "platform override")
	fps := flag.Int("fps", cfg.FPS, "capture/encode FPS (1-60)")
	bitrate := flag.Int("bitrate", cfg.Bitrate, "H.264 encode bitrate in bits/sec")
	scale := flag.Float64("scale", cfg.Scale, "capture resolution scale (0.25-1.0)")
	retryStr := flag.String("retry", cfg.Retry, "reconnect interval (e.g. 5s)")
	caCert := flag.String("ca-cert", cfg.CACert, "path to custom CA certificate")
	noControl := flag.Bool("no-control", !cfg.AllowControl, "refuse all incoming remote-control connections")
	flag.Parse()

	retryDur, err := time.ParseDuration(*retryStr)
	if err != nil {
		log.Fatalf("invalid retry duration %q: %v", *retryStr, err)
	}
	retry := &retryDur

	if !isValidDeviceID(*deviceID) {
		*deviceID = loadOrGenerateDeviceID()
	}
	if *name == "" {
		*name = *deviceID
	}

	// Build shared WebRTC API and video track (outlive reconnects)
	api := newWebRTCAPI()
	videoTrack, err := webrtc.NewTrackLocalStaticSample(
		webrtc.RTPCodecCapability{MimeType: webrtc.MimeTypeH264},
		"video", "remotectl",
	)
	if err != nil {
		log.Fatalf("NewTrackLocalStaticSample: %v", err)
	}

	chatSrv := newChatServer(17770)
	chatSrv.start()

	sessionPwd := generateSessionPwd()
	agent := &Agent{
		serverURL:  *serverURL,
		deviceID:   *deviceID,
		token:      *token,
		name:       *name,
		platform:   *platform,
		fps:        *fps,
		bitrate:    *bitrate,
		scale:      *scale,
		caCert:       *caCert,
		allowControl: !*noControl,
		sessionPwd:   sessionPwd,
		sessions:   make(map[string]*session.Session),
		webrtcAPI:  api,
		videoTrack: videoTrack,
		rtcPeers:   make(map[string]*webrtc.PeerConnection),
		chatDCs:    make(map[string]*webrtc.DataChannel),
		fileRx:     make(map[string]*chatFileReceiver),
		chatSrv:    chatSrv,
	}
	chatSrv.sendToViewers = agent.broadcastChat

	// Machine-readable marker for the Flutter app to parse (do not change format)
	fmt.Printf("SESSION_PWD:%s\n", sessionPwd)
	log.Printf("┌─────────────────────────────────────────────────")
	log.Printf("│ 设备 ID:  %s", *deviceID)
	log.Printf("│ 会话密码: %s", sessionPwd)
	log.Printf("│ 聊天界面: %s", chatSrv.URL())
	log.Printf("└─────────────────────────────────────────────────")

	// ── macOS permission checks (run once at startup) ─────────────────────────
	appName := "remotectl"
	if exe, err := os.Executable(); err == nil {
		appName = filepath.Base(exe)
	}
	if !pipeline.CheckScreenRecording() {
		log.Printf("WARNING: 屏幕录制权限未授权 — 截图将无法工作")
		log.Printf("  请前往: 系统设置 → 隐私与安全性 → 屏幕录制 → 添加 %s", appName)
	}
	if !input.RequestAccessibilityPrompt() {
		// RequestAccessibilityPrompt triggers the system Accessibility dialog.
		log.Printf("WARNING: 辅助功能权限未授权 — 鼠标/键盘注入将无法工作")
		log.Printf("  请前往: 系统设置 → 隐私与安全性 → 辅助功能 → 添加 %s", appName)
		log.Printf("  授权后请重新启动共享")
	}

	ctx, cancel := context.WithCancel(context.Background())

	go func() {
		quit := make(chan os.Signal, 1)
		signal.Notify(quit, syscall.SIGTERM, syscall.SIGINT)
		<-quit
		log.Println("shutting down...")
		cancel()
		if agent.conn != nil {
			agent.conn.Close()
		}
	}()

	for {
		agent.run(ctx)
		select {
		case <-ctx.Done():
			log.Println("agent stopped")
			return
		default:
		}
		log.Printf("disconnected, retrying in %s...", *retry)
		// Reset per-connection state before retry
		agent.sessions = make(map[string]*session.Session)
		agent.rtcPeers = make(map[string]*webrtc.PeerConnection)
		select {
		case <-time.After(*retry):
		case <-ctx.Done():
			return
		}
	}
}
