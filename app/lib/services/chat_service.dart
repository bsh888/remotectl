import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path_provider/path_provider.dart';

// ── Message models ─────────────────────────────────────────────────────────────

enum ChatSender { viewer, agent }

enum ChatMsgType { text, file, voice }

class ChatMessage {
  final String id;
  final ChatSender sender;
  final ChatMsgType type;
  final DateTime timestamp;

  // text
  final String? text;

  // file / voice
  final String? fileName;
  final int? fileSize;
  final String? mimeType;
  String? localPath; // populated once inbound transfer completes
  double progress;   // 0..1
  bool hasError;

  ChatMessage._({
    required this.id,
    required this.sender,
    required this.type,
    required this.timestamp,
    this.text,
    this.fileName,
    this.fileSize,
    this.mimeType,
    this.localPath,
    this.progress = 0,
    this.hasError = false,
  });

  factory ChatMessage.text({
    required String id,
    required ChatSender sender,
    required String text,
    DateTime? timestamp,
  }) =>
      ChatMessage._(
        id: id,
        sender: sender,
        type: ChatMsgType.text,
        text: text,
        progress: 1.0,
        timestamp: timestamp ?? DateTime.now(),
      );

  factory ChatMessage.transfer({
    required String id,
    required ChatSender sender,
    required ChatMsgType type,
    required String fileName,
    required int fileSize,
    required String mimeType,
    String? localPath,
    DateTime? timestamp,
  }) =>
      ChatMessage._(
        id: id,
        sender: sender,
        type: type,
        fileName: fileName,
        fileSize: fileSize,
        mimeType: mimeType,
        localPath: localPath,
        timestamp: timestamp ?? DateTime.now(),
      );
}

// ── In-flight inbound file ─────────────────────────────────────────────────────

class _InboundFile {
  final String name;
  final int size;
  final String mime;
  final BytesBuilder buf = BytesBuilder(copy: false);

  _InboundFile({required this.name, required this.size, required this.mime});
}

// ── ChatService ────────────────────────────────────────────────────────────────

// DataChannel chunk size: 12 KB payload → ~16 KB after base64 encoding.
// Stays well under the SCTP message-size limit (~64 KB) on all platforms.
const int _kChunkSize = 12 * 1024;

// Back-pressure threshold: pause sending when the DataChannel send buffer
// exceeds this many bytes. Without this, large files flood the SCTP buffer
// and chunks are silently dropped (causing the transfer to stall).
const int _kHighWaterMark = 256 * 1024; // 256 KB

class ChatService extends ChangeNotifier {
  final List<ChatMessage> _messages = [];
  RTCDataChannel? _dc;
  bool _dcOpen = false;
  final Map<String, _InboundFile> _inbound = {};
  int _unreadCount = 0;
  bool _panelOpen = false;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isOpen => _dcOpen;
  int get unreadCount => _unreadCount;
  bool get panelOpen => _panelOpen;

  // ── Panel state ───────────────────────────────────────────────────────────

  void setPanelOpen(bool open) {
    _panelOpen = open;
    if (open) _unreadCount = 0;
    notifyListeners();
  }

  // ── Attach / detach DataChannel ───────────────────────────────────────────

  void attach(RTCDataChannel dc) {
    _dc = dc;
    _dcOpen = dc.state == RTCDataChannelState.RTCDataChannelOpen;
    dc.onDataChannelState = (state) {
      _dcOpen = state == RTCDataChannelState.RTCDataChannelOpen;
      notifyListeners();
    };
    dc.onMessage = (RTCDataChannelMessage msg) {
      if (!msg.isBinary) _handleIncoming(msg.text);
    };
  }

  void detach() {
    _dc = null;
    _dcOpen = false;
    _inbound.clear();
    notifyListeners();
  }

  // ── Send text ─────────────────────────────────────────────────────────────

  Future<void> sendText(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final id = _uuid();
    _messages.add(ChatMessage.text(id: id, sender: ChatSender.viewer, text: t));
    notifyListeners();
    _sendRaw({'type': 'text', 'id': id, 'text': t, 'ts': DateTime.now().millisecondsSinceEpoch});
  }

  // ── Send file ─────────────────────────────────────────────────────────────

