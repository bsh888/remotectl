// remotectl relay server
//
// Security model:
//   - Transport:    TLS (WSS) — mandatory in production (--tls-cert / --tls-key)
//   - Agent auth:   HMAC-SHA256 challenge-response (prevents replay attacks)
//   - E2EE input:   ECDH P-256 + HKDF-SHA256 + AES-256-GCM for input events
//   - Video:        WebRTC H.264 P2P (server relays SDP/ICE, never sees video)
//
// Message flow:
//
//	[agent connect]
//	  server → agent : challenge{nonce}
//	  agent  → server: auth{device_id, hmac, platform, name}
//	  server → agent : registered{device_id}   (or closes)
//
//	[viewer connect]
//	  viewer → server: connect{device_id, password}
//	  server → viewer: connected{device_id, name, platform}   (or error)
//	  server → agent : viewer_joined{viewer_id, viewer_count}
//
//	[WebRTC signaling — server relays opaquely]
//	  agent  → server → viewer: rtc_offer{viewer_id→stripped, sdp}
//	  viewer → server → agent : rtc_answer{sdp}       (server adds viewer_id)
//	  agent  ↔ server ↔ viewer: rtc_ice_{agent,viewer} (trickle ICE)
//
//	[E2EE input key exchange — server is transparent]
//	  agent  → server → viewer: key_offer{viewer_id→stripped, public_key}
//	  viewer → server → agent : key_answer{public_key} (server adds viewer_id)
//	  viewer → server → agent : input_enc{data}        (server adds viewer_id)
package main

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/gorilla/websocket"
	"gopkg.in/yaml.v3"
)

const (
	writeWait      = 10 * time.Second
	pongWait       = 60 * time.Second
	pingPeriod     = pongWait * 9 / 10
	maxMessageSize = 64 << 10 // 64 KB (signaling only; video goes P2P via WebRTC)
	challengeSize  = 32      // bytes
)

// ── Message types ────────────────────────────────────────────────────────────

const (
	// Server → Agent (handshake)
	TypeChallenge = "challenge"
	// Agent → Server (handshake)
	TypeAuth = "auth"

	// Server ↔ Agent / Viewer
	TypeRegistered   = "registered"
	TypeConnect      = "connect"
	TypeConnected    = "connected"
	TypeViewerJoined = "viewer_joined"
	TypeViewerLeft   = "viewer_left"
	TypeAgentOffline = "agent_offline"
	TypeError        = "error"

	// E2EE key exchange (server relays opaquely)
	TypeKeyOffer  = "key_offer"  // agent → viewer (via server)
	TypeKeyAnswer = "key_answer" // viewer → agent (via server)

	// Encrypted input events (server cannot read)
	TypeInputEnc = "input_enc" // viewer → agent

	// WebRTC signaling (server relays opaquely)
	TypeRTCOffer    = "rtc_offer"      // agent → viewer (via server)
	TypeRTCAnswer   = "rtc_answer"     // viewer → agent (via server)
	TypeRTCIceAgent = "rtc_ice_agent"  // agent → viewer (via server)
	TypeRTCIceViewer = "rtc_ice_viewer" // viewer → agent (via server)
)

// ── Wire types ───────────────────────────────────────────────────────────────

type Message struct {
	Type    string          `json:"type"`
	Payload json.RawMessage `json:"payload,omitempty"`
}

type ChallengePayload struct {
	Nonce string `json:"nonce"` // hex-encoded 32 random bytes
}

type AuthPayload struct {
	DeviceID string `json:"device_id"`
	HMAC     string `json:"hmac"` // hex HMAC-SHA256(nonce_bytes, token)
	Platform string `json:"platform"`
	Name     string `json:"name"`
}

type ConnectPayload struct {
	DeviceID string `json:"device_id"`
	Password string `json:"password"`
}

// ICEServerConfig is sent to both agent and viewer so they use the same ICE servers.
// When a TURN server is configured on the relay, this includes TURN credentials;
// otherwise it contains only the public STUN server.
type ICEServerConfig struct {
	URLs       []string `json:"urls"`
	Username   string   `json:"username,omitempty"`
	Credential string   `json:"credential,omitempty"`
}

