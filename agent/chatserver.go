package main

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"runtime"
	"strings"
	"sync"
	"time"

	_ "embed"

	"github.com/gorilla/websocket"
)

//go:embed chat.html
var chatHTMLBytes []byte

// chatMsgWire is the JSON message exchanged between the agent HTTP server and
// the browser chat page over WebSocket.
type chatMsgWire struct {
	Type    string `json:"type"`              // "text" | "file"
	From    string `json:"from"`              // "viewer" | "agent"
	Text    string `json:"text,omitempty"`
	Name    string `json:"name,omitempty"`
	Mime    string `json:"mime,omitempty"`
	Size    int64  `json:"size,omitempty"`
	FileURL string `json:"fileURL,omitempty"` // relative URL served by this HTTP server
	Ts      int64  `json:"ts"`
}

type chatWSClient struct {
	conn *websocket.Conn
	send chan []byte
}

// chatServer serves the browser chat UI and relays messages to/from the
// DataChannel layer via the sendToViewers callback.
//
// Security: all routes are prefixed with a random per-session token so that
// other processes on the same machine cannot sniff messages by simply hitting
// http://localhost:17770. The token changes every time the agent restarts.
const chatHistoryCap = 50

type chatServer struct {
	port          int
	secret        string // random hex token, part of every URL
	mu            sync.Mutex
	clients       map[*chatWSClient]struct{}
	history       []chatMsgWire // recent messages replayed to newly-connected browsers
	sendToViewers func(data []byte) // set by the Agent after construction
}

func newChatServer(port int) *chatServer {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		panic("rand: " + err.Error())
	}
	return &chatServer{
		port:    port,
		secret:  hex.EncodeToString(b),
		clients: make(map[*chatWSClient]struct{}),
	}
}

// URL returns the full URL a user should open to access the chat page.
func (s *chatServer) URL() string {
	return fmt.Sprintf("http://localhost:%d/%s", s.port, s.secret)
}

func (s *chatServer) start() {
	mux := http.NewServeMux()
	// All routes gated behind the secret token as the first path segment.
	mux.HandleFunc("/", s.route)

	srv := &http.Server{
		Addr:    fmt.Sprintf("127.0.0.1:%d", s.port),
		Handler: mux,
	}
	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Printf("[chat] server error: %v", err)
		}
	}()
}

// route validates the secret token and dispatches to the right handler.
// URL structure:
//
//	/<secret>           → chat.html
//	/<secret>/ws        → WebSocket
//	/<secret>/files/... → file download
func (s *chatServer) route(w http.ResponseWriter, r *http.Request) {
	// Strip leading slash and split into segments.
	path := strings.TrimPrefix(r.URL.Path, "/")
	parts := strings.SplitN(path, "/", 3)

	// First segment must be the secret token.
	if len(parts) == 0 || parts[0] != s.secret {
		http.NotFound(w, r)
		return
	}

	sub := ""
	if len(parts) > 1 {
		sub = parts[1]
	}

	switch sub {
	case "", "index.html":
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Header().Set("Cache-Control", "no-cache")
		w.Write(chatHTMLBytes) //nolint:errcheck
	case "ws":
		s.handleWS(w, r)
	case "files":
		encoded := ""
		if len(parts) > 2 {
			encoded = parts[2]
		}
		s.serveFile(w, r, encoded)
	default:
		http.NotFound(w, r)
	}
}

var wsUpgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

func (s *chatServer) handleWS(w http.ResponseWriter, r *http.Request) {
	conn, err := wsUpgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	client := &chatWSClient{conn: conn, send: make(chan []byte, 128)}
	s.mu.Lock()
	s.clients[client] = struct{}{}
	// Replay recent history so the browser sees messages sent before it connected.
	for _, msg := range s.history {
		data, _ := json.Marshal(msg)
		select {
		case client.send <- data:
		default:
		}
	}
	s.mu.Unlock()

	go client.writePump()
	go s.readPump(client)
}

func (c *chatWSClient) writePump() {
	defer c.conn.Close()
	for data := range c.send {
		c.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
		if err := c.conn.WriteMessage(websocket.TextMessage, data); err != nil {
			return
		}
	}
}

