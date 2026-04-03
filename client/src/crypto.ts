/**
 * E2EE utilities using the browser Web Crypto API.
 *
 * Key agreement: ECDH P-256
 * Key derivation: ECDH bits → HKDF-SHA-256 (info = "remotectl-v1") → AES-256-GCM key
 * Encryption:    AES-256-GCM, 12-byte random nonce prepended to ciphertext
 *
 * This matches the Go implementation in agent/session/session.go exactly.
 */

const HKDF_INFO = new TextEncoder().encode('remotectl-v1')
const AES_KEY_LEN = 256

/** An ephemeral ECDH key pair for one session. */
export interface ECDHKeyPair {
  publicKey: CryptoKey
  privateKey: CryptoKey
}

/** Generate an ephemeral ECDH P-256 key pair. */
export async function generateKeyPair(): Promise<ECDHKeyPair> {
  return crypto.subtle.generateKey(
    { name: 'ECDH', namedCurve: 'P-256' },
    true,
    ['deriveBits'],
  ) as Promise<ECDHKeyPair>
}

/**
 * Export the public key as a base64-encoded uncompressed point (04 || X || Y, 65 bytes).
 * This format is what Go's crypto/ecdh PublicKey.Bytes() returns for P-256.
 */
export async function exportPublicKey(keyPair: ECDHKeyPair): Promise<string> {
  const raw = await crypto.subtle.exportKey('raw', keyPair.publicKey)
  return bufToBase64(raw)
}

/**
 * Import a peer's raw P-256 public key from base64 (uncompressed, 65 bytes).
 */
async function importPeerPublicKey(b64: string): Promise<CryptoKey> {
  const raw = base64ToBuf(b64)
  return crypto.subtle.importKey(
    'raw',
    raw,
    { name: 'ECDH', namedCurve: 'P-256' },
    false,
    [],
  )
}

/**
 * Derive an AES-256-GCM session key from our private key and the peer's public key.
 * Uses HKDF-SHA-256 for key derivation, matching the Go HKDF step.
 */
export async function deriveSessionKey(
  myKeyPair: ECDHKeyPair,
  peerPublicKeyB64: string,
): Promise<CryptoKey> {
  const peerKey = await importPeerPublicKey(peerPublicKeyB64)

  // ECDH → 256 raw bits (X coordinate of shared point)
  const sharedBits = await crypto.subtle.deriveBits(
    { name: 'ECDH', public: peerKey },
    myKeyPair.privateKey,
    256,
  )

  // Import shared bits as HKDF key material
  const hkdfKey = await crypto.subtle.importKey(
    'raw',
    sharedBits,
    'HKDF',
    false,
    ['deriveKey'],
  )

  // HKDF-SHA-256 → AES-256-GCM key (zero salt, info = "remotectl-v1")
  return crypto.subtle.deriveKey(
    {
      name: 'HKDF',
      hash: 'SHA-256',
      salt: new Uint8Array(0),
      info: HKDF_INFO,
    },
    hkdfKey,
    { name: 'AES-GCM', length: AES_KEY_LEN },
    false,
    ['encrypt', 'decrypt'],
  )
}

/**
 * Encrypt plaintext bytes with AES-256-GCM.
 * Returns base64(12-byte nonce || ciphertext || 16-byte tag).
 */
export async function encrypt(key: CryptoKey, plaintext: Uint8Array): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12))
  const ciphertext = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, toArrayBuffer(plaintext))
  // Prepend nonce
  const out = new Uint8Array(iv.byteLength + ciphertext.byteLength)
  out.set(iv, 0)
  out.set(new Uint8Array(ciphertext), iv.byteLength)
  return bufToBase64(out.buffer)
}

/**
 * Decrypt a base64-encoded nonce||ciphertext produced by encrypt() or the Go agent.
 */
export async function decrypt(key: CryptoKey, b64: string): Promise<Uint8Array> {
  const data = new Uint8Array(base64ToBuf(b64))
  if (data.length < 12 + 16) throw new Error('ciphertext too short')
  const iv = data.slice(0, 12)
  const ciphertext = data.slice(12)
  const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv }, key, ciphertext)
  return new Uint8Array(plain)
}

// ── Internal helpers ──────────────────────────────────────────────────────────

/**
 * Ensure a Uint8Array is backed by a plain ArrayBuffer (not SharedArrayBuffer).
 * Web Crypto APIs require ArrayBuffer, not ArrayBufferLike.
 */
function toArrayBuffer(arr: Uint8Array): ArrayBuffer {
  return arr.buffer.slice(arr.byteOffset, arr.byteOffset + arr.byteLength) as ArrayBuffer
}

function bufToBase64(buf: ArrayBuffer): string {
  const bytes = new Uint8Array(buf)
  let binary = ''
  for (let i = 0; i < bytes.byteLength; i++) binary += String.fromCharCode(bytes[i])
  return btoa(binary)
}

function base64ToBuf(b64: string): ArrayBuffer {
  const binary = atob(b64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return bytes.buffer
}