type ConnectedPayload struct {
	DeviceID   string            `json:"device_id"`
	Name       string            `json:"name"`
	Platform   string            `json:"platform"`
	ICEServers []ICEServerConfig `json:"ice_servers,omitempty"`
}

type ViewerEventPayload struct {
	ViewerID    string `json:"viewer_id"`
	ViewerCount int    `json:"viewer_count"`
}

type ErrorPayload struct {
	Message string `json:"message"`
}

// KeyOffer: agent → server → viewer
// The agent includes viewer_id so the server can route it; viewer receives only public_key.
type KeyOfferAgentPayload struct {
	ViewerID  string `json:"viewer_id"`
	PublicKey string `json:"public_key"` // base64 raw P-256 public key
}

type KeyOfferViewerPayload struct {
	PublicKey string `json:"public_key"`
}

// KeyAnswer: viewer → server → agent
// Viewer sends only public_key; server adds viewer_id before forwarding to agent.
type KeyAnswerViewerPayload struct {
	PublicKey string `json:"public_key"`
}

type KeyAnswerAgentPayload struct {
	ViewerID  string `json:"viewer_id"`
	PublicKey string `json:"public_key"`
}

// InputEnc: viewer → server → agent
// Viewer sends data; server adds viewer_id.
type InputEncViewerPayload struct {
	Data string `json:"data"` // base64(nonce || AES-256-GCM ciphertext)
}

type InputEncAgentPayload struct {
	ViewerID string `json:"viewer_id"`
	Data     string `json:"data"`
}

type DeviceInfo struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Platform    string `json:"platform"`
	ViewerCount int    `json:"viewer_count"`
}

// ── Config file ──────────────────────────────────────────────────────────────

type TURNConfig struct {
	URL      string `yaml:"url"`
	User     string `yaml:"user"`
	Password string `yaml:"password"`
}

type ServerConfig struct {
	Addr       string            `yaml:"addr"`
	Password   string            `yaml:"password"`
	TLSCert    string            `yaml:"tls_cert"`
	TLSKey     string            `yaml:"tls_key"`
	Static     string            `yaml:"static"`
	AgentToken string            `yaml:"agent_token"` // single shared token for all agents
	Tokens     map[string]string `yaml:"tokens"`      // per-device tokens (optional, higher priority)
	TURN       TURNConfig        `yaml:"turn"`
}

func defaultServerConfig() ServerConfig {
	return ServerConfig{
		Addr:     ":8080",
		Password: "remotectl",
		Static:   "./static",
	}
}

