import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'chat_service.dart';

/// Chat service for the hosted (被控端) side.
/// Communicates via stdio IPC (no network port).
/// AgentService calls [receive] when a CHAT_MSG: line arrives from the agent,
/// and provides a send callback so [sendText]/[sendFile] write CHAT_SEND: to stdin.
class HostedChatService extends ChatServiceBase {
  final List<ChatMessage> _messages = [];
  void Function(String json)? _onSend;
  bool _connected = false;
  int _unreadCount = 0;
  bool _panelOpen = false;

  @override
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  @override
  bool get isOpen => _connected;
  @override
  int get unreadCount => _unreadCount;
  @override
  bool get panelOpen => _panelOpen;

  /// Called by AgentService when the agent process starts/stops.
  void setConnected(bool v) {
    if (_connected == v) return;
    _connected = v;
    notifyListeners();
  }

  /// Called by AgentService to wire up the stdin write path.
  void setSendCallback(void Function(String json) cb) {
    _onSend = cb;
  }

  /// Called by AgentService for each CHAT_MSG:<json> line from agent stdout.
  void receive(String json) => _handle(json);

  @override
  void setPanelOpen(bool open) {
    _panelOpen = open;
    if (open) _unreadCount = 0;
    notifyListeners();
  }

  void _handle(String raw) {
    try {
      final ev = jsonDecode(raw) as Map<String, dynamic>;
      final type = ev['type'] as String?;
      final from = ev['from'] as String?;
      // from="agent"  → sent by us (hosted/被控端) → shown on right (ChatSender.viewer)
      // from="viewer" → sent by the remote controller → shown on left (ChatSender.agent)
      final isMe = from == 'agent';
      final sender = isMe ? ChatSender.viewer : ChatSender.agent;

      switch (type) {
        case 'text':
          final text = ev['text'] as String? ?? '';
          if (text.isEmpty) return;
          final ts = ev['ts'] as int?;
          _messages.add(ChatMessage.text(
            id: _uuid(),
            sender: sender,
            text: text,
            timestamp: ts != null
                ? DateTime.fromMillisecondsSinceEpoch(ts)
                : DateTime.now(),
          ));
          if (!isMe && !_panelOpen) _unreadCount++;
          notifyListeners();

        case 'file_start':
          final id = ev['id'] as String? ?? _uuid();
          final name = ev['name'] as String? ?? 'file';
          final size = (ev['size'] as num?)?.toInt() ?? 0;
          final mime = ev['mime'] as String? ?? 'application/octet-stream';
          final msgType =
              mime.startsWith('audio/') ? ChatMsgType.voice : ChatMsgType.file;
          final msg = ChatMessage.transfer(
            id: id,
            sender: sender,
            type: msgType,
            fileName: name,
            fileSize: size,
            mimeType: mime,
          );
          // Incoming file from viewer: agent already saved it → mark done.
          if (!isMe) msg.progress = 1.0;
          _messages.add(msg);
          if (!isMe && !_panelOpen) _unreadCount++;
          notifyListeners();

        case 'file_saved':
          // Agent finished saving a received file — set localPath so
          // ChatPanel can show the "打开文件" button.
          final id = ev['id'] as String?;
          final name = ev['name'] as String?;
          final path = ev['path'] as String?;
          if (path == null) return;
          final idx = id != null
              ? _messages.indexWhere((m) => m.id == id)
              : name != null
                  ? _messages.lastIndexWhere(
                      (m) => m.type != ChatMsgType.text && m.fileName == name)
                  : -1;
          if (idx >= 0) {
            _messages[idx].localPath = path;
            _messages[idx].progress = 1.0;
            notifyListeners();
          }
      }
    } catch (_) {}
  }

  @override
  Future<void> sendText(String text) async {
    final t = text.trim();
    if (t.isEmpty || !_connected) return;
    _onSend?.call(jsonEncode({'action': 'send_text', 'text': t}));
    // Show the outgoing message locally immediately.
    _messages.add(ChatMessage.text(
      id: _uuid(),
      sender: ChatSender.viewer, // "me" = right side
      text: t,
    ));
    notifyListeners();
  }

  @override
  Future<void> sendFile(String filePath) async {
    if (!_connected) return;
    final file = File(filePath);
    if (!file.existsSync()) return;
    final name = file.uri.pathSegments.last;
    _onSend?.call(jsonEncode({'action': 'send_file', 'name': name, 'path': filePath}));
    // Show the outgoing file locally immediately.
    final mime = _guessMime(name);
    final msgType = mime.startsWith('audio/') ? ChatMsgType.voice : ChatMsgType.file;
    final stat = await file.stat();
    final msg = ChatMessage.transfer(
      id: _uuid(),
      sender: ChatSender.viewer,
      type: msgType,
      fileName: name,
      fileSize: stat.size,
      mimeType: mime,
      localPath: filePath,
    );
    msg.progress = 1.0;
    _messages.add(msg);
    notifyListeners();
  }

  static String _guessMime(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'pdf' => 'application/pdf',
      'txt' || 'md' => 'text/plain',
      'mp4' || 'mov' => 'video/mp4',
      'mp3' => 'audio/mpeg',
      'wav' => 'audio/wav',
      _ => 'application/octet-stream',
    };
  }

  static String _uuid() {
    final r = Random.secure();
    return List.generate(8, (_) => r.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  @override
  void dispose() {
    _onSend = null;
    super.dispose();
  }
}
