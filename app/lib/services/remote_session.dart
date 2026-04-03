import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart' as ws_io;
import 'crypto_service.dart';

enum SessionState { idle, connecting, connected, error }

class DeviceInfo {
  final String id;
  final String name;
  final String platform;
  final int viewerCount;

  const DeviceInfo({
    required this.id,
    required this.name,
    required this.platform,
    required this.viewerCount,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> j) => DeviceInfo(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? j['id'] as String,
        platform: (j['platform'] as String?) ?? '',
        viewerCount: (j['viewer_count'] as int?) ?? 0,
      );
}

class RemoteSession extends ChangeNotifier {
  SessionState _state = SessionState.idle;
  String _error = '';
  RTCVideoRenderer? _renderer;
  List<DeviceInfo> _devices = [];

  SessionState get state => _state;
  String get error => _error;
  RTCVideoRenderer? get renderer => _renderer;
  List<DeviceInfo> get devices => _devices;

  WebSocketChannel? _ws;
  RTCPeerConnection? _pc;
  RTCDataChannel? _inputDC;      // reliable+ordered: clicks, keys, scroll, paste
  RTCDataChannel? _inputMoveDC;  // unreliable+unordered: mousemove only
  bool _inputDCOpen = false;
  bool _inputMoveDCOpen = false;
  final _crypto = CryptoService();
  List<Map<String, dynamic>> _iceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
  ];

  // ── connect ──────────────────────────────────────────────────────────────────

  Future<void> connect({
    required String serverURL,
    required String deviceID,
    required String password,
    bool allowSelfSigned = false,
  }) async {
    await disconnect();
    _setState(SessionState.connecting);
    _error = '';

    try {
      final uri = _wsUri(serverURL);
      final WebSocketChannel ws;
      if (allowSelfSigned) {
        ws = ws_io.IOWebSocketChannel.connect(uri, customClient: _buildInsecureClient());
      } else {
        ws = WebSocketChannel.connect(uri);
      }
      _ws = ws;

      ws.sink.add(jsonEncode({
        'type': 'connect',
        'payload': {'device_id': deviceID, 'password': password},
      }));

      ws.stream.listen(
        (raw) => _onMessage(raw as String),
        onError: (e) => _setError('WebSocket error: $e'),
        onDone: () {
          // WebSocket closing is normal once WebRTC negotiation has started (_pc != null).
          // Only treat it as an error if no peer connection was ever created.
          if (_state == SessionState.connecting && _pc == null) {
            _setError('WebSocket closed unexpectedly');
          }
        },
      );
    } catch (e) {
      _setError('Connect failed: $e');
    }
  }

  Future<void> disconnect() async {
    _inputDC?.close();
    _inputDC = null;
    _inputDCOpen = false;
    _inputMoveDC?.close();
    _inputMoveDC = null;
    _inputMoveDCOpen = false;
    await _pc?.close();
    _pc = null;
    _ws?.sink.close();
    _ws = null;
    _iceServers = [{'urls': 'stun:stun.l.google.com:19302'}];
    final r = _renderer;
    _renderer = null;
    r?.srcObject = null;
    await r?.dispose();
    if (_state != SessionState.idle) {
      _setState(SessionState.idle);
    }
  }

  // ── sendInput ─────────────────────────────────────────────────────────────────

  Future<void> sendInput(Map<String, dynamic> ev) async {
    final event = ev['event'] as String?;
    // mousemove goes through the unreliable channel — stale positions are
    // worthless and retransmitting them only adds latency.
    final isMove = event == 'mousemove';

    // Prefer DataChannel (P2P, low latency). Use the tracked _open flags instead
    // of dc.state — flutter_webrtc updates state asynchronously via method
    // channels, so dc.state may still read "connecting" even when the native
    // channel is already open.
    if (isMove) {
      final dc = _inputMoveDCOpen ? _inputMoveDC : (_inputDCOpen ? _inputDC : null);
      if (dc != null) {
        try { dc.send(RTCDataChannelMessage(jsonEncode(ev))); return; } catch (_) {}
      }
    } else {
      if (_inputDCOpen && _inputDC != null) {
        try { _inputDC!.send(RTCDataChannelMessage(jsonEncode(ev))); return; } catch (_) {}
      }
    }

    // Fallback: E2EE over WebSocket
    final ws = _ws;
    if (ws == null || !_crypto.hasSessionKey) return;
    try {
      final plaintext = utf8.encode(jsonEncode(ev));
      final data = await _crypto.encrypt(Uint8List.fromList(plaintext));
      ws.sink.add(jsonEncode({'type': 'input_enc', 'payload': {'data': data}}));
    } catch (_) {}
  }

  // ── fetchDevices ─────────────────────────────────────────────────────────────