  Future<void> sendFile(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) return;
    final name = file.uri.pathSegments.last;
    final data = await file.readAsBytes();
    final mime = _guessMime(name);
    final type = mime.startsWith('audio/') ? ChatMsgType.voice : ChatMsgType.file;
    await _sendBytes(data: data, name: name, mime: mime, type: type);
  }

  Future<void> sendVoice(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) return;
    final name = file.uri.pathSegments.last;
    final data = await file.readAsBytes();
    await _sendBytes(data: data, name: name, mime: 'audio/m4a', type: ChatMsgType.voice);
  }

  Future<void> _sendBytes({
    required Uint8List data,
    required String name,
    required String mime,
    required ChatMsgType type,
  }) async {
    final id = _uuid();
    final msg = ChatMessage.transfer(
      id: id,
      sender: ChatSender.viewer,
      type: type,
      fileName: name,
      fileSize: data.length,
      mimeType: mime,
    );
    _messages.add(msg);
    notifyListeners();

    if (!_dcOpen || _dc == null) {
      msg.hasError = true;
      notifyListeners();
      return;
    }

    _sendRaw({'type': 'file_start', 'id': id, 'name': name, 'size': data.length, 'mime': mime});

    int offset = 0;
    int seq = 0;
    while (offset < data.length) {
      // Back-pressure: wait until the DataChannel send buffer drains below the
      // high-water mark. Without this, all chunks are queued immediately and
      // large files overflow the SCTP buffer, causing silent chunk drops.
      for (var waited = 0; waited < 500; waited++) {
        if (!_dcOpen || _dc == null) break;
        if ((_dc!.bufferedAmount) <= _kHighWaterMark) break;
        await Future.delayed(const Duration(milliseconds: 10));
      }

      if (!_dcOpen || _dc == null) {
        msg.hasError = true;
        notifyListeners();
        return;
      }

      final end = (offset + _kChunkSize).clamp(0, data.length);
      final chunk = data.sublist(offset, end);
      final isLast = end >= data.length;
      final ok = _sendRaw({
        'type': 'file_chunk',
        'id': id,
        'seq': seq++,
        'data': base64.encode(chunk),
        'last': isLast,
      });
      if (!ok) {
        msg.hasError = true;
        notifyListeners();
        return;
      }
      offset = end;
      msg.progress = offset / data.length;
      notifyListeners();
    }
    msg.progress = 1.0;
    notifyListeners();
  }

  // ── Receive ───────────────────────────────────────────────────────────────

  void _handleIncoming(String raw) {
    try {
      final ev = jsonDecode(raw) as Map<String, dynamic>;
      switch (ev['type'] as String?) {
        case 'text':
          _addAgentMessage(ChatMessage.text(
            id: ev['id'] as String? ?? _uuid(),
            sender: ChatSender.agent,
            text: ev['text'] as String? ?? '',
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              (ev['ts'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
            ),
          ));

        case 'file_start':
          final id = ev['id'] as String? ?? _uuid();
          final name = ev['name'] as String? ?? 'file';
          final size = (ev['size'] as int?) ?? 0;
          final mime = ev['mime'] as String? ?? 'application/octet-stream';
          _inbound[id] = _InboundFile(name: name, size: size, mime: mime);
          final type = mime.startsWith('audio/') ? ChatMsgType.voice : ChatMsgType.file;
          _addAgentMessage(ChatMessage.transfer(
            id: id,
            sender: ChatSender.agent,
            type: type,
            fileName: name,
            fileSize: size,
            mimeType: mime,
          ));

        case 'file_chunk':
          final id = ev['id'] as String?;
          if (id == null) return;
          final rx = _inbound[id];
          if (rx == null) return;
          rx.buf.add(base64.decode(ev['data'] as String? ?? ''));
          final isLast = ev['last'] as bool? ?? false;
          final idx = _messages.indexWhere((m) => m.id == id);
          if (idx >= 0 && rx.size > 0) {
            _messages[idx].progress = rx.buf.length / rx.size;
            notifyListeners();
          }
          if (isLast) _finishInboundFile(id, rx);
      }
    } catch (_) {}
  }

  void _addAgentMessage(ChatMessage msg) {
    _messages.add(msg);
    if (!_panelOpen) _unreadCount++;
    notifyListeners();
  }

  Future<void> _finishInboundFile(String id, _InboundFile rx) async {
    final bytes = rx.buf.toBytes();
    _inbound.remove(id);
    try {
      final dir = await _saveDir();
      final baseName = rx.name;
      String path = '${dir.path}/$baseName';
      if (File(path).existsSync()) {
        final ext = baseName.contains('.') ? '.${baseName.split('.').last}' : '';
        final stem = ext.isNotEmpty
            ? baseName.substring(0, baseName.length - ext.length)
            : baseName;
        path = '${dir.path}/$stem-${DateTime.now().millisecondsSinceEpoch}$ext';
      }
      await File(path).writeAsBytes(bytes);
      final idx = _messages.indexWhere((m) => m.id == id);
      if (idx >= 0) {
        _messages[idx].localPath = path;
        _messages[idx].progress = 1.0;
        notifyListeners();
      }
    } catch (_) {
      final idx = _messages.indexWhere((m) => m.id == id);
      if (idx >= 0) {
        _messages[idx].hasError = true;
        notifyListeners();
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Returns true if the message was queued successfully, false on error.
  bool _sendRaw(Map<String, dynamic> data) {
    if (!_dcOpen || _dc == null) return false;
    try {
      _dc!.send(RTCDataChannelMessage(jsonEncode(data)));
      return true;
    } catch (_) {
      return false;
    }
  }

  void clear() {
    _messages.clear();
    _unreadCount = 0;
    notifyListeners();
  }

  static Future<Directory> _saveDir() async {
    if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      try {
        final dl = await getDownloadsDirectory();
        if (dl != null) return dl;
      } catch (_) {}
    }
    return getApplicationDocumentsDirectory();
  }

  static String _uuid() {
    final r = Random.secure();
    final bytes = List.generate(8, (_) => r.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _guessMime(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'bmp' => 'image/bmp',
      'pdf' => 'application/pdf',
      'txt' || 'md' => 'text/plain',
      'mp4' || 'mov' || 'avi' => 'video/mp4',
      'mp3' => 'audio/mpeg',
      'aac' => 'audio/aac',
      'opus' => 'audio/opus',
      'm4a' => 'audio/mp4',
      'wav' => 'audio/wav',
      _ => 'application/octet-stream',
    };
  }

  @override
  void dispose() {
    _dc = null;
    super.dispose();
  }
}
