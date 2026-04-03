/// E2EE for the WebSocket fallback path.
///
/// Key agreement:  ECDH P-256
/// Key derivation: shared-secret → HKDF-SHA-256 (salt=empty, info="remotectl-v1") → 32-byte AES key
/// Encryption:     AES-256-GCM, 12-byte nonce prepended to ciphertext+tag
///
/// Matches crypto.ts and the Go agent implementation exactly.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class CryptoService {
  static final _ecdhAlgo = Ecdh.p256(length: 32);
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final _aesGcm = AesGcm.with256bits(nonceLength: 12);

  EcKeyPair? _keyPair;
  SecretKey? _sessionKey;

  bool get hasSessionKey => _sessionKey != null;

  /// Generate ephemeral key pair. Returns base64(04‖X‖Y) — the 65-byte
  /// uncompressed P-256 public key expected by the Go agent.
  Future<String> generateKeyPair() async {
    _keyPair = await _ecdhAlgo.newKeyPair();
    final pub = await _keyPair!.extractPublicKey() as EcPublicKey;
    final raw = _buildUncompressedPoint(pub);
    return base64Encode(raw);
  }

  /// Derive AES-256-GCM session key from the agent's base64 public key.
  Future<void> deriveSessionKey(String peerPubKeyB64) async {
    final kp = _keyPair;
    if (kp == null) throw StateError('generateKeyPair() must be called first');

    final peerBytes = base64Decode(peerPubKeyB64);
    if (peerBytes.length != 65 || peerBytes[0] != 0x04) {
      throw ArgumentError('expected 65-byte uncompressed P-256 point');
    }

    final peerPub = EcPublicKey(
      x: peerBytes.sublist(1, 33),
      y: peerBytes.sublist(33, 65),
      type: KeyPairType.p256,
    );

    // ECDH → 32-byte shared secret (X coordinate of shared point)
    final sharedBits = await _ecdhAlgo.sharedSecretKey(
      keyPair: kp,
      remotePublicKey: peerPub,
    );

    // HKDF-SHA-256: salt = empty, info = "remotectl-v1"
    _sessionKey = await _hkdf.deriveKey(
      secretKey: sharedBits,
      nonce: const <int>[], // empty salt
      info: utf8.encode('remotectl-v1'),
    );
  }

  /// Encrypt [plaintext] with AES-256-GCM.
  /// Returns base64(12-byte nonce ‖ ciphertext ‖ 16-byte GCM tag).
  Future<String> encrypt(Uint8List plaintext) async {
    final key = _sessionKey;
    if (key == null) throw StateError('deriveSessionKey() must be called first');

    final nonce = _randomBytes(12);
    final box = await _aesGcm.encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
    );

    final out = Uint8List(12 + box.cipherText.length + box.mac.bytes.length);
    out.setRange(0, 12, nonce);
    out.setRange(12, 12 + box.cipherText.length, box.cipherText);
    out.setRange(12 + box.cipherText.length, out.length, box.mac.bytes);
    return base64Encode(out);
  }

  // ── helpers ──────────────────────────────────────────────────────────────────

  static Uint8List _buildUncompressedPoint(EcPublicKey pub) {
    final xBytes = _padTo32(pub.x);
    final yBytes = _padTo32(pub.y);
    final out = Uint8List(65);
    out[0] = 0x04;
    out.setRange(1, 33, xBytes);
    out.setRange(33, 65, yBytes);
    return out;
  }

  static Uint8List _padTo32(List<int> bytes) {
    if (bytes.length == 32) return Uint8List.fromList(bytes);
    final out = Uint8List(32);
    final start = 32 - bytes.length;
    out.setRange(start, 32, bytes);
    return out;
  }

  static Uint8List _randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
  }
}
