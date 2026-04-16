import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../l10n.dart';
import '../services/remote_session.dart';
import 'chat_panel.dart';

class RemoteScreen extends StatefulWidget {
  final RemoteSession session;
  final String deviceName;
  final String remotePlatform; // 'darwin' | 'windows' | 'linux' | ''

  const RemoteScreen({
    super.key,
    required this.session,
    this.deviceName = '',
    this.remotePlatform = '',
  });

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  // ── touch tracking ──────────────────────────────────────────────────────────
  Timer? _longPressTimer;
  Offset? _touchStart;
  Offset? _lastTouch;
  bool _longPressFired = false;

  // Two-finger scroll / zoom / pan
  Offset? _prevCentroid;
  double? _prevPinchDist;
  double _videoScale = 1.0;
  Offset _videoPan = Offset.zero;
  bool _twoFingerUsed = false; // true if this gesture involved 2 fingers

  // Keyboard
  final _kbFocus = FocusNode();
  final _kbController = TextEditingController(text: '\u200b'); // zero-width space sentinel
  String _prevKbText = '\u200b';
  bool _kbVisible = false;

  // Desktop hardware keyboard capture (Windows/macOS/Linux viewer)
  // HardwareKeyboard.addHandler works without focus — reliable for remote desktop.
  bool Function(KeyEvent)? _hwKeyHandler;
  final Set<String> _desktopMods = {}; // currently held modifier keys

  // Toolbar auto-hide
  bool _toolbarVisible = true;
  Timer? _hideTimer;

  // Sticky modifier keys (armed until next keystroke)
  final Set<String> _mods = {};

  bool get _isDesktopViewer => !kIsWeb && (
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.linux ||
    defaultTargetPlatform == TargetPlatform.macOS
  );

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _showToolbar();
    widget.session.chat.addListener(_onChatUpdate);