func loadServerConfig(path string) (ServerConfig, error) {
	cfg := defaultServerConfig()
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

// findConfigFlag scans os.Args for --config=<path> or --config <path>
// before flag.Parse() so config values can seed flag defaults.
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

// ── Hub ──────────────────────────────────────────────────────────────────────

type Hub struct {
	agents     map[string]*Agent
	mu         sync.RWMutex
	password   string
	agentToken string            // single shared token accepted from any agent
	tokens     map[string]string // per-device tokens (override agentToken if set)
	iceServers []ICEServerConfig
}

func newHub(password, agentToken string, tokens map[string]string, iceServers []ICEServerConfig) *Hub {
	return &Hub{
		agents:     make(map[string]*Agent),
		password:   password,
		agentToken: agentToken,
		tokens:     tokens,
		iceServers: iceServers,
	}
}

func (h *Hub) verifyHMAC(deviceID, nonceHex, receivedHMAC string) bool {
	// Priority: per-device token > global agent_token > dev mode
	token, ok := h.tokens[deviceID]
	if !ok {
		if h.agentToken != "" {
			// Global token: any device with the right token is accepted.
			token = h.agentToken
		} else if len(h.tokens) > 0 {
			return false // per-device tokens configured but this device is unknown
		} else {
			// Dev mode: no tokens configured at all, accept everyone.
			return true
		}
	}
	nonce, err := hex.DecodeString(nonceHex)
	if err != nil {
		return false
	}
	mac := hmac.New(sha256.New, []byte(token))
	mac.Write(nonce)
	expected := hex.EncodeToString(mac.Sum(nil))
	return hmac.Equal([]byte(expected), []byte(receivedHMAC))
}

// ── Agent ─────────────────────────────────────────────────────────────────────

type Agent struct {
	id       string
	name     string
	platform string
	conn     *websocket.Conn
	send     chan []byte
	viewers  map[string]*Viewer
	mu       sync.RWMutex
	hub      *Hub
	closed   atomic.Bool
}

func (a *Agent) close() {
	if a.closed.CompareAndSwap(false, true) {
		close(a.send)
		a.conn.Close()
	}
}

func (a *Agent) viewerCount() int {
	a.mu.RLock()
	defer a.mu.RUnlock()
	return len(a.viewers)
}

func (a *Agent) addViewer(v *Viewer) {
	a.mu.Lock()
	a.viewers[v.id] = v
	count := len(a.viewers)
	a.mu.Unlock()
	if !a.closed.Load() {
		sendJSON(a.send, TypeViewerJoined, ViewerEventPayload{ViewerID: v.id, ViewerCount: count})
	}
}

func (a *Agent) removeViewer(v *Viewer) {
	a.mu.Lock()
	delete(a.viewers, v.id)
	count := len(a.viewers)
	a.mu.Unlock()
	if !a.closed.Load() {
		sendJSON(a.send, TypeViewerLeft, ViewerEventPayload{ViewerID: v.id, ViewerCount: count})
	}
}

func (a *Agent) readPump() {
	defer func() {
		// Notify all viewers that agent went offline
		a.mu.RLock()
		for _, v := range a.viewers {
			sendJSON(v.send, TypeAgentOffline, nil)
		}
		a.mu.RUnlock()

		a.hub.mu.Lock()
		if a.hub.agents[a.id] == a {
			delete(a.hub.agents, a.id)
		}
		a.hub.mu.Unlock()

		a.close()
		log.Printf("[agent] disconnected: %s", a.id)
	}()

	a.conn.SetReadLimit(maxMessageSize)
	a.conn.SetReadDeadline(time.Now().Add(pongWait))
	a.conn.SetPongHandler(func(string) error {
		a.conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	for {
		_, data, err := a.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("[agent] read error %s: %v", a.id, err)
			}
			return
		}

		var msg Message
		if err := json.Unmarshal(data, &msg); err != nil {
			continue
		}

		switch msg.Type {

		// E2EE: agent sends key offer for a specific viewer
		case TypeKeyOffer:
			var p KeyOfferAgentPayload
			if err := json.Unmarshal(msg.Payload, &p); err != nil {
				continue
			}
			a.mu.RLock()
			v, ok := a.viewers[p.ViewerID]
			a.mu.RUnlock()
			if ok {
				sendJSON(v.send, TypeKeyOffer, KeyOfferViewerPayload{PublicKey: p.PublicKey})
			}

		// WebRTC: agent sends SDP offer for a specific viewer
		case TypeRTCOffer:
			var p struct {
				ViewerID string `json:"viewer_id"`
				SDP      string `json:"sdp"`
			}
			if err := json.Unmarshal(msg.Payload, &p); err != nil {
				continue
			}
			a.mu.RLock()
			v, ok := a.viewers[p.ViewerID]
			a.mu.RUnlock()
			if ok {
				sendJSON(v.send, TypeRTCOffer, map[string]string{"sdp": p.SDP})
			}

		// WebRTC: agent sends ICE candidate for a specific viewer
		case TypeRTCIceAgent:
			var p struct {
				ViewerID  string `json:"viewer_id"`
				Candidate string `json:"candidate"`
				SDPMid    string `json:"sdp_mid"`
			}
			if err := json.Unmarshal(msg.Payload, &p); err != nil {
				continue
			}
			a.mu.RLock()
			v, ok := a.viewers[p.ViewerID]
			a.mu.RUnlock()
			if ok {
				sendJSON(v.send, TypeRTCIceAgent, map[string]string{
					"candidate": p.Candidate,
					"sdp_mid":   p.SDPMid,
				})
			}
		}
	}
}

func (a *Agent) writePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		a.conn.Close()
	}()
	for {
		select {
		case msg, ok := <-a.send:
			a.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				a.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := a.conn.WriteMessage(websocket.TextMessage, msg); err != nil {
				return
			}
		case <-ticker.C:
			a.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := a.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// ── Viewer ────────────────────────────────────────────────────────────────────

type Viewer struct {
	id    string
	conn  *websocket.Conn
	send  chan []byte
	agent *Agent
}

func (v *Viewer) readPump() {
	defer func() {
		v.agent.removeViewer(v)
		v.conn.Close()
		log.Printf("[viewer] disconnected: %s from agent %s", v.id, v.agent.id)
	}()

	v.conn.SetReadLimit(64 << 10) // signaling + input events
	v.conn.SetReadDeadline(time.Now().Add(pongWait))
	v.conn.SetPongHandler(func(string) error {
		v.conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	for {
		_, data, err := v.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("[viewer] read error %s: %v", v.id, err)
			}
			return
		}

		var msg Message
		if err := json.Unmarshal(data, &msg); err != nil {
			continue
		}

		switch msg.Type {

		// E2EE: viewer responds with its public key; server adds viewer_id and forwards
		case TypeKeyAnswer:
			var p KeyAnswerViewerPayload
			if err := json.Unmarshal(msg.Payload, &p); err != nil {
				continue
			}
			sendJSON(v.agent.send, TypeKeyAnswer, KeyAnswerAgentPayload{
				ViewerID:  v.id,
				PublicKey: p.PublicKey,
			})

		// E2EE: viewer sends encrypted input; server adds viewer_id and forwards
		case TypeInputEnc:
			var p InputEncViewerPayload
			if err := json.Unmarshal(msg.Payload, &p); err != nil {
				continue
			}
			sendJSON(v.agent.send, TypeInputEnc, InputEncAgentPayload{
				ViewerID: v.id,
				Data:     p.Data,
			})

		// WebRTC: viewer sends SDP answer; server adds viewer_id and forwards
		case TypeRTCAnswer:
			var p struct {
				SDP string `json:"sdp"`
			}
			if err := json.Unmarshal(msg.Payload, &p); err != nil {
				continue
			}
			sendJSON(v.agent.send, TypeRTCAnswer, map[string]string{
				"viewer_id": v.id,
				"sdp":       p.SDP,
			})

		// WebRTC: viewer sends ICE candidate; server adds viewer_id and forwards
		case TypeRTCIceViewer:
			var p struct {
				Candidate string `json:"candidate"`
				SDPMid    string `json:"sdp_mid"`
			}
			if err := json.Unmarshal(msg.Payload, &p); err != nil {
				continue
			}
			sendJSON(v.agent.send, TypeRTCIceViewer, map[string]string{
				"viewer_id": v.id,
				"candidate": p.Candidate,
				"sdp_mid":   p.SDPMid,
			})
		}
	}
}

func (v *Viewer) writePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		v.conn.Close()
	}()
	for {
		select {
		case msg, ok := <-v.send:
			v.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				v.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := v.conn.WriteMessage(websocket.TextMessage, msg); err != nil {
				return
			}
		case <-ticker.C:
			v.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := v.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// ── WebSocket handlers ────────────────────────────────────────────────────────

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024 * 1024,
	CheckOrigin:     func(r *http.Request) bool { return true },
}

func (h *Hub) handleAgent(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("[agent] upgrade: %v", err)
		return
	}

	// ── Step 1: send challenge ──────────────────────────────────────────────
	nonce := make([]byte, challengeSize)
	if _, err := rand.Read(nonce); err != nil {
		conn.Close()
		return
	}
	nonceHex := hex.EncodeToString(nonce)

	chalData := marshalMsg(TypeChallenge, ChallengePayload{Nonce: nonceHex})
	conn.SetWriteDeadline(time.Now().Add(writeWait))
	if err := conn.WriteMessage(websocket.TextMessage, chalData); err != nil {
		conn.Close()
		return
	}

	// ── Step 2: receive auth ────────────────────────────────────────────────
	conn.SetReadDeadline(time.Now().Add(30 * time.Second))
	_, data, err := conn.ReadMessage()
	if err != nil {
		conn.Close()
		return
	}

	var msg Message
	if err := json.Unmarshal(data, &msg); err != nil || msg.Type != TypeAuth {
		conn.Close()
		return
	}

	var auth AuthPayload
	if err := json.Unmarshal(msg.Payload, &auth); err != nil || auth.DeviceID == "" {
		conn.Close()
		return
	}

	if !h.verifyHMAC(auth.DeviceID, nonceHex, auth.HMAC) {
		log.Printf("[agent] auth failed for device %s", auth.DeviceID)
		replyErr(conn, "authentication failed")
		conn.Close()
		return
	}

	conn.SetReadDeadline(time.Time{})

	agent := &Agent{
		id:       auth.DeviceID,
		name:     auth.Name,
		platform: auth.Platform,
		conn:     conn,
		send:     make(chan []byte, 256),
		viewers:  make(map[string]*Viewer),
		hub:      h,
	}

	h.mu.Lock()
	if old, ok := h.agents[agent.id]; ok {
		old.close()
	}
	h.agents[agent.id] = agent
	h.mu.Unlock()

	log.Printf("[agent] registered: %s (%s) platform=%s", agent.id, agent.name, agent.platform)
	sendJSON(agent.send, TypeRegistered, map[string]any{
		"device_id":   agent.id,
		"ice_servers": h.iceServers,
	})

	go agent.writePump()
	agent.readPump()
}

func (h *Hub) handleViewer(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("[viewer] upgrade: %v", err)
		return
	}

	conn.SetReadDeadline(time.Now().Add(30 * time.Second))
	_, data, err := conn.ReadMessage()
	if err != nil {
		conn.Close()
		return
	}

	var msg Message
	if err := json.Unmarshal(data, &msg); err != nil || msg.Type != TypeConnect {
		conn.Close()
		return
	}

	var cp ConnectPayload
	if err := json.Unmarshal(msg.Payload, &cp); err != nil {
		conn.Close()
		return
	}

	if cp.Password != h.password {
		replyErr(conn, "invalid password")
		conn.Close()
		return
	}

	h.mu.RLock()
	agent, ok := h.agents[cp.DeviceID]
	h.mu.RUnlock()
	if !ok {
		replyErr(conn, "device not found or offline")
		conn.Close()
		return
	}

	conn.SetReadDeadline(time.Time{})

	viewer := &Viewer{
		id:    fmt.Sprintf("v-%s", randomHex(8)),
		conn:  conn,
		send:  make(chan []byte, 512),
		agent: agent,
	}

	sendJSON(viewer.send, TypeConnected, ConnectedPayload{
		DeviceID:   agent.id,
		Name:       agent.name,
		Platform:   agent.platform,
		ICEServers: h.iceServers,
	})

	agent.addViewer(viewer)
	log.Printf("[viewer] %s connected to agent %s", viewer.id, agent.id)

	go viewer.writePump()
	viewer.readPump()
}

