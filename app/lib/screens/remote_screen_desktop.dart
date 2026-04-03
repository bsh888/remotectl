import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/remote_session.dart';
import '../utils/key_mapper.dart';

class RemoteScreenDesktop extends StatefulWidget {
  final RemoteSession session;
  final String deviceName;
  final String remotePlatform; // 'darwin' | 'windows' | 'linux' | ''

  const RemoteScreenDesktop({
    super.key,
    required this.session,
    required this.deviceName,
    required this.remotePlatform,
  });

  @override
  State<RemoteScreenDesktop> createState() => _RemoteScreenDesktopState();
}

class _RemoteScreenDesktopState extends State<RemoteScreenDesktop> {
  // ── state ──────────────────────────────────────────────────────────────────
  late bool _swapCtrlCmd;
  bool _cursorInVideo = false;

  // Toolbar auto-hide
  bool _toolbarVisible = true;
  Timer? _hideTimer;

  // Mouse throttle
  int _lastMouseMs = 0;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _swapCtrlCmd = _defaultSwap();
  }

  bool _defaultSwap() {
    final localMac = Platform.isMacOS;
    final remote = widget.remotePlatform;
    // Mac client → Windows remote: Cmd→Ctrl
    if (localMac && remote == 'windows') return true;
    // Windows/Linux client → Mac remote: Ctrl→Cmd
    if (!localMac && (remote == 'darwin' || remote == '')) return true;
    return false;
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _hideTimer?.cancel();
    super.dispose();
  }

  // ── toolbar auto-hide ──────────────────────────────────────────────────────

  void _showToolbar() {
    if (!_toolbarVisible) setState(() => _toolbarVisible = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toolbarVisible = false);
    });
  }

  // ── coordinate mapping ─────────────────────────────────────────────────────
  // Matches browser toRemote(): accounts for letterboxing with object-fit:contain.
  (double, double) _toVideoCoords(
      Offset pos, Size widgetSize, RTCVideoRenderer renderer) {
    final vW = renderer.videoWidth.toDouble();
    final vH = renderer.videoHeight.toDouble();
    if (vW <= 0 || vH <= 0) return (pos.dx, pos.dy);

    final vAspect = vW / vH;
    final cAspect = widgetSize.width / widgetSize.height;

    double rW, rH, oX, oY;
    if (vAspect > cAspect) {
      rW = widgetSize.width;
      rH = widgetSize.width / vAspect;
      oX = 0;
      oY = (widgetSize.height - rH) / 2;
    } else {
      rW = widgetSize.height * vAspect;
      rH = widgetSize.height;
      oX = (widgetSize.width - rW) / 2;
      oY = 0;
    }

    final x = ((pos.dx - oX) / rW) * vW;
    final y = ((pos.dy - oY) / rH) * vH;
    return (x.roundToDouble(), y.roundToDouble());
  }

  // ── modifier helpers ───────────────────────────────────────────────────────

  List<String> _getMods() {
    final hw = HardwareKeyboard.instance;
    final mods = <String>[];
    if (hw.isControlPressed) mods.add('ctrl');
    if (hw.isShiftPressed) mods.add('shift');
    if (hw.isAltPressed) mods.add('alt');
    if (hw.isMetaPressed) mods.add('meta');
    if (!_swapCtrlCmd) return mods;
    return mods
        .map((m) => m == 'ctrl' ? 'meta' : m == 'meta' ? 'ctrl' : m)
        .toList();
  }

  String _swapKey(String k) {
    if (!_swapCtrlCmd) return k;
    if (k == 'Control') return 'Meta';
    if (k == 'Meta') return 'Control';
    return k;
  }

  String _swapCode(String c) {
    if (!_swapCtrlCmd) return c;
    if (c == 'ControlLeft') return 'MetaLeft';
    if (c == 'ControlRight') return 'MetaRight';
    if (c == 'MetaLeft') return 'ControlLeft';
    if (c == 'MetaRight') return 'ControlRight';
    return c;
  }

  // ── keyboard ───────────────────────────────────────────────────────────────

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent &&
        event is! KeyUpEvent &&
        event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final type = (event is KeyUpEvent) ? 'keyup' : 'keydown';
    var keyStr = KeyMapper.logicalToKey(event.logicalKey);
    var codeStr = KeyMapper.physicalToCode(event.physicalKey);
    keyStr = _swapKey(keyStr);
    codeStr = _swapCode(codeStr);

    widget.session.sendInput({
      'event': type,
      'key': keyStr,
      'code': codeStr,
      'mods': _getMods(),
    });

    return KeyEventResult.handled;
  }

  // ── mouse ──────────────────────────────────────────────────────────────────

  void _onPointerMove(PointerMoveEvent e, Size widgetSize) {
    _showToolbar();
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastMouseMs < 8) return; // ~120 Hz throttle
    _lastMouseMs = now;

    final renderer = widget.session.renderer;
    if (renderer == null) return;
    final (x, y) = _toVideoCoords(e.localPosition, widgetSize, renderer);
    widget.session.sendInput({'event': 'mousemove', 'x': x, 'y': y});
  }

  void _onPointerDown(PointerDownEvent e, Size widgetSize) {
    final renderer = widget.session.renderer;
    if (renderer == null) return;
    final (x, y) = _toVideoCoords(e.localPosition, widgetSize, renderer);
    final button = _flutterButtonToWeb(e.buttons);
    widget.session.sendInput({
      'event': 'mousedown',
      'x': x,
      'y': y,
      'button': button,
      'mods': _getMods(),
    });
  }

  void _onPointerUp(PointerUpEvent e, Size widgetSize) {
    final renderer = widget.session.renderer;
    if (renderer == null) return;
    final (x, y) = _toVideoCoords(e.localPosition, widgetSize, renderer);
    final button = _flutterButtonToWeb(e.buttons);
    widget.session.sendInput({'event': 'mouseup', 'x': x, 'y': y, 'button': button});
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    widget.session.sendInput({
      'event': 'scroll',
      'dx': e.scrollDelta.dx.round(),
      'dy': e.scrollDelta.dy.round(),
    });
  }

  static int _flutterButtonToWeb(int buttons) {
    if (buttons & kSecondaryMouseButton != 0) return 2;
    if (buttons & kMiddleMouseButton != 0) return 1;
    return 0; // primary (left)
  }

  // ── clipboard paste ────────────────────────────────────────────────────────

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      widget.session.sendInput({'event': 'paste_text', 'text': data.text});
    }
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ListenableBuilder(
        listenable: widget.session,
        builder: (context, _) {
          if (widget.session.state == SessionState.error) {
            return _buildError(context);
          }
          if (widget.session.state != SessionState.connected ||
              widget.session.renderer == null) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white38),
                  SizedBox(height: 16),
                  Text('正在建立 WebRTC 连接…',
                      style: TextStyle(color: Colors.white54)),
                ],
              ),
            );
          }
          return _buildConnected(context);
        },
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(widget.session.error,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnected(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Stack(
        children: [
          // ── Video + mouse layer ──
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final widgetSize =
                    Size(constraints.maxWidth, constraints.maxHeight);
                return MouseRegion(
                  cursor: _cursorInVideo
                      ? SystemMouseCursors.none
                      : SystemMouseCursors.basic,
                  onEnter: (_) => setState(() => _cursorInVideo = true),
                  onExit: (_) => setState(() => _cursorInVideo = false),
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerMove: (e) => _onPointerMove(e, widgetSize),
                    onPointerDown: (e) => _onPointerDown(e, widgetSize),
                    onPointerUp: (e) => _onPointerUp(e, widgetSize),
                    onPointerSignal: _onPointerSignal,
                    child: RTCVideoView(
                      widget.session.renderer!,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                      mirror: false,
                    ),
                  ),
                );
              },
            ),
          ),

          // ── Toolbar (auto-hide) ──
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            top: _toolbarVisible ? 0 : -56,
            left: 0,
            right: 0,
            child: _buildToolbar(context),
          ),

          // ── Mouse-move trigger for toolbar reveal ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 4,
            child: MouseRegion(
              onEnter: (_) => _showToolbar(),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return Container(
      height: 48,
      color: Colors.black.withOpacity(0.80),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Device icon + name
          Icon(_platformIcon(widget.remotePlatform),
              size: 16, color: Colors.white54),
          const SizedBox(width: 6),
          Text(
            widget.deviceName.isNotEmpty ? widget.deviceName : '远程桌面',
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500),
          ),

          const Spacer(),

          // Ctrl ⇄ Cmd toggle
          _ToolbarToggle(
            label: Platform.isMacOS ? 'Ctrl ⇄ ⌘' : '⌘ ⇄ Ctrl',
            value: _swapCtrlCmd,
            tooltip: Platform.isMacOS
                ? 'Cmd+C/V/Z 自动转换为远程的 Ctrl+C/V/Z'
                : 'Ctrl+C/V/Z 自动转换为远程 Mac 的 Cmd+C/V/Z',
            onChanged: (v) => setState(() => _swapCtrlCmd = v),
          ),
          const SizedBox(width: 4),

          // Paste clipboard
          _ToolbarButton(
            icon: Icons.content_paste,
            label: '粘贴',
            tooltip: '将本地剪贴板内容发送到远程（或直接 Ctrl+V）',
            onTap: _pasteClipboard,
          ),
          const SizedBox(width: 4),

          // Ctrl+Alt+Del (Windows)
          if (widget.remotePlatform == 'windows' || widget.remotePlatform == '')
            _ToolbarButton(
              icon: Icons.power_settings_new,
              label: 'CAD',
              tooltip: 'Ctrl+Alt+Del',
              onTap: _sendCtrlAltDel,
            ),
          if (widget.remotePlatform == 'windows' || widget.remotePlatform == '')
            const SizedBox(width: 4),

          // Disconnect
          TextButton(
            onPressed: () {
              widget.session.disconnect();
              Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red.shade300,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
            child: const Text('断开', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  void _sendCtrlAltDel() {
    for (final ev in ['keydown', 'keyup']) {
      if (ev == 'keydown') {
        widget.session.sendInput(
            {'event': 'keydown', 'key': 'Control', 'code': 'ControlLeft', 'mods': []});
        widget.session.sendInput(
            {'event': 'keydown', 'key': 'Alt', 'code': 'AltLeft', 'mods': ['ctrl']});
        widget.session.sendInput(
            {'event': 'keydown', 'key': 'Delete', 'code': 'Delete', 'mods': ['ctrl', 'alt']});
      } else {
        widget.session.sendInput(
            {'event': 'keyup', 'key': 'Delete', 'code': 'Delete', 'mods': ['ctrl', 'alt']});
        widget.session.sendInput(
            {'event': 'keyup', 'key': 'Alt', 'code': 'AltLeft', 'mods': ['ctrl']});
        widget.session.sendInput(
            {'event': 'keyup', 'key': 'Control', 'code': 'ControlLeft', 'mods': []});
      }
    }
  }

  static IconData _platformIcon(String platform) {
    switch (platform) {
      case 'darwin':
        return Icons.laptop_mac;
      case 'windows':
        return Icons.laptop_windows;
      default:
        return Icons.computer;
    }
  }
}

// ── Toolbar widgets ───────────────────────────────────────────────────────────

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: Colors.white60),
              const SizedBox(width: 4),
              Text(label,
                  style: const TextStyle(fontSize: 12, color: Colors.white60)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarToggle extends StatelessWidget {
  final String label;
  final String tooltip;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToolbarToggle({
    required this.label,
    required this.tooltip,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 16,
                child: _MiniSwitch(value: value),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: value ? const Color(0xFF86EFAC) : Colors.white54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniSwitch extends StatelessWidget {
  final bool value;
  const _MiniSwitch({required this.value});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: value ? const Color(0xFF2563EB) : Colors.white24,
      ),
      child: Align(
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
