// Package session implements per-viewer E2EE using ECDH P-256 + HKDF-SHA256 + AES-256-GCM.
//
// Protocol:
//  1. Agent receives viewer_joined → calls session.New(viewerID)
//  2. Agent sends key_offer{viewer_id, public_key} to server → relayed to viewer
//  3. Viewer sends key_answer{public_key} → relayed to agent as key_answer{viewer_id, public_key}
//  4. Agent calls session.Complete(peerPubKey) → derives AES-256-GCM key via HKDF
//  5. All subsequent frames encrypted per-viewer; input events decrypted per-viewer
//
// The relay server only sees ciphertext and can never derive the session key.
package session

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/ecdh"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"io"

	"golang.org/x/crypto/hkdf"
)

// Session holds cryptographic state for one viewer ↔ agent connection.
type Session struct {
	ViewerID   string
	privateKey *ecdh.PrivateKey
	gcm        cipher.AEAD
}

// New generates an ephemeral ECDH P-256 key pair for a new viewer session.
func New(viewerID string) (*Session, error) {
	priv, err := ecdh.P256().GenerateKey(rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("generate ecdh key: %w", err)
	}
	return &Session{ViewerID: viewerID, privateKey: priv}, nil
}

// PublicKeyBase64 returns the uncompressed public key bytes (65 bytes, 04||X||Y) as base64.
// This is the "raw" format expected by the browser Web Crypto API.
func (s *Session) PublicKeyBase64() string {
	return base64.StdEncoding.EncodeToString(s.privateKey.PublicKey().Bytes())
}

// Complete finalizes key exchange with the peer's raw P-256 public key (base64-encoded).
// After this, Encrypt and Decrypt are available.
func (s *Session) Complete(peerPubKeyB64 string) error {
	peerBytes, err := base64.StdEncoding.DecodeString(peerPubKeyB64)
	if err != nil {
		return fmt.Errorf("decode peer public key: %w", err)
	}
	peerKey, err := ecdh.P256().NewPublicKey(peerBytes)
	if err != nil {
		return fmt.Errorf("import peer public key: %w", err)
	}

	// ECDH shared secret (32-byte X coordinate of shared point)
	secret, err := s.privateKey.ECDH(peerKey)
	if err != nil {
		return fmt.Errorf("ecdh: %w", err)
	}

	// Derive 256-bit AES key via HKDF-SHA256
	// Both sides must use identical info string and zero salt
	hk := hkdf.New(sha256.New, secret, nil, []byte("remotectl-v1"))
	key := make([]byte, 32)
	if _, err = io.ReadFull(hk, key); err != nil {
		return fmt.Errorf("hkdf: %w", err)
	}

	block, err := aes.NewCipher(key)
	if err != nil {
		return fmt.Errorf("aes: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return fmt.Errorf("gcm: %w", err)
	}

	s.gcm = gcm
	// Wipe private key — no longer needed
	s.privateKey = nil
	return nil
}

// Ready reports whether key exchange has been completed.
func (s *Session) Ready() bool { return s.gcm != nil }

// Encrypt encrypts plaintext with AES-256-GCM.
// Output is base64(12-byte nonce || ciphertext || 16-byte tag).
func (s *Session) Encrypt(plaintext []byte) (string, error) {
	if !s.Ready() {
		return "", fmt.Errorf("session %s: key exchange not complete", s.ViewerID)
	}
	nonce := make([]byte, s.gcm.NonceSize()) // 12 bytes
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", err
	}
	sealed := s.gcm.Seal(nonce, nonce, plaintext, nil) // nonce prepended
	return base64.StdEncoding.EncodeToString(sealed), nil
}

// Decrypt decrypts a base64-encoded nonce||ciphertext produced by Encrypt (or the browser).
func (s *Session) Decrypt(enc string) ([]byte, error) {
	if !s.Ready() {
		return nil, fmt.Errorf("session %s: key exchange not complete", s.ViewerID)
	}
	data, err := base64.StdEncoding.DecodeString(enc)
	if err != nil {
		return nil, fmt.Errorf("base64 decode: %w", err)
	}
	ns := s.gcm.NonceSize()
	if len(data) < ns+s.gcm.Overhead() {
		return nil, fmt.Errorf("ciphertext too short")
	}
	return s.gcm.Open(nil, data[:ns], data[ns:], nil)
}