func (h *Hub) handleDevices(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")

	h.mu.RLock()
	list := make([]DeviceInfo, 0, len(h.agents))
	for _, a := range h.agents {
		list = append(list, DeviceInfo{
			ID:          a.id,
			Name:        a.name,
			Platform:    a.platform,
			ViewerCount: a.viewerCount(),
		})
	}
	h.mu.RUnlock()

	json.NewEncoder(w).Encode(list)
}

// ── Helpers ───────────────────────────────────────────────────────────────────

func marshalMsg(msgType string, payload any) []byte {
	raw, _ := json.Marshal(payload)
	data, _ := json.Marshal(Message{Type: msgType, Payload: raw})
	return data
}

func sendJSON(ch chan []byte, msgType string, payload any) {
	defer func() { recover() }() // guard against send on closed channel
	select {
	case ch <- marshalMsg(msgType, payload):
	default:
	}
}

func replyErr(conn *websocket.Conn, msg string) {
	conn.SetWriteDeadline(time.Now().Add(writeWait))
	conn.WriteMessage(websocket.TextMessage, marshalMsg(TypeError, ErrorPayload{Message: msg}))
}

func randomHex(n int) string {
	b := make([]byte, n)
	rand.Read(b)
	return hex.EncodeToString(b)
}

// ── main ──────────────────────────────────────────────────────────────────────

