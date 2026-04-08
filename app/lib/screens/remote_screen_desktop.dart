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
  Offset? _localCursorPos; // cursor position in widget coords for software cursor

  // Keyboard focus — onKeyEvent is set in initState so _onKey can reference `this`
  late final FocusNode _focusNode;

  // Hidden TextField for text / IME capture (Chinese, Japanese, etc.)
  // The same FocusNode is shared so key events and text input are co-located.
  final TextEditingController _kbController =
      TextEditingController(text: '\u200b');
  String _prevKbText = '\u200b';
  // Tracks which physical keys were passed through to the TextField (printable,
  // no modifier) so their KeyUpEvent can also be ignored.
  final Set<PhysicalKeyboardKey> _textKeys = {};

  // Panel toggle (click the icon to open/close)
  bool _panelOpen = false;

  // Mouse throttle
  int _lastMouseMs = 0;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _swapCtrlCmd = _defaultSwap();
    _focusNode = FocusNode(onKeyEvent: _onKey);
    // Request keyboard focus after the first frame — autofocus alone is not
    // reliable on macOS desktop when the route is pushed via Navigator.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
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
    _focusNode.dispose();
    _kbController.dispose();
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

  // Returns true when a character is "printable text" that should flow through
  // to the hidden TextField so the IME can process it (e.g. Chinese pinyin
  // input).  Control characters, Backspace, Tab, Enter, Delete are excluded
  // so we can handle them explicitly.
  static bool _isPrintableChar(String? char) {
    if (char == null || char.isEmpty) return false;
    final cp = char.runes.first;
    // Exclude control characters (< U+0020) and DEL (U+007F)
    return cp >= 0x20 && cp != 0x7f;
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent &&
        event is! KeyUpEvent &&
        event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final hasCtrlAltMeta = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    if (event is KeyUpEvent) {
      // If the matching KeyDown was passed through to the TextField, ignore
      // this KeyUp too (TextField + IME owns that key's lifecycle).
      if (_textKeys.remove(event.physicalKey)) {
        return KeyEventResult.ignored;
      }
    } else {
      // KeyDown / KeyRepeat
      if (!hasCtrlAltMeta && _isPrintableChar(event.character)) {
        // Let the hidden TextField + platform IME handle this character.
        // _onKbChanged will send it as paste_text once IME commits it.
        _textKeys.add(event.physicalKey);
        return KeyEventResult.ignored;
      }
      // Not a text key — remove from set in case a modifier was pressed after
      // the key was already tracked (edge case).
      _textKeys.remove(event.physicalKey);
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

  // ── IME / text field ───────────────────────────────────────────────────────

  void _onKbChanged(String text) {
    // While IME composition is in progress the preedit text changes rapidly.
    // Only act once composition is committed (composing range becomes empty).
    if (_kbController.value.composing.isValid) return;

    final prev = _prevKbText;

    if (text.isEmpty) {
      _prevKbText = '\u200b';
      _kbController.value = const TextEditingValue(
        text: '\u200b',
        selection: TextSelection.collapsed(offset: 1),
      );
      widget.session
          .sendInput({'event': 'keydown', 'key': 'Backspace', 'code': 'Backspace', 'mods': []});
      widget.session
          .sendInput({'event': 'keyup', 'key': 'Backspace', 'code': 'Backspace', 'mods': []});
      return;
    }

    if (text.length > prev.length) {
      final added = text.replaceFirst('\u200b', '');
      final prevClean = prev.replaceFirst('\u200b', '');
      if (added.length > prevClean.length) {
        final newChars = added.substring(prevClean.length);
        widget.session.sendInput({'event': 'paste_text', 'text': newChars});
      }
    } else if (text.length < prev.length) {
      final removed = prev.length - text.length;
      for (var i = 0; i < removed; i++) {
        widget.session
            .sendInput({'event': 'keydown', 'key': 'Backspace', 'code': 'Backspace', 'mods': []});
        widget.session
            .sendInput({'event': 'keyup', 'key': 'Backspace', 'code': 'Backspace', 'mods': []});
      }
    }

    _prevKbText = text;
    _kbController.selection = TextSelection.collapsed(offset: text.length);
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
    return Stack(
      children: [
        // ── Hidden TextField for text / IME input ──────────────────────────
        // Fills the entire area so Flutter can establish a proper text-input
        // connection (a 1×1 box fails to do so on some platforms).
        // IgnorePointer lets mouse events fall through to the Listener below;
        // Opacity(0) makes it invisible without removing it from layout.
        Positioned.fill(
          child: IgnorePointer(
            child: Opacity(
              opacity: 0,
              child: TextField(
                focusNode: _focusNode,
                controller: _kbController,
                onChanged: _onKbChanged,
                autofocus: true,
                enableInteractiveSelection: false,
                keyboardType: TextInputType.multiline,
                maxLines: null,
                style: const TextStyle(color: Colors.transparent, fontSize: 14),
                cursorColor: Colors.transparent,
                cursorWidth: 0,
                decoration: const InputDecoration.collapsed(hintText: ''),
              ),
            ),
          ),
        ),

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

        // ── Floating control icon (top-right) ──
        Positioned(
          top: 8,
          right: 8,
          child: _buildToggleButton(context),
        ),

        // ── Control panel (expands below icon when open) ──
        if (_panelOpen)
          Positioned(
            top: 38,
            right: 8,
            child: _buildPanel(context),
          ),
      ],
    );
  }

  Widget _buildToggleButton(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() => _panelOpen = !_panelOpen);
        // Re-grab focus after toggling so keyboard still works.
        _focusNode.requestFocus();
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: _panelOpen
                ? Colors.white.withOpacity(0.18)
                : Colors.black.withOpacity(0.45),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            _platformIcon(widget.remotePlatform),
            size: 15,
            color: Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    final name = widget.deviceName.isNotEmpty ? widget.deviceName : '远程桌面';
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
                tooltip: '粘贴',
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
                tooltip: '断开',
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

// ── Panel button ──────────────────────────────────────────────────────────────

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