    // Desktop: capture all physical keyboard events via HardwareKeyboard.
    // This bypasses the FocusNode requirement and survives clicks on the remote screen.
    if (_isDesktopViewer) {
      _kbVisible = true; // show modifier row by default on desktop
      _hwKeyHandler = _handleHardwareKeyEvent;
      HardwareKeyboard.instance.addHandler(_hwKeyHandler!);
    }
  }

  void _onChatUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.session.chat.removeListener(_onChatUpdate);
    if (_hwKeyHandler != null) {
      HardwareKeyboard.instance.removeHandler(_hwKeyHandler!);
    }
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _longPressTimer?.cancel();
    _hideTimer?.cancel();
    _kbFocus.dispose();
    _kbController.dispose();
    super.dispose();
  }

  // ── toolbar auto-hide ───────────────────────────────────────────────────────

  // Only resets the hide timer. Does NOT re-show the toolbar — call
  // _showToolbar() explicitly when the user wants to bring it back.
  void _resetHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_kbVisible) setState(() => _toolbarVisible = false);
    });
  }

  void _showToolbar() {
    _hideTimer?.cancel();
    setState(() => _toolbarVisible = true);
    _resetHideTimer();
  }

  // ── coordinate mapping ──────────────────────────────────────────────────────
  // Letterbox-aware: accounts for black bars added by RTCVideoViewObjectFitContain.
  // Also reverses the local zoom/pan transform so remote coordinates are correct.

  (double, double) _toVideoCoords(Offset pos, Size widgetSize, {required bool portrait}) {
    final renderer = widget.session.renderer;
    if (renderer == null) return (pos.dx, pos.dy);
    final vW = renderer.videoWidth.toDouble();
    final vH = renderer.videoHeight.toDouble();
    if (vW <= 0 || vH <= 0) return (pos.dx, pos.dy);

    // Reverse local pan + scale (scale is around widget center, pan applied after)
    final center = widgetSize.center(Offset.zero);
    final posInDisplay = (pos - _videoPan - center) / _videoScale + center;

    final vAspect = vW / vH;
    final cAspect = widgetSize.width / widgetSize.height;
    double rW, rH, oX, oY;
    if (vAspect > cAspect) {
      rW = widgetSize.width;
      rH = rW / vAspect;
      oX = 0;
      oY = (widgetSize.height - rH) / 2; // always centered (no portrait top-align)
    } else {
      rH = widgetSize.height;
      rW = rH * vAspect;
      oX = (widgetSize.width - rW) / 2;
      oY = 0;
    }
    final x = ((posInDisplay.dx - oX) / rW * vW).clamp(0.0, vW);
    final y = ((posInDisplay.dy - oY) / rH * vH).clamp(0.0, vH);
    return (x, y);
  }

  // portrait flag is stored so gesture handlers can pass it without needing context
  bool _isPortrait = true;

  void _sendMouse(String event, Offset pos, Size widgetSize,
      {int button = 0, double dx = 0, double dy = 0}) {
    final (x, y) = _toVideoCoords(pos, widgetSize, portrait: _isPortrait);
    final ev = <String, dynamic>{
      'event': event,
      'x': x,
      'y': y,
      if (button != 0) 'button': button,
      if (dx != 0) 'dx': dx,
      if (dy != 0) 'dy': dy,
    };
    widget.session.sendInput(ev);
  }

  // ── single-finger gestures ──────────────────────────────────────────────────

  void _onTouchStart(Offset local, Size widgetSize) {
    _twoFingerUsed = false;
    _prevCentroid = null;   // defensive: ensure no stale two-finger state
    _prevPinchDist = null;
    _touchStart = local;
    _lastTouch = local;
    _longPressFired = false;
    _longPressTimer = Timer(const Duration(milliseconds: 600), () {
      _longPressFired = true;
      HapticFeedback.mediumImpact();
      _sendMouse('mousedown', local, widgetSize, button: 2);
      _sendMouse('mouseup',   local, widgetSize, button: 2);
    });
  }

  void _onTouchMove(Offset local, Size widgetSize) {
    final prev = _lastTouch;
    _lastTouch = local;
    if (_touchStart != null && (local - _touchStart!).distance > 8) {
      _longPressTimer?.cancel();
    }
    if (_longPressFired || prev == null) return;
    // Single-finger drag → scroll
    final dy = (local.dy - prev.dy) * 3.0;
    final dx = (local.dx - prev.dx) * 3.0;
    _sendMouse('scroll', local, widgetSize, dx: dx, dy: -dy);
  }

  void _onTouchEnd(Offset local, Size widgetSize) {
    _longPressTimer?.cancel();
    if (_longPressFired) return;
    final start = _touchStart;
    if (start == null) return;
    if (!_twoFingerUsed && (local - start).distance < 12) {
      _resetHideTimer();
      _sendMouse('mousemove', local, widgetSize);
      _sendMouse('mousedown', local, widgetSize);
      _sendMouse('mouseup',   local, widgetSize);
    }
    _touchStart = null;
    _lastTouch = null;
    _twoFingerUsed = false;
  }

  // ── two-finger scroll ───────────────────────────────────────────────────────

  void _onTwoFingerMove(List<Offset> fingers, Size widgetSize) {
    if (fingers.length != 2) { _prevCentroid = null; _prevPinchDist = null; return; }
    _twoFingerUsed = true;
    // Hide keyboard and toolbar on two-finger gesture
    if (_kbVisible || _toolbarVisible) {
      _kbFocus.unfocus();
      _hideTimer?.cancel();
      setState(() { _kbVisible = false; _mods.clear(); _toolbarVisible = false; });
    }
    Offset sum = Offset.zero;
    for (final f in fingers) sum += f;
    final curr = sum / 2;
    final pinchDist = (fingers[0] - fingers[1]).distance;

    // Pinch to zoom
    final prevDist = _prevPinchDist;
    _prevPinchDist = pinchDist;
    if (prevDist != null && prevDist > 0) {
      final scale = (_videoScale * pinchDist / prevDist).clamp(0.5, 4.0);
      if ((scale - _videoScale).abs() > 0.005) {
        setState(() => _videoScale = scale);
      }
    }

    // Centroid movement: pan local view when zoomed, scroll remote when not
    final prev = _prevCentroid;
    _prevCentroid = curr;
    if (prev == null) return;
    final delta = curr - prev;
    if (_videoScale > 1.0) {
      setState(() => _videoPan += delta);
    } else {
      _sendMouse('scroll', curr, widgetSize, dx: delta.dx * 3.0, dy: -delta.dy * 3.0);
    }
  }

  // ── keyboard ────────────────────────────────────────────────────────────────

  void _toggleKeyboard() {
    if (_kbVisible) {
      // Hide panel → restore system keyboard so user can type freely
      if (!_isDesktopViewer) _kbFocus.requestFocus();
      setState(() { _kbVisible = false; _mods.clear(); });
      if (!_isDesktopViewer) _resetHideTimer();
    } else {
      // Show full panel → dismiss system keyboard (our grid covers digits/special keys)
      if (!_isDesktopViewer) _kbFocus.unfocus();
      setState(() => _kbVisible = true);
      _hideTimer?.cancel();
    }
  }

  void _sendCtrlKey(String char) {
    final String key, code;
    if (RegExp(r'^[a-zA-Z]$').hasMatch(char)) {
      key = char.toUpperCase();
      code = 'Key${char.toUpperCase()}';
    } else if (char == '[') {
      key = '[';
      code = 'BracketLeft';
    } else {
      key = char;
      code = char;
    }
    widget.session.sendInput({'event': 'keydown', 'key': key, 'code': code, 'mods': ['ctrl']});
    widget.session.sendInput({'event': 'keyup',   'key': key, 'code': code, 'mods': ['ctrl']});
  }

  void _toggleModifier(String mod) {
    setState(() {
      if (_mods.contains(mod)) _mods.remove(mod); else _mods.add(mod);
    });
    _prevKbText = _kbController.text;
    // Only call requestFocus when not already focused — calling it when already
    // focused can cause iOS to move the cursor away from the end.
    if (!_kbFocus.hasFocus) _kbFocus.requestFocus();
    // Pin cursor to end of accumulated text so the next keypress always appends.
    _kbController.selection =
        TextSelection.collapsed(offset: _kbController.text.length);
  }

  void _sendSpecialKey(String key, String code) {
    final mods = _mods.toList();
    widget.session.sendInput({'event': 'keydown', 'key': key, 'code': code, 'mods': mods});
    widget.session.sendInput({'event': 'keyup',   'key': key, 'code': code, 'mods': mods});
    if (_mods.isNotEmpty) setState(() => _mods.clear());
    // Re-focus so Tab/Esc can be pressed multiple times
    _kbFocus.requestFocus();
  }

  // Track text changes: diff against sentinel to detect new chars vs backspace.
  void _onKbChanged(String text) {
    final prev = _prevKbText;

    if (text.isEmpty) {
      // TextField entirely cleared — treat as one backspace
      _prevKbText = '\u200b';
      _kbController.value = const TextEditingValue(
        text: '\u200b',
        selection: TextSelection.collapsed(offset: 1),
      );
      widget.session.sendInput(
          {'event': 'keydown', 'key': 'Backspace', 'code': 'Backspace', 'mods': []});
      widget.session.sendInput(
          {'event': 'keyup', 'key': 'Backspace', 'code': 'Backspace', 'mods': []});
      return;
    }

    if (text.length > prev.length) {
      // Characters added — diff against prev to find only the new ones
      final added = text.replaceFirst('\u200b', '');
      final prevClean = prev.replaceFirst('\u200b', '');
      if (added.length > prevClean.length) {
        final newChars = added.substring(prevClean.length);
        final parts = newChars.split('\n');
        final mods = _mods.toList();
        for (int i = 0; i < parts.length; i++) {
          if (parts[i].isNotEmpty) {
            if (mods.isNotEmpty) {
              for (final ch in parts[i].runes) {
                final s = String.fromCharCode(ch);
                final upper = s.toUpperCase();
                final code = RegExp(r'^[a-zA-Z]$').hasMatch(s)
                    ? 'Key$upper'
                    : RegExp(r'^[0-9]$').hasMatch(s)
                        ? 'Digit$s'
                        : s == ' ' ? 'Space' : s;
                widget.session.sendInput({'event': 'keydown', 'key': s, 'code': code, 'mods': mods});
                widget.session.sendInput({'event': 'keyup',   'key': s, 'code': code, 'mods': mods});
              }
            } else {
              widget.session.sendInput({'event': 'paste_text', 'text': parts[i]});
            }
          }
          if (i < parts.length - 1) {
            widget.session.sendInput(
                {'event': 'keydown', 'key': 'Enter', 'code': 'Enter', 'mods': mods});
            widget.session.sendInput(
                {'event': 'keyup', 'key': 'Enter', 'code': 'Enter', 'mods': mods});
          }
        }
        if (mods.isNotEmpty) setState(() => _mods.clear());
      }
    } else if (text.length < prev.length) {
      // Backspace(s)
      final removed = prev.length - text.length;
      for (var i = 0; i < removed; i++) {
        widget.session.sendInput(
            {'event': 'keydown', 'key': 'Backspace', 'code': 'Backspace', 'mods': []});
        widget.session.sendInput(
            {'event': 'keyup', 'key': 'Backspace', 'code': 'Backspace', 'mods': []});
      }
    }

    // Track actual field content; fix cursor to end so that the next keypress
    // always appends (not inserts mid-string or replaces a selection).
    _prevKbText = text;
    _kbController.selection = TextSelection.collapsed(offset: text.length);
  }

  void _sendPaste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      widget.session.sendInput({'event': 'paste_text', 'text': data.text!});
    }
  }

  // ── desktop hardware keyboard ────────────────────────────────────────────────

  bool _handleHardwareKeyEvent(KeyEvent event) {
    if (widget.session.state != SessionState.connected) return false;
    // Don't capture keyboard when a different widget has focus (e.g. chat TextField).
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus != null && primaryFocus != _kbFocus) return false;
    final logical = event.logicalKey;
    final physical = event.physicalKey;
    final isDown = event is KeyDownEvent || event is KeyRepeatEvent;
    final isUp = event is KeyUpEvent;
    if (!isDown && !isUp) return false;

    // Track modifier keys; consume them so Flutter's own shortcuts don't fire.
    switch (logical) {
      case LogicalKeyboardKey.controlLeft:
      case LogicalKeyboardKey.controlRight:
        isDown ? _desktopMods.add('ctrl') : _desktopMods.remove('ctrl');
        return true;
      case LogicalKeyboardKey.shiftLeft:
      case LogicalKeyboardKey.shiftRight:
        isDown ? _desktopMods.add('shift') : _desktopMods.remove('shift');
        return true;
      case LogicalKeyboardKey.altLeft:
      case LogicalKeyboardKey.altRight:
        isDown ? _desktopMods.add('alt') : _desktopMods.remove('alt');
        return true;
      case LogicalKeyboardKey.metaLeft:
      case LogicalKeyboardKey.metaRight:
        isDown ? _desktopMods.add('meta') : _desktopMods.remove('meta');
        return true;
      default:
        break;
    }

    final code = _physicalKeyToCode(physical);
    if (code.isEmpty) return false;
    final mods = _desktopMods.toList();

    // Printable character with no modifiers → paste_text (handles unicode/IME).
    if (isDown && mods.isEmpty) {
      final ch = event.character;
      if (ch != null && ch.isNotEmpty) {
        final cp = ch.codeUnitAt(0);
        if (cp >= 32 && cp != 127) {
          widget.session.sendInput({'event': 'paste_text', 'text': ch});
          return true;
        }
      }
    }

    // Special keys and hotkeys → keydown / keyup with code + mods.
    final keyLabel = logical.keyLabel;
    final key = keyLabel.isNotEmpty ? keyLabel : code;
    widget.session.sendInput({
      'event': isDown ? 'keydown' : 'keyup',
      'key': key,
      'code': code,
      'mods': mods,
    });
    return true;
  }

  // "Key A" → "KeyA",  "Arrow Left" → "ArrowLeft",  "Digit 1" → "Digit1"
  static String _physicalKeyToCode(PhysicalKeyboardKey key) {
    final name = key.debugName;
    if (name == null || name.isEmpty) return '';
    return name.split(' ').map((s) => s.isEmpty ? '' : '${s[0].toUpperCase()}${s.substring(1)}').join('');
  }

  Future<void> _disconnect() async {
    await widget.session.disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  // ── build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: ListenableBuilder(
        listenable: widget.session,
        builder: (context, _) {
          final state = widget.session.state;
          if (state == SessionState.error) {
            return _buildError();
          }
          if (state != SessionState.connected || widget.session.renderer == null) {
            return _buildConnecting();
          }
          return _buildConnected();
        },
      ),
    );
  }

  Widget _buildConnecting() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(color: Colors.white38),
        const SizedBox(height: 16),
        Text(AppLocalizations.of(context).connectingWebRTC, style: const TextStyle(color: Colors.white54)),
      ]),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
          const SizedBox(height: 12),
          Text(widget.session.error,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _disconnect,
            icon: const Icon(Icons.arrow_back),
            label: Text(AppLocalizations.of(context).back),
          ),
        ]),
      ),
    );
  }

  Widget _buildConnected() {
    final renderer = widget.session.renderer;
    if (renderer == null) return _buildConnecting();
    // Also listen to the renderer so we rebuild when videoWidth/videoHeight
    // arrive (they're 0 at the moment the session first becomes connected).
    return ListenableBuilder(
      listenable: renderer,
      builder: (context, _) => _buildConnectedContent(renderer),
    );
  }

  Widget _buildConnectedContent(RTCVideoRenderer renderer) {
    final mq = MediaQuery.of(context);
    final isPortrait = mq.orientation == Orientation.portrait;
    // Store for gesture handlers (no context available there)
    _isPortrait = isPortrait;
    // In portrait, leave room for status bar / notch so touches aren't blocked
    final topOffset = isPortrait ? mq.padding.top : 0.0;

    return Stack(children: [
      // ── video + gesture layer ──────────────────────────────────────────────
      Positioned(
        left: 0, right: 0,
        top: topOffset, bottom: 0,
        child: LayoutBuilder(builder: (context, constraints) {
          final widgetSize = Size(constraints.maxWidth, constraints.maxHeight);
          final vW = renderer.videoWidth.toDouble();
          final vH = renderer.videoHeight.toDouble();

          // Explicitly size and center the video so it's reliably centered
          // regardless of RTCVideoView's internal alignment quirks on iOS.
          Widget videoWidget;
          if (vW > 0 && vH > 0) {
            final vAspect = vW / vH;
            final cAspect = widgetSize.width / widgetSize.height;
            final double dW, dH;
            if (vAspect > cAspect) {
              dW = widgetSize.width;
              dH = widgetSize.width / vAspect;
            } else {
              dH = widgetSize.height;
              dW = widgetSize.height * vAspect;
            }
            videoWidget = Center(
              child: SizedBox(
                width: dW, height: dH,
                child: RTCVideoView(renderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    mirror: false),
              ),
            );
          } else {
            videoWidget = RTCVideoView(renderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                mirror: false);
          }

          return GestureDetector(
            onTap: () {}, // tap handled by _GestureArea; don't auto-show toolbar
            child: _GestureArea(
              onTouchStart: (p) => _onTouchStart(p, widgetSize),
              onTouchMove: (p) => _onTouchMove(p, widgetSize),
              onTouchEnd: (p) => _onTouchEnd(p, widgetSize),
              onTwoFingerMove: (pts) => _onTwoFingerMove(pts, widgetSize),
              onTwoFingerEnd: () { _prevCentroid = null; _prevPinchDist = null; },
              onSecondFingerDown: () {
                _longPressTimer?.cancel();
                _longPressFired = false;
                _prevCentroid = null;
                _prevPinchDist = null;
              },
              child: ClipRect(
                child: Transform.translate(
                  offset: _videoPan,
                  child: Transform.scale(scale: _videoScale, child: videoWidget),
                ),
              ),
            ),
          );
        }),
      ),

      // ── hidden keyboard input field ────────────────────────────────────────
      Positioned(
        left: -1, top: -1, width: 1, height: 1,
        child: TextField(
          controller: _kbController,
          focusNode: _kbFocus,
          onChanged: _onKbChanged,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.multiline,
          maxLines: null,
          style: const TextStyle(fontSize: 1, color: Colors.transparent),
          decoration: const InputDecoration(border: InputBorder.none),
        ),
      ),

      // ── toolbar (+ modifier row) ───────────────────────────────────────────
      // Sit above the system keyboard when it is open.
      AnimatedPositioned(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        left: 0,
        right: 0,
        bottom: _toolbarVisible ? mq.viewInsets.bottom : -200,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_kbVisible) _buildKbPanel(),
          _buildToolbar(),
        ]),
      ),

      // ── show-toolbar handle (visible only when toolbar is hidden) ──────────
      if (!_toolbarVisible)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: GestureDetector(
            onTap: _showToolbar,
            child: Center(
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Icon(Icons.keyboard_arrow_up_rounded,
                    color: Colors.white54, size: 20),
              ),
            ),
          ),
        ),
    ]);
  }

  // ── Termius-style keyboard panel ───────────────────────────────────────────

  Widget _buildKbPanel() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D1117),
        border: Border(top: BorderSide(color: Color(0xFF30363D))),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _buildQuickRow(),
        _buildExpandedRows(),
      ]),
    );
  }

  // Quick row: Esc Tab Ctrl Alt Cmd / | ~ -  (9 equal keys, no expand toggle)
  Widget _buildQuickRow() {
    Widget k(String label, VoidCallback onTap, {bool active = false}) =>
        Expanded(child: _KbKey(label: label, active: active, onTap: onTap));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(children: [
        k('Esc',  () => _sendSpecialKey('Escape', 'Escape')),
        const SizedBox(width: 3),
        k('Tab',  () => _sendSpecialKey('Tab', 'Tab')),
        const SizedBox(width: 3),
        k('Ctrl', () => _toggleModifier('ctrl'),  active: _mods.contains('ctrl')),
        const SizedBox(width: 3),
        k('Alt',  () => _toggleModifier('alt'),   active: _mods.contains('alt')),
        const SizedBox(width: 3),
        k('Cmd',  () => _toggleModifier('meta'),  active: _mods.contains('meta')),
        const SizedBox(width: 3),
        k('/',    () => _sendSpecialKey('/', 'Slash')),
        const SizedBox(width: 3),
        k('|',    () => _sendSpecialKey('|', 'Backslash')),
        const SizedBox(width: 3),
        k('~',    () => _sendSpecialKey('~', 'Backquote')),
        const SizedBox(width: 3),
        k('-',    () => _sendSpecialKey('-', 'Minus')),
      ]),
    );
  }

  // Expanded rows: digits, ctrl shortcuts, navigation, F keys
  Widget _buildExpandedRows() {
    // Build a fixed 8-column row
    Widget row(List<_KbKey> keys) {
      return Padding(
        padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
        child: Row(
          children: [
            for (int i = 0; i < keys.length; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Expanded(child: keys[i]),
            ],
          ],
        ),
      );
    }

    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Divider(height: 1, color: Color(0xFF30363D)),
      const SizedBox(height: 4),

      // Row 1: Digits
      row([
        for (final d in ['1','2','3','4','5','6','7','8'])
          _KbKey(label: d, onTap: () => _sendSpecialKey(d, 'Digit$d')),
      ]),

      // Row 2: More digits + Shift + Space + Del + `
      row([
        for (final d in ['9','0'])
          _KbKey(label: d, onTap: () => _sendSpecialKey(d, 'Digit$d')),
        _KbKey(label: 'Shift', active: _mods.contains('shift'), onTap: () => _toggleModifier('shift')),
        _KbKey(label: 'Spc',   onTap: () => _sendSpecialKey(' ',      'Space')),
        _KbKey(label: 'Del',   onTap: () => _sendSpecialKey('Delete', 'Delete')),
        _KbKey(label: '`',     onTap: () => _sendSpecialKey('`',      'Backquote')),
        _KbKey(label: '=',     onTap: () => _sendSpecialKey('=',      'Equal')),
        _KbKey(
          label: widget.remotePlatform == 'windows' ? '⊞' : '+',
          onTap: widget.remotePlatform == 'windows'
              ? () => _sendSpecialKey('Meta', 'MetaLeft')
              : () => _sendSpecialKey('+', 'Equal'),
        ),
      ]),

      // Row 3: Terminal Ctrl shortcuts
      row([
        _KbKey(label: '^C', onTap: () => _sendCtrlKey('c')),
        _KbKey(label: '^Z', onTap: () => _sendCtrlKey('z')),
        _KbKey(label: '^A', onTap: () => _sendCtrlKey('a')),
        _KbKey(label: '^E', onTap: () => _sendCtrlKey('e')),
        _KbKey(label: '^K', onTap: () => _sendCtrlKey('k')),
        _KbKey(label: '^U', onTap: () => _sendCtrlKey('u')),
        _KbKey(label: '^W', onTap: () => _sendCtrlKey('w')),
        _KbKey(label: '^[', onTap: () => _sendCtrlKey('[')),
      ]),

      // Row 4: Navigation + arrows
      row([
        _KbKey(label: 'Home', onTap: () => _sendSpecialKey('Home',     'Home')),
        _KbKey(label: 'End',  onTap: () => _sendSpecialKey('End',      'End')),
        _KbKey(label: 'PgUp', onTap: () => _sendSpecialKey('PageUp',   'PageUp')),
        _KbKey(label: 'PgDn', onTap: () => _sendSpecialKey('PageDown', 'PageDown')),
        _KbKey(icon: Icons.arrow_back_rounded,     onTap: () => _sendSpecialKey('ArrowLeft',  'ArrowLeft')),
        _KbKey(icon: Icons.arrow_forward_rounded,  onTap: () => _sendSpecialKey('ArrowRight', 'ArrowRight')),
        _KbKey(icon: Icons.arrow_upward_rounded,   onTap: () => _sendSpecialKey('ArrowUp',    'ArrowUp')),
        _KbKey(icon: Icons.arrow_downward_rounded, onTap: () => _sendSpecialKey('ArrowDown',  'ArrowDown')),
      ]),

      // Row 5: F1–F8
      row([
        for (int i = 1; i <= 8; i++)
          _KbKey(label: 'F$i', onTap: () => _sendSpecialKey('F$i', 'F$i')),
      ]),

      // Row 6: F9–F12 + Ins + PrintScrn + Pause + ScrollLock (or placeholders)
      row([
        for (int i = 9; i <= 12; i++)
          _KbKey(label: 'F$i', onTap: () => _sendSpecialKey('F$i', 'F$i')),
        _KbKey(label: 'Ins',   onTap: () => _sendSpecialKey('Insert',     'Insert')),
        _KbKey(label: 'PrtSc', onTap: () => _sendSpecialKey('PrintScreen','PrintScreen')),
        _KbKey(label: 'Pause', onTap: () => _sendSpecialKey('Pause',      'Pause')),
        _KbKey(label: 'ScrLk', onTap: () => _sendSpecialKey('ScrollLock', 'ScrollLock')),
      ]),
    ]);
  }

  Widget _buildToolbar() {
    final bottom = MediaQuery.of(context).padding.bottom;
    final name = widget.deviceName.isNotEmpty ? widget.deviceName : AppLocalizations.of(context).remoteDesktop;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D1117),
        border: Border(top: BorderSide(color: Color(0xFF30363D))),
      ),
      padding: EdgeInsets.fromLTRB(12, 4, 6, bottom + 4),
      child: Row(children: [
        const Icon(Icons.laptop_mac, color: Colors.white30, size: 14),
        const SizedBox(width: 6),
        Expanded(
          child: Text(name,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
              overflow: TextOverflow.ellipsis),
        ),
        if (_videoScale != 1.0)
          _ActionBtn(
            icon: Icons.zoom_out_map_rounded,
            active: true,
            onTap: () => setState(() { _videoScale = 1.0; _videoPan = Offset.zero; }),
          ),
        _ActionBtn(
          icon: _kbVisible ? Icons.keyboard_hide_rounded : Icons.keyboard_rounded,
          active: _kbVisible,
          onTap: _toggleKeyboard,
        ),
        _ActionBtn(icon: Icons.content_paste_rounded, onTap: _sendPaste),
        _ChatActionBtn(unread: widget.session.chat.unreadCount, onTap: _openChat),
        _ActionBtn(
          icon: Icons.keyboard_arrow_down_rounded,
          onTap: () {
            _hideTimer?.cancel();
            setState(() => _toolbarVisible = false);
          },
        ),
        _ActionBtn(icon: Icons.close_rounded, danger: true, onTap: _disconnect),
      ]),
    );
  }

  void _openChat() {
    widget.session.chat.setPanelOpen(true);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            // Drag handle
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: ChatPanel(
                chat: widget.session.chat,
                onClose: () {
                  widget.session.chat.setPanelOpen(false);
                  Navigator.of(ctx).pop();
                },
              ),
            ),
          ],
        ),
      ),
    ).then((_) => widget.session.chat.setPanelOpen(false));
  }
}

