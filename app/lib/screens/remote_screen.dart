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
      if (!_isDesktopViewer) _kbFocus.unfocus();
      setState(() { _kbVisible = false; _mods.clear(); });
      if (!_isDesktopViewer) _resetHideTimer();
    } else {
      setState(() => _kbVisible = true);
      if (!_isDesktopViewer) {
        // Must call requestFocus synchronously within the tap handler for iOS.
        _kbFocus.requestFocus();
        _hideTimer?.cancel();
      }
    }
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
          if (_kbVisible) _buildModifierRow(),
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

  Widget _buildModifierRow() {
    Widget sep() => Container(
      width: 1, height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: Colors.white24,
    );
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.9),
        border: const Border(top: BorderSide(color: Colors.white12)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          // ── sticky modifiers ──
          _ModKey(label: 'Ctrl',  active: _mods.contains('ctrl'),  onTap: () => _toggleModifier('ctrl')),
          _ModKey(label: 'Shift', active: _mods.contains('shift'), onTap: () => _toggleModifier('shift')),
          _ModKey(label: 'Alt',   active: _mods.contains('alt'),   onTap: () => _toggleModifier('alt')),
          _ModKey(label: 'Cmd',   active: _mods.contains('meta'),  onTap: () => _toggleModifier('meta')),
          sep(),
          // ── digits — placed early so Ctrl+B+number needs no scrolling ──
          for (final d in ['1','2','3','4','5','6','7','8','9','0'])
            _ModKey(label: d, small: true, onTap: () => _sendSpecialKey(d, 'Digit$d')),
          sep(),
          // ── editing ──
          _ModKey(label: 'Tab',   onTap: () => _sendSpecialKey('Tab',    'Tab')),
          _ModKey(label: 'Esc',   onTap: () => _sendSpecialKey('Escape', 'Escape')),
          _ModKey(label: 'Del',   onTap: () => _sendSpecialKey('Delete', 'Delete')),
          _ModKey(label: '`',     onTap: () => _sendSpecialKey('`',      'Backquote')),
          _ModKey(label: 'Space', onTap: () => _sendSpecialKey(' ',      'Space')),
          sep(),
          // ── arrow keys ──
          _ModKey(label: '←', onTap: () => _sendSpecialKey('ArrowLeft',  'ArrowLeft')),
          _ModKey(label: '↑', onTap: () => _sendSpecialKey('ArrowUp',    'ArrowUp')),
          _ModKey(label: '↓', onTap: () => _sendSpecialKey('ArrowDown',  'ArrowDown')),
          _ModKey(label: '→', onTap: () => _sendSpecialKey('ArrowRight', 'ArrowRight')),
          sep(),
          // ── navigation ──
          _ModKey(label: 'Home',  onTap: () => _sendSpecialKey('Home',     'Home')),
          _ModKey(label: 'End',   onTap: () => _sendSpecialKey('End',      'End')),
          _ModKey(label: 'PgUp',  onTap: () => _sendSpecialKey('PageUp',  'PageUp')),
          _ModKey(label: 'PgDn',  onTap: () => _sendSpecialKey('PageDown','PageDown')),
          sep(),
          // ── function keys ──
          for (int i = 1; i <= 12; i++)
            _ModKey(label: 'F$i', onTap: () => _sendSpecialKey('F$i', 'F$i')),
          // ── Win key (Windows only) ──
          if (widget.remotePlatform == 'windows') ...[
            sep(),
            _ModKey(label: '⊞', onTap: () => _sendSpecialKey('Meta', 'MetaLeft')),
          ],
        ]),
      ),
    );
  }

  Widget _buildToolbar() {
    final bottom = MediaQuery.of(context).padding.bottom;
    final name = widget.deviceName.isNotEmpty ? widget.deviceName : AppLocalizations.of(context).remoteDesktop;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.75),
        border: const Border(top: BorderSide(color: Colors.white12)),
      ),
      padding: EdgeInsets.fromLTRB(8, 6, 8, bottom + 6),
      child: Row(children: [
        // Device name
        const SizedBox(width: 4),
        const Icon(Icons.laptop_mac, color: Colors.white38, size: 16),
        const SizedBox(width: 6),
        Expanded(
          child: Text(name,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
              overflow: TextOverflow.ellipsis),
        ),
        // Zoom reset (visible only when zoomed)
        if (_videoScale != 1.0)
          _ToolbarBtn(
            icon: Icons.zoom_out_map_rounded,
            label: AppLocalizations.of(context).restore,
            active: true,
            onTap: () => setState(() { _videoScale = 1.0; _videoPan = Offset.zero; }),
          ),
        // Keyboard toggle
        _ToolbarBtn(
          icon: _kbVisible ? Icons.keyboard_hide_rounded : Icons.keyboard_rounded,
          label: AppLocalizations.of(context).keyboard,
          active: _kbVisible,
          onTap: _toggleKeyboard,
        ),
        // Paste
        _ToolbarBtn(
          icon: Icons.content_paste_rounded,
          label: AppLocalizations.of(context).paste,
          onTap: _sendPaste,
        ),
        // Chat
        _ChatToolbarBtn(
          unread: widget.session.chat.unreadCount,
          onTap: _openChat,
        ),
        // Hide toolbar
        _ToolbarBtn(
          icon: Icons.keyboard_arrow_down_rounded,
          label: AppLocalizations.of(context).hide,
          onTap: () {
            _hideTimer?.cancel();
            setState(() => _toolbarVisible = false);
          },
        ),
        // Disconnect
        _ToolbarBtn(
          icon: Icons.close_rounded,
          label: AppLocalizations.of(context).disconnect,
          danger: true,
          onTap: _disconnect,
        ),
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

// ── Chat toolbar button (with unread badge) ────────────────────────────────────

class _ChatToolbarBtn extends StatelessWidget {
  final int unread;
  final VoidCallback onTap;
  const _ChatToolbarBtn({required this.unread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white70, size: 22),
              const SizedBox(height: 2),
              Text(AppLocalizations.of(context).chat, style: const TextStyle(color: Colors.white70, fontSize: 10)),
            ]),
          ),
        ),
        if (unread > 0)
          Positioned(
            top: 2,
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                unread > 9 ? '9+' : '$unread',
                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Toolbar button ─────────────────────────────────────────────────────────────

class _ToolbarBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool danger;

  const _ToolbarBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? Colors.redAccent
        : active
            ? Theme.of(context).colorScheme.primary
            : Colors.white70;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: color, fontSize: 10)),
        ]),
      ),
    );
  }
}

// ── Modifier key chip ─────────────────────────────────────────────────────────

class _ModKey extends StatelessWidget {
  final String label;
  final bool active;
  final bool small;   // compact style for digit keys
  final VoidCallback onTap;

  const _ModKey({
    required this.label,
    required this.onTap,
    this.active = false,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: small ? 2 : 3, vertical: 2),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
            horizontal: small ? 9 : 12,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: active
                ? Theme.of(context).colorScheme.primary.withOpacity(0.85)
                : Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white24,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : Colors.white70,
              fontSize: small ? 12 : 13,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
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