  Future<void> fetchDevices(String serverURL, {bool allowSelfSigned = false}) async {
    try {
      final uri = Uri.parse(serverURL).replace(path: '/api/devices');
      final client = HttpClient();
      if (allowSelfSigned) {
        client.badCertificateCallback = (cert, host, port) => true;
      }
      final req = await client.getUrl(uri);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      client.close();
      final list = jsonDecode(body) as List<dynamic>;
      _devices = list
          .map((e) => DeviceInfo.fromJson(e as Map<String, dynamic>))
          .toList();
      notifyListeners();
    } catch (_) {
      _devices = [];
      notifyListeners();
    }
  }

  // ── WebSocket message handler ─────────────────────────────────────────────────

  Future<void> _onMessage(String raw) async {
    final msg = jsonDecode(raw) as Map<String, dynamic>;
    final type = msg['type'] as String;
    final payload = msg['payload'] as Map<String, dynamic>?;

    switch (type) {
      case 'connected':
        // Store ICE servers (includes TURN if configured on the relay)
        final rawICE = payload?['ice_servers'] as List<dynamic>?;
        if (rawICE != null && rawICE.isNotEmpty) {
          _iceServers = rawICE.cast<Map<String, dynamic>>();
        }
        break;
      case 'key_offer':
        await _handleKeyOffer(payload!);
      case 'rtc_offer':
        await _handleRtcOffer(payload!);
      case 'rtc_ice_agent':
        await _handleIceAgent(payload!);
      case 'agent_offline':
        _setError('Agent disconnected');
      case 'error':
        _setError((payload?['message'] as String?) ?? 'Unknown server error');
    }
  }

  Future<void> _handleKeyOffer(Map<String, dynamic> payload) async {
    try {
      final peerPubKey = payload['public_key'] as String;
      final myPubKey = await _crypto.generateKeyPair();
      await _crypto.deriveSessionKey(peerPubKey);
      _ws!.sink.add(jsonEncode({
        'type': 'key_answer',
        'payload': {'public_key': myPubKey},
      }));
    } catch (e) {
      // Key exchange only protects the WebSocket input fallback path.
      // WebRTC DataChannel (primary path) works without it — don't fail
      // the whole session, just disable the fallback and send an empty answer
      // so the server can continue to the rtc_offer step.
      debugPrint('[remotectl] key exchange failed (WS fallback disabled): $e');
      _ws?.sink.add(jsonEncode({
        'type': 'key_answer',
        'payload': {'public_key': ''},
      }));
    }
  }

  Future<void> _handleRtcOffer(Map<String, dynamic> payload) async {
    try {
      final sdp = payload['sdp'] as String;

      final pc = await createPeerConnection({'iceServers': _iceServers});
      _pc = pc;

      final renderer = RTCVideoRenderer();
      await renderer.initialize();
      _renderer = renderer;

      pc.onIceCandidate = (candidate) {
        _ws?.sink.add(jsonEncode({
          'type': 'rtc_ice_viewer',
          'payload': {
            'candidate': candidate.candidate ?? '',
            'sdp_mid': candidate.sdpMid ?? '',
          },
        }));
      };

      pc.onDataChannel = (channel) {
        if (channel.label == 'input') {
          _inputDC = channel;
          // flutter_webrtc updates channel.state asynchronously — track open
          // state explicitly via the state callback instead of reading .state.
          _inputDCOpen = channel.state == RTCDataChannelState.RTCDataChannelOpen;
          channel.onDataChannelState = (state) {
            _inputDCOpen = state == RTCDataChannelState.RTCDataChannelOpen;
          };
        } else if (channel.label == 'input-move') {
          _inputMoveDC = channel;
          _inputMoveDCOpen = channel.state == RTCDataChannelState.RTCDataChannelOpen;
          channel.onDataChannelState = (state) {
            _inputMoveDCOpen = state == RTCDataChannelState.RTCDataChannelOpen;
          };
        }
      };

      pc.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          _renderer?.srcObject = event.streams[0];
          _setState(SessionState.connected);
        }
      };

      pc.onConnectionState = (s) {
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            s == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          if (_state == SessionState.connected) {
            _setError('WebRTC connection failed');
          }
        }
      };

      await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);

      _ws?.sink.add(jsonEncode({
        'type': 'rtc_answer',
        'payload': {'sdp': answer.sdp},
      }));
    } catch (e) {
      _setError('WebRTC setup failed: $e');
    }
  }

  Future<void> _handleIceAgent(Map<String, dynamic> payload) async {
    final pc = _pc;
    if (pc == null) return;
    try {
      final candidate = payload['candidate'] as String;
      final sdpMid = payload['sdp_mid'] as String;
      await pc.addCandidate(RTCIceCandidate(candidate, sdpMid, 0));
    } catch (_) {}
  }

  // ── helpers ──────────────────────────────────────────────────────────────────

  void _setState(SessionState s) {
    _state = s;
    notifyListeners();
  }

  void _setError(String msg) {
    _error = msg;
    _state = SessionState.error;
    notifyListeners();
  }

  static Uri _wsUri(String serverURL) {
    final u = Uri.parse(serverURL);
    return u.replace(
      scheme: u.scheme == 'https' ? 'wss' : 'ws',
      path: '/ws/viewer',
    );
  }

  static HttpClient _buildInsecureClient() {
    final client = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;
    return client;
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