// ── Action bar button (icon-only, compact) ────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final bool danger;

  const _ActionBtn({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? const Color(0xFFFF5033)
        : active
            ? const Color(0xFFFF5033)
            : Colors.white54;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}

// ── Chat action button (icon-only with unread badge) ──────────────────────────

class _ChatActionBtn extends StatelessWidget {
  final int unread;
  final VoidCallback onTap;
  const _ChatActionBtn({required this.unread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Stack(clipBehavior: Clip.none, children: [
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          child: Icon(Icons.chat_bubble_outline_rounded, color: Colors.white54, size: 20),
        ),
      ),
      if (unread > 0)
        Positioned(
          top: 3, right: 5,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.redAccent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              unread > 9 ? '9+' : '$unread',
              style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
            ),
          ),
        ),
    ]);
  }
}

// ── Termius-style keyboard key ────────────────────────────────────────────────

class _KbKey extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final bool active;
  final VoidCallback onTap;

  const _KbKey({
    this.label,
    this.icon,
    this.active = false,
    required this.onTap,
  }) : assert(label != null || icon != null, 'label or icon required');

  @override
  Widget build(BuildContext context) {
    const kAccent = Color(0xFFFF5033);
    final bg = active ? const Color(0x33FF5033) : const Color(0xFF21262D);
    final borderColor = active ? kAccent : const Color(0xFF30363D);
    final fgColor = active ? kAccent : Colors.white70;

    Widget content = icon != null
        ? Icon(icon, size: 15, color: fgColor)
        : Text(
            label!,
            style: TextStyle(
              color: fgColor,
              fontSize: 12,
              fontWeight: active ? FontWeight.bold : FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            textAlign: TextAlign.center,
          );

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: content,
      ),
    );
  }
}

