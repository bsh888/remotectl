import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../l10n.dart';
import '../services/remote_session.dart';
import '../utils/key_mapper.dart';
import 'chat_panel.dart';

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
  Offset? _localCursorPos; // cursor position in widget coords for software cursor

  // Keyboard focus
  final FocusNode _focusNode = FocusNode();

  // Panel toggle (click the icon to open/close)
  bool _toolbarVisible = true;
  bool _panelOpen = false;
  bool _chatOpen = false;

  // Mouse throttle
  int _lastMouseMs = 0;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _swapCtrlCmd = _defaultSwap();
    widget.session.chat.addListener(_onChatUpdate);
    // Request keyboard focus after the first frame — autofocus alone is not
    // reliable on macOS desktop when the route is pushed via Navigator.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  void _onChatUpdate() {
    if (mounted) setState(() {});
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
    widget.session.chat.removeListener(_onChatUpdate);
    WakelockPlus.disable();
    _focusNode.dispose();
    super.dispose();
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
    // Don't forward to remote when a child widget (e.g. chat TextField) has focus.
    if (FocusManager.instance.primaryFocus != _focusNode) {
      return KeyEventResult.ignored;
    }
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

  void _onPointerHover(PointerHoverEvent e, Size widgetSize) {
    setState(() => _localCursorPos = e.localPosition);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastMouseMs < 8) return; // ~120 Hz throttle
    _lastMouseMs = now;
    final renderer = widget.session.renderer;
    if (renderer == null) return;
    final (x, y) = _toVideoCoords(e.localPosition, widgetSize, renderer);
    widget.session.sendInput({'event': 'mousemove', 'x': x, 'y': y});
  }

  void _onPointerMove(PointerMoveEvent e, Size widgetSize) {
    // Fires during click-drag (button held). Update cursor position and send move.
    setState(() => _localCursorPos = e.localPosition);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastMouseMs < 8) return; // ~120 Hz throttle
    _lastMouseMs = now;

    final renderer = widget.session.renderer;
    if (renderer == null) return;
    final (x, y) = _toVideoCoords(e.localPosition, widgetSize, renderer);
    widget.session.sendInput({'event': 'mousemove', 'x': x, 'y': y});
  }

  void _onPointerDown(PointerDownEvent e, Size widgetSize) {
    // Re-grab keyboard focus on every click so typing always works.
    _focusNode.requestFocus();
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
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white38),
                  const SizedBox(height: 16),
                  Text(AppLocalizations.of(context).connectingWebRTCDesktop,
                      style: const TextStyle(color: Colors.white54)),
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
              child: Text(AppLocalizations.of(context).back),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnected(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Stack(
        children: [
          // ── Video layer ──
          Positioned.fill(
            child: RTCVideoView(
              widget.session.renderer!,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
              mirror: false,
            ),
          ),

          // ── Event capture overlay (ABOVE the platform view so it gets events) ──
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
                  onExit: (_) => setState(() {
                    _cursorInVideo = false;
                    _localCursorPos = null;
                  }),
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerHover: (e) => _onPointerHover(e, widgetSize),
                    onPointerMove: (e) => _onPointerMove(e, widgetSize),
                    onPointerDown: (e) => _onPointerDown(e, widgetSize),
                    onPointerUp: (e) => _onPointerUp(e, widgetSize),
                    onPointerSignal: _onPointerSignal,
                    child: const SizedBox.expand(),
                  ),
                );
              },
            ),
          ),

          // ── Software cursor (replaces hidden system cursor inside video) ──
          if (_cursorInVideo && _localCursorPos != null)
            Positioned(
              left: _localCursorPos!.dx,
              top: _localCursorPos!.dy,
              child: const IgnorePointer(
                child: CustomPaint(
                  size: Size(20, 20),
                  painter: _CursorPainter(),
                ),
              ),
            ),

          // ── Chat panel (right side, full height) ──
          if (_chatOpen)
            Positioned(
              top: 8,
              right: 8,
              bottom: 8,
              child: ChatPanel(
                width: 300,
                chat: widget.session.chat,
                onClose: () {
                  setState(() => _chatOpen = false);
                  widget.session.chat.setPanelOpen(false);
                  _focusNode.requestFocus();
                },
              ),
            ),

          // ── Floating toolbar (top-right, shifts left when chat open) ──
          if (_toolbarVisible)
            Positioned(
              top: 8,
              right: _chatOpen ? 316 : 8,
              child: _buildToolbar(context),
            ),

          // ── Control panel (expands below toolbar when open) ──
          if (_toolbarVisible && _panelOpen)
            Positioned(
              top: 46,
              right: _chatOpen ? 316 : 8,
              child: _buildPanel(context),
            ),

          // ── Collapsed tab (shown when toolbar is hidden) ──
          if (!_toolbarVisible)
            Positioned(
              top: 0,
              right: _chatOpen ? 316 : 0,
              child: GestureDetector(
                onTap: () => setState(() => _toolbarVisible = true),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Tooltip(
                    message: AppLocalizations.of(context).showToolbar,
                    child: Container(
                      width: 24,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.50),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(6),
                          bottomRight: Radius.circular(6),
                        ),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.12),
                          width: 0.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 14,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final unread = widget.session.chat.unreadCount;
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.60),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Collapse toolbar
          _ToolbarBtn(
            icon: Icons.keyboard_arrow_up_rounded,
            tooltip: AppLocalizations.of(context).collapse,
            onTap: () => setState(() {
              _toolbarVisible = false;
              _panelOpen = false;
            }),
          ),
          Container(width: 1, height: 16, color: Colors.white.withOpacity(0.15)),
          // Control panel toggle
          _ToolbarBtn(
            icon: _platformIcon(widget.remotePlatform),
            active: _panelOpen,
            tooltip: AppLocalizations.of(context).controlPanel,
            onTap: () {
              setState(() => _panelOpen = !_panelOpen);
              _focusNode.requestFocus();
            },
          ),
          Container(width: 1, height: 16, color: Colors.white.withOpacity(0.15)),
          // Chat toggle
          _ToolbarBtn(
            icon: _chatOpen ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded,
            active: _chatOpen,
            accentColor: const Color(0xFF2563EB),
            tooltip: AppLocalizations.of(context).chat,
            badge: unread > 0 ? (unread > 9 ? '9+' : '$unread') : null,
            onTap: () {
              setState(() {
                _chatOpen = !_chatOpen;
                _panelOpen = false;
              });
              widget.session.chat.setPanelOpen(_chatOpen);
              _focusNode.requestFocus();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final name = widget.deviceName.isNotEmpty ? widget.deviceName : AppLocalizations.of(context).remoteDesktop;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.82),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Device name
          Text(name,
              style: const TextStyle(
                  color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 8),
          // Action row
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ctrl ⇄ Cmd toggle
              _PanelBtn(
                label: Platform.isMacOS ? '⌘⇄Ctrl' : 'Ctrl⇄⌘',
                active: _swapCtrlCmd,
                onTap: () => setState(() => _swapCtrlCmd = !_swapCtrlCmd),
              ),
              const SizedBox(width: 6),
              // Paste
              _PanelBtn(
                icon: Icons.content_paste,
                tooltip: AppLocalizations.of(context).paste,
                onTap: () { _pasteClipboard(); setState(() => _panelOpen = false); },
              ),
              // Win key (Windows only)
              if (widget.remotePlatform == 'windows') ...[
                const SizedBox(width: 6),
                _PanelBtn(
                  label: '⊞',
                  tooltip: 'Win',
                  onTap: () { _sendWinKey(); setState(() => _panelOpen = false); },
                ),
                const SizedBox(width: 6),
                _PanelBtn(
                  label: 'CAD',
                  tooltip: 'Ctrl+Alt+Del',
                  onTap: () { _sendCtrlAltDel(); setState(() => _panelOpen = false); },
                ),
              ],
              const SizedBox(width: 6),
              // Disconnect
              _PanelBtn(
                icon: Icons.logout,
                danger: true,
                tooltip: AppLocalizations.of(context).disconnect,
                onTap: () {
                  widget.session.disconnect();
                  Navigator.of(context).pop();
                },
              ),
            ],
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

  void _sendWinKey() {
    widget.session.sendInput(
        {'event': 'keydown', 'key': 'Meta', 'code': 'MetaLeft', 'mods': []});
    widget.session.sendInput(
        {'event': 'keyup', 'key': 'Meta', 'code': 'MetaLeft', 'mods': []});
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

// ── Software cursor painter ───────────────────────────────────────────────────
// Draws a classic arrow cursor at (0, 0) — place via Positioned so the tip
// lands exactly on the pointer position.

class _CursorPainter extends CustomPainter {
  const _CursorPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = const Color(0xFFFFFFFF)..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    // Arrow cursor path (tip at origin)
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(0, 14)
      ..lineTo(3.5, 10.5)
      ..lineTo(6, 16)
      ..lineTo(8, 15)
      ..lineTo(5.5, 9.5)
      ..lineTo(10, 9.5)
      ..close();

    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(_CursorPainter old) => false;
}

// ── Toolbar button (inside the floating pill) ─────────────────────────────────

class _ToolbarBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final Color? accentColor;
  final String? tooltip;
  final String? badge;
  final VoidCallback onTap;

  const _ToolbarBtn({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.accentColor,
    this.tooltip,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final bg = active
        ? (accentColor ?? Colors.white.withOpacity(0.18)).withOpacity(
            accentColor != null ? 0.75 : 0.18)
        : Colors.transparent;

    Widget btn = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 30,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 15, color: active ? Colors.white : Colors.white60),
              if (badge != null)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 7,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return tooltip != null ? Tooltip(message: tooltip!, child: btn) : btn;
  }
}

// ── Panel button (inside the expanded control panel) ──────────────────────────

class _PanelBtn extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final String? tooltip;
  final bool active;
  final bool danger;
  final VoidCallback onTap;

  const _PanelBtn({
    this.label,
    this.icon,
    this.tooltip,
    this.active = false,
    this.danger = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = icon != null
        ? Icon(icon, size: 14,
            color: danger ? Colors.redAccent : Colors.white70)
        : Text(label ?? '',
            style: TextStyle(
              fontSize: 11,
              color: danger
                  ? Colors.redAccent
                  : active
                      ? Colors.white
                      : Colors.white70,
            ));

    Widget btn = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFF2563EB).withOpacity(0.7)
                : Colors.white10,
            borderRadius: BorderRadius.circular(5),
          ),
          child: content,
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}