func main() {
	// Load config file first so its values seed flag defaults.
	cfg, err := loadServerConfig(findConfigFlag())
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	configFile := flag.String("config", "", "path to YAML config file")
	addr := flag.String("addr", cfg.Addr, "listen address")
	password := flag.String("password", cfg.Password, "viewer connection password")
	tlsCert := flag.String("tls-cert", cfg.TLSCert, "TLS certificate file")
	tlsKey := flag.String("tls-key", cfg.TLSKey, "TLS key file")
	staticDir := flag.String("static", cfg.Static, "client build directory")
	turnURL := flag.String("turn-url", cfg.TURN.URL, "TURN server URL (e.g. turn:1.2.3.4:3478)")
	turnUser := flag.String("turn-user", cfg.TURN.User, "TURN username")
	turnCred := flag.String("turn-credential", cfg.TURN.Password, "TURN credential")
	flag.Parse()

	// If --config was given as a flag (not pre-scanned), reload to apply any
	// values that differ from the pre-scan path (edge case: flag after other args).
	if *configFile != "" && *configFile != findConfigFlag() {
		if cfg, err = loadServerConfig(*configFile); err != nil {
			log.Fatalf("config: %v", err)
		}
	}

	agentToken := cfg.AgentToken
	tokens := cfg.Tokens
	switch {
	case len(tokens) > 0:
		log.Printf("agent auth: per-device tokens (%d devices)", len(tokens))
	case agentToken != "":
		log.Println("agent auth: global agent_token (any device with correct token accepted)")
	default:
		log.Println("WARNING: no agent token configured — dev mode, all agents accepted")
	}

	iceServers := []ICEServerConfig{
		{URLs: []string{"stun:stun.l.google.com:19302"}},
	}
	if *turnURL != "" {
		iceServers = append(iceServers, ICEServerConfig{
			URLs:       []string{*turnURL},
			Username:   *turnUser,
			Credential: *turnCred,
		})
		log.Printf("TURN enabled: %s (user=%s)", *turnURL, *turnUser)
	}

	hub := newHub(*password, agentToken, tokens, iceServers)

	mux := http.NewServeMux()
	mux.HandleFunc("/ws/agent", hub.handleAgent)
	mux.HandleFunc("/ws/viewer", hub.handleViewer)
	mux.HandleFunc("/api/devices", hub.handleDevices)
	mux.Handle("/", http.FileServer(http.Dir(*staticDir)))

	srv := &http.Server{Addr: *addr, Handler: mux}

	// Graceful shutdown on SIGTERM / SIGINT
	go func() {
		quit := make(chan os.Signal, 1)
		signal.Notify(quit, syscall.SIGTERM, syscall.SIGINT)
		<-quit
		log.Println("shutting down...")
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		srv.Shutdown(ctx)
	}()

	log.Printf("remotectl server on %s", *addr)

	var listenErr error
	if *tlsCert != "" && *tlsKey != "" {
		log.Println("TLS enabled")
		listenErr = srv.ListenAndServeTLS(*tlsCert, *tlsKey)
	} else {
		log.Println("WARNING: TLS not configured — use --tls-cert / --tls-key in production")
		listenErr = srv.ListenAndServe()
	}
	if listenErr != nil && listenErr != http.ErrServerClosed {
		log.Fatal(listenErr)
	}
}
