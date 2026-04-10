import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/chat_service.dart';

// ── ChatPanel ─────────────────────────────────────────────────────────────────
// A self-contained chat panel widget. Place it in a Stack overlay (desktop)
// or inside a bottom sheet (mobile).

class ChatPanel extends StatefulWidget {
  final ChatServiceBase chat;
  final VoidCallback onClose;
  /// Fixed width for the panel. If null, the panel fills available width
  /// (used when embedded in a bottom sheet on mobile).
  final double? width;

  const ChatPanel({super.key, required this.chat, required this.onClose, this.width});

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.chat.addListener(_onChatChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollBottom());
  }

  @override
  void dispose() {
    widget.chat.removeListener(_onChatChange);
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onChatChange() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollBottom());
  }

  void _scrollBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();
    await widget.chat.sendText(text);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path != null) await widget.chat.sendFile(path);
  }


  Future<void> _openFile(ChatMessage msg) async {
    if (msg.localPath == null) return;
    final path = msg.localPath!;
    try {
      if (Platform.isMacOS) {
        Process.run('open', [path]);
      } else if (Platform.isWindows) {
        // `explorer.exe path` is unreliable with spaces; use cmd start instead.
        Process.run('cmd', ['/c', 'start', '', path]);
      } else if (Platform.isLinux) {
        Process.run('xdg-open', [path]);
      }
      // iOS / Android: handled separately (no file manager API here)
    } catch (_) {}
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isSheet = widget.width == null;
    final radius = isSheet
        ? const BorderRadius.vertical(top: Radius.circular(16))
        : BorderRadius.circular(12);
    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: const Color(0xFF0A1628).withOpacity(0.97),
        borderRadius: radius,
        border: isSheet ? null : Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: isSheet
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 24,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Column(
          children: [
            _buildHeader(),
            const Divider(height: 1, thickness: 1, color: Colors.white10),
            Expanded(child: _buildMessageList()),
            const Divider(height: 1, thickness: 1, color: Colors.white10),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          const Icon(Icons.chat_bubble_rounded, size: 14, color: Color(0xFF2563EB)),
          const SizedBox(width: 7),
          const Text(
            '聊天',
            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          if (!widget.chat.isOpen)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '等待连接',
                style: TextStyle(color: Colors.orange, fontSize: 9),
              ),
            ),
          const Spacer(),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onClose,
              child: const Icon(Icons.close, size: 16, color: Colors.white38),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    final msgs = widget.chat.messages;
    if (msgs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 36, color: Colors.white10),
            SizedBox(height: 8),
            Text('发消息给对方', style: TextStyle(color: Colors.white24, fontSize: 12)),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      itemCount: msgs.length,
      itemBuilder: (_, i) => _buildBubble(msgs[i]),
    );
  }

  Widget _buildBubble(ChatMessage msg) {
    final isMe = msg.sender == ChatSender.viewer;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 13,
              backgroundColor: Colors.white10,
              child: const Icon(Icons.computer, size: 12, color: Colors.white38),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(child: _buildContent(msg, isMe)),
          if (isMe) const SizedBox(width: 2),
        ],
      ),
    );
  }

  Widget _buildContent(ChatMessage msg, bool isMe) {
    return switch (msg.type) {
      ChatMsgType.text => _textBubble(msg, isMe),
      ChatMsgType.voice || ChatMsgType.file => _fileBubble(msg, isMe),
    };
  }

  // ── Text bubble ───────────────────────────────────────────────────────────

  Widget _textBubble(ChatMessage msg, bool isMe) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFF2563EB) : Colors.white12,
        borderRadius: BorderRadius.circular(14).copyWith(
          bottomRight: isMe ? const Radius.circular(3) : null,
          bottomLeft: isMe ? null : const Radius.circular(3),
        ),
      ),
      child: Text(
        msg.text ?? '',
        style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
      ),
    );
  }

  // ── File bubble ───────────────────────────────────────────────────────────

  Widget _fileBubble(ChatMessage msg, bool isMe) {
    final isImage = (msg.mimeType ?? '').startsWith('image/');
    final done = msg.progress >= 1.0 && msg.localPath != null && !msg.hasError;

    // Show inline image preview when available
    if (isImage && done) {
      return _imageBubble(msg, isMe);
    }

    final transferring = !isMe && !done && !msg.hasError;

    return Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: isMe ? const Color(0xFF2563EB) : Colors.white12,
        borderRadius: BorderRadius.circular(14).copyWith(
          bottomRight: isMe ? const Radius.circular(3) : null,
          bottomLeft: isMe ? null : const Radius.circular(3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_mimeIcon(msg.mimeType), color: Colors.white70, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  msg.fileName ?? '文件',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (msg.fileSize != null) ...[
            const SizedBox(height: 2),
            Text(
              _fmtSize(msg.fileSize!),
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],
          if (transferring) ...[
            const SizedBox(height: 5),
            LinearProgressIndicator(
              value: msg.progress > 0 ? msg.progress : null,
              minHeight: 2,
              backgroundColor: Colors.white12,
              color: Colors.white54,
            ),
          ] else if (isMe && msg.progress < 1.0 && !msg.hasError) ...[
            const SizedBox(height: 5),
            LinearProgressIndicator(
              value: msg.progress,
              minHeight: 2,
              backgroundColor: Colors.white24,
              color: Colors.white,
            ),
          ] else if (done && !isMe) ...[
            const SizedBox(height: 4),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => _openFile(msg),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.open_in_new, size: 11, color: Colors.white38),
                    SizedBox(width: 3),
                    Text('打开文件', style: TextStyle(color: Colors.white38, fontSize: 10)),
                  ],
                ),
              ),
            ),
          ],
          if (msg.hasError) ...[
            const SizedBox(height: 3),
            const Text('传输失败', style: TextStyle(color: Colors.redAccent, fontSize: 10)),
          ],
        ],
      ),
    );
  }

  Widget _imageBubble(ChatMessage msg, bool isMe) {
    return GestureDetector(
      onTap: () => _openFile(msg),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12).copyWith(
            bottomRight: isMe ? const Radius.circular(3) : null,
            bottomLeft: isMe ? null : const Radius.circular(3),
          ),
          child: Image.file(
            File(msg.localPath!),
            width: 200,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fileBubble(msg, isMe),
          ),
        ),
      ),
    );
  }

  // ── Input bar ─────────────────────────────────────────────────────────────

  Widget _buildInputBar() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Attach file
          _IconBtn(icon: Icons.attach_file_rounded, onTap: _pickFile, tooltip: '发送文件'),
          const SizedBox(width: 6),
          // Text input
          Expanded(
            child: TextField(
              controller: _textCtrl,
              enabled: widget.chat.isOpen,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              maxLines: 4,
              minLines: 1,
              decoration: InputDecoration(
                hintText: widget.chat.isOpen ? '发消息…' : '等待连接…',
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                filled: true,
                fillColor: Colors.white.withOpacity(0.07),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 6),
          _SendBtn(onSend: _send, enabled: widget.chat.isOpen),
        ],
      ),
    );
  }

  // ── Static helpers ────────────────────────────────────────────────────────

  static IconData _mimeIcon(String? mime) {
    if (mime == null) return Icons.insert_drive_file_rounded;
    if (mime.startsWith('image/')) return Icons.image_rounded;
    if (mime.startsWith('video/')) return Icons.video_file_rounded;
    if (mime.startsWith('audio/')) return Icons.audio_file_rounded;
    if (mime == 'application/pdf') return Icons.picture_as_pdf_rounded;
    return Icons.insert_drive_file_rounded;
  }

  static String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  const _IconBtn({required this.icon, required this.onTap, this.tooltip});

  @override
  Widget build(BuildContext context) {
    Widget w = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.white54, size: 15),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: w) : w;
  }
}

class _SendBtn extends StatelessWidget {
  final VoidCallback onSend;
  final bool enabled;
  const _SendBtn({required this.onSend, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? onSend : null,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: enabled ? const Color(0xFF2563EB) : Colors.white10,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.send_rounded, color: Colors.white, size: 15),
        ),
      ),
    );
  }
}