// ── Gesture area ──────────────────────────────────────────────────────────────

class _GestureArea extends StatefulWidget {
  final Widget child;
  final ValueChanged<Offset> onTouchStart;
  final ValueChanged<Offset> onTouchMove;
  final ValueChanged<Offset> onTouchEnd;
  final ValueChanged<List<Offset>> onTwoFingerMove;
  final VoidCallback onTwoFingerEnd;
  final VoidCallback onSecondFingerDown;

  const _GestureArea({
    required this.child,
    required this.onTouchStart,
    required this.onTouchMove,
    required this.onTouchEnd,
    required this.onTwoFingerMove,
    required this.onTwoFingerEnd,
    required this.onSecondFingerDown,
  });

  @override
  State<_GestureArea> createState() => _GestureAreaState();
}

class _GestureAreaState extends State<_GestureArea> {
  final Map<int, Offset> _pointers = {};

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        _pointers[e.pointer] = e.localPosition;
        if (_pointers.length == 1) {
          widget.onTouchStart(e.localPosition);
        } else if (_pointers.length == 2) {
          widget.onSecondFingerDown(); // cancel any pending long-press
        }
      },
      onPointerMove: (e) {
        _pointers[e.pointer] = e.localPosition;
        if (_pointers.length == 1) {
          widget.onTouchMove(e.localPosition);
        } else if (_pointers.length == 2) {
          widget.onTwoFingerMove(_pointers.values.toList());
        }
      },
      onPointerUp: (e) {
        if (_pointers.length == 1) widget.onTouchEnd(e.localPosition);
        _pointers.remove(e.pointer);
        if (_pointers.isEmpty) widget.onTwoFingerEnd();
      },
      onPointerCancel: (e) {
        _pointers.remove(e.pointer);
        if (_pointers.isEmpty) widget.onTwoFingerEnd();
      },
      child: widget.child,
    );
  }
}