func (s *chatServer) readPump(client *chatWSClient) {
	defer func() {
		s.mu.Lock()
		delete(s.clients, client)
		s.mu.Unlock()
		close(client.send)
		client.conn.Close()
	}()
	for {
		_, data, err := client.conn.ReadMessage()
		if err != nil {
			return
		}
		var m map[string]interface{}
		if json.Unmarshal(data, &m) != nil {
			continue
		}
		switch m["type"] {
		case "text":
			text, _ := m["text"].(string)
			if text == "" {
				continue
			}
			// Forward to all connected viewers via DataChannel.
			if s.sendToViewers != nil {
				wire := map[string]interface{}{
					"type": "text",
					"id":   fmt.Sprintf("%016x", time.Now().UnixNano()),
					"text": text,
					"ts":   time.Now().UnixMilli(),
				}
				dcData, _ := json.Marshal(wire)
				s.sendToViewers(dcData)
			}
			// Echo the outgoing message back to all browser clients (including sender).
			s.broadcast(chatMsgWire{
				Type: "text",
				From: "agent",
				Text: text,
				Ts:   time.Now().UnixMilli(),
			})

		case "file_send":
			name, _ := m["name"].(string)
			mime, _ := m["mime"].(string)
			sizeF, _ := m["size"].(float64)
			dataB64, _ := m["data"].(string)
			if name == "" || dataB64 == "" {
				continue
			}
			go s.relayFileToDC(name, mime, int64(sizeF), dataB64)
		}
	}
}

// push delivers a message to all connected browser clients and stores it in
// the history buffer so late-connecting browsers can replay recent messages.
func (s *chatServer) push(msg chatMsgWire) {
	if msg.Ts == 0 {
		msg.Ts = time.Now().UnixMilli()
	}
	s.mu.Lock()
	s.history = append(s.history, msg)
	if len(s.history) > chatHistoryCap {
		s.history = s.history[len(s.history)-chatHistoryCap:]
	}
	s.mu.Unlock()
	s.broadcast(msg)
}

func (s *chatServer) broadcast(msg chatMsgWire) {
	data, _ := json.Marshal(msg)
	s.mu.Lock()
	for c := range s.clients {
		select {
		case c.send <- data:
		default:
		}
	}
	s.mu.Unlock()
}

// hasClients reports whether at least one browser tab has the chat page open.
func (s *chatServer) hasClients() bool {
	s.mu.Lock()
	n := len(s.clients)
	s.mu.Unlock()
	return n > 0
}

// openBrowser opens the chat page (including secret token) in the default browser.
func (s *chatServer) openBrowser() {
	u := s.URL()
	var cmd string
	var args []string
	switch runtime.GOOS {
	case "darwin":
		cmd, args = "open", []string{u}
	case "windows":
		// Use PowerShell Start-Process so no CMD window flashes.
		// hiddenCmd sets CREATE_NO_WINDOW at the process level.
		cmd, args = "powershell", []string{"-WindowStyle", "Hidden", "-NonInteractive", "-Command", "Start-Process '" + u + "'"}
	default:
		cmd, args = "xdg-open", []string{u}
	}
	hiddenCmd(cmd, args...).Start() //nolint:errcheck
}

// serveFile serves a file at an absolute path that was previously saved by the agent.
// encoded is the url.PathEscape'd absolute path from the URL.
func (s *chatServer) serveFile(w http.ResponseWriter, r *http.Request, encoded string) {
	if encoded == "" {
		http.NotFound(w, r)
		return
	}
	path, err := url.PathUnescape(encoded)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	http.ServeFile(w, r, path)
}

// fileURL returns the token-prefixed URL for the given absolute file path.
func (s *chatServer) fileURL(absPath string) string {
	return fmt.Sprintf("/%s/files/%s", s.secret, url.PathEscape(absPath))
}

// relayFileToDC decodes base64 file data received from the browser and
// forwards it to all connected viewers as file_start + file_chunk messages.
func (s *chatServer) relayFileToDC(name, mime string, size int64, dataB64 string) {
	if s.sendToViewers == nil {
		return
	}
	data, err := base64.StdEncoding.DecodeString(dataB64)
	if err != nil {
		log.Printf("[chat] relayFileToDC decode error: %v", err)
		return
	}

	// Generate a random file ID.
	b := make([]byte, 8)
	rand.Read(b) //nolint:errcheck
	id := hex.EncodeToString(b)

	start, _ := json.Marshal(map[string]interface{}{
		"type": "file_start",
		"id":   id,
		"name": name,
		"size": size,
		"mime": mime,
	})
	s.sendToViewers(start)

	const chunkSize = 12 * 1024
	for i, seq := 0, 0; i < len(data); i += chunkSize {
		end := i + chunkSize
		if end > len(data) {
			end = len(data)
		}
		isLast := end >= len(data)
		chunk, _ := json.Marshal(map[string]interface{}{
			"type": "file_chunk",
			"id":   id,
			"seq":  seq,
			"data": base64.StdEncoding.EncodeToString(data[i:end]),
			"last": isLast,
		})
		s.sendToViewers(chunk)
		seq++
		// Yield between chunks so the SCTP send goroutine can drain the buffer.
		time.Sleep(time.Millisecond)
	}
	log.Printf("[chat] relayed file to viewers: %s (%d bytes)", name, len(data))
}
