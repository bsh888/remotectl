package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os/exec"
	"runtime"
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
type chatServer struct {
	port          int
	mu            sync.Mutex
	clients       map[*chatWSClient]struct{}
	history       []chatMsgWire
	sendToViewers func(data []byte) // set by the Agent after construction
}

func newChatServer(port int) *chatServer {
	return &chatServer{
		port:    port,
		clients: make(map[*chatWSClient]struct{}),
	}
}

func (s *chatServer) start() {
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Header().Set("Cache-Control", "no-cache")
		w.Write(chatHTMLBytes)
	})
	mux.HandleFunc("/ws", s.handleWS)
	mux.HandleFunc("/files/", s.handleFile)

	srv := &http.Server{
		Addr:    fmt.Sprintf("127.0.0.1:%d", s.port),
		Handler: mux,
	}
	go func() {
		log.Printf("[chat] UI available at http://localhost:%d", s.port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Printf("[chat] server error: %v", err)
		}
	}()
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
	// replay history so the page shows previous messages on reconnect/refresh
	history := make([]chatMsgWire, len(s.history))
	copy(history, s.history)
	s.mu.Unlock()

	for _, msg := range history {
		if data, err := json.Marshal(msg); err == nil {
			client.send <- data
		}
	}

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
		if m["type"] != "text" {
			continue
		}
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
		// Echo the outgoing message to all browser clients (including sender).
		s.push(chatMsgWire{
			Type: "text",
			From: "agent",
			Text: text,
			Ts:   time.Now().UnixMilli(),
		})
	}
}

// push stores a message in history and broadcasts it to all connected browser clients.
func (s *chatServer) push(msg chatMsgWire) {
	if msg.Ts == 0 {
		msg.Ts = time.Now().UnixMilli()
	}
	data, _ := json.Marshal(msg)
	s.mu.Lock()
	s.history = append(s.history, msg)
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

// openBrowser opens the chat page in the system default browser.
func (s *chatServer) openBrowser() {
	u := fmt.Sprintf("http://localhost:%d", s.port)
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("open", u)
	case "windows":
		cmd = exec.Command("cmd", "/c", "start", u)
	default: // linux
		cmd = exec.Command("xdg-open", u)
	}
	cmd.Start() //nolint:errcheck
}

// handleFile serves files from the Downloads directory.
// URL pattern: /files/<url-encoded-absolute-path>
func (s *chatServer) handleFile(w http.ResponseWriter, r *http.Request) {
	encoded := r.URL.Path[len("/files/"):]
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

// fileURL returns the relative URL under which the given absolute path will be
// served by handleFile.
func fileURL(absPath string) string {
	return "/files/" + url.PathEscape(absPath)
}
