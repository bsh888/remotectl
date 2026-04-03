import 'package:flutter/services.dart';

/// Maps Flutter physical/logical keys to web-compatible KeyboardEvent values.
///
/// The agent expects:
///   key  → KeyboardEvent.key  (e.g. "a", "A", "Enter", "Control")
///   code → KeyboardEvent.code (e.g. "KeyA", "ControlLeft", "Enter")
class KeyMapper {
  KeyMapper._();

  /// Physical key → web KeyboardEvent.code (locale-independent position).
  static String physicalToCode(PhysicalKeyboardKey key) {
    final mapped = _physicalToCode[key];
    if (mapped != null) return mapped;
    // Fallback: Flutter debugName "Key A" → "KeyA", "Arrow Up" → "ArrowUp"
    final name = key.debugName ?? '';
    return name.replaceAll(' ', '');
  }

  /// Logical key → web KeyboardEvent.key (character or key name).
  static String logicalToKey(LogicalKeyboardKey key) {
    final label = key.keyLabel;
    // Single printable character
    if (label.length == 1) return label;
    return _logicalToKey[key] ?? key.debugName?.replaceAll(' ', '') ?? 'Unknown';
  }

  // ── Physical key → code ───────────────────────────────────────────────────

  static final Map<PhysicalKeyboardKey, String> _physicalToCode = {
    // Letters
    PhysicalKeyboardKey.keyA: 'KeyA', PhysicalKeyboardKey.keyB: 'KeyB',
    PhysicalKeyboardKey.keyC: 'KeyC', PhysicalKeyboardKey.keyD: 'KeyD',
    PhysicalKeyboardKey.keyE: 'KeyE', PhysicalKeyboardKey.keyF: 'KeyF',
    PhysicalKeyboardKey.keyG: 'KeyG', PhysicalKeyboardKey.keyH: 'KeyH',
    PhysicalKeyboardKey.keyI: 'KeyI', PhysicalKeyboardKey.keyJ: 'KeyJ',
    PhysicalKeyboardKey.keyK: 'KeyK', PhysicalKeyboardKey.keyL: 'KeyL',
    PhysicalKeyboardKey.keyM: 'KeyM', PhysicalKeyboardKey.keyN: 'KeyN',
    PhysicalKeyboardKey.keyO: 'KeyO', PhysicalKeyboardKey.keyP: 'KeyP',
    PhysicalKeyboardKey.keyQ: 'KeyQ', PhysicalKeyboardKey.keyR: 'KeyR',
    PhysicalKeyboardKey.keyS: 'KeyS', PhysicalKeyboardKey.keyT: 'KeyT',
    PhysicalKeyboardKey.keyU: 'KeyU', PhysicalKeyboardKey.keyV: 'KeyV',
    PhysicalKeyboardKey.keyW: 'KeyW', PhysicalKeyboardKey.keyX: 'KeyX',
    PhysicalKeyboardKey.keyY: 'KeyY', PhysicalKeyboardKey.keyZ: 'KeyZ',
    // Digits
    PhysicalKeyboardKey.digit0: 'Digit0', PhysicalKeyboardKey.digit1: 'Digit1',
    PhysicalKeyboardKey.digit2: 'Digit2', PhysicalKeyboardKey.digit3: 'Digit3',
    PhysicalKeyboardKey.digit4: 'Digit4', PhysicalKeyboardKey.digit5: 'Digit5',
    PhysicalKeyboardKey.digit6: 'Digit6', PhysicalKeyboardKey.digit7: 'Digit7',
    PhysicalKeyboardKey.digit8: 'Digit8', PhysicalKeyboardKey.digit9: 'Digit9',
    // Function keys
    PhysicalKeyboardKey.f1:  'F1',  PhysicalKeyboardKey.f2:  'F2',
    PhysicalKeyboardKey.f3:  'F3',  PhysicalKeyboardKey.f4:  'F4',
    PhysicalKeyboardKey.f5:  'F5',  PhysicalKeyboardKey.f6:  'F6',
    PhysicalKeyboardKey.f7:  'F7',  PhysicalKeyboardKey.f8:  'F8',
    PhysicalKeyboardKey.f9:  'F9',  PhysicalKeyboardKey.f10: 'F10',
    PhysicalKeyboardKey.f11: 'F11', PhysicalKeyboardKey.f12: 'F12',
    // Modifiers
    PhysicalKeyboardKey.shiftLeft:    'ShiftLeft',
    PhysicalKeyboardKey.shiftRight:   'ShiftRight',
    PhysicalKeyboardKey.controlLeft:  'ControlLeft',
    PhysicalKeyboardKey.controlRight: 'ControlRight',
    PhysicalKeyboardKey.altLeft:      'AltLeft',
    PhysicalKeyboardKey.altRight:     'AltRight',
    PhysicalKeyboardKey.metaLeft:     'MetaLeft',
    PhysicalKeyboardKey.metaRight:    'MetaRight',
    // Navigation
    PhysicalKeyboardKey.arrowUp:    'ArrowUp',
    PhysicalKeyboardKey.arrowDown:  'ArrowDown',
    PhysicalKeyboardKey.arrowLeft:  'ArrowLeft',
    PhysicalKeyboardKey.arrowRight: 'ArrowRight',
    PhysicalKeyboardKey.home:       'Home',
    PhysicalKeyboardKey.end:        'End',
    PhysicalKeyboardKey.pageUp:     'PageUp',
    PhysicalKeyboardKey.pageDown:   'PageDown',
    PhysicalKeyboardKey.insert:     'Insert',
    PhysicalKeyboardKey.delete:     'Delete',
    // Common
    PhysicalKeyboardKey.enter:         'Enter',
    PhysicalKeyboardKey.numpadEnter:   'NumpadEnter',
    PhysicalKeyboardKey.space:         'Space',
    PhysicalKeyboardKey.tab:           'Tab',
    PhysicalKeyboardKey.backspace:     'Backspace',
    PhysicalKeyboardKey.escape:        'Escape',
    PhysicalKeyboardKey.capsLock:      'CapsLock',
    PhysicalKeyboardKey.numLock:       'NumLock',
    PhysicalKeyboardKey.scrollLock:    'ScrollLock',
    PhysicalKeyboardKey.printScreen:   'PrintScreen',
    PhysicalKeyboardKey.pause:         'Pause',
    // Punctuation (US layout)
    PhysicalKeyboardKey.minus:            'Minus',
    PhysicalKeyboardKey.equal:            'Equal',
    PhysicalKeyboardKey.bracketLeft:      'BracketLeft',
    PhysicalKeyboardKey.bracketRight:     'BracketRight',
    PhysicalKeyboardKey.backslash:        'Backslash',
    PhysicalKeyboardKey.semicolon:        'Semicolon',
    PhysicalKeyboardKey.quote:            'Quote',
    PhysicalKeyboardKey.backquote:        'Backquote',
    PhysicalKeyboardKey.comma:            'Comma',
    PhysicalKeyboardKey.period:           'Period',
    PhysicalKeyboardKey.slash:            'Slash',
    // Numpad
    PhysicalKeyboardKey.numpad0: 'Numpad0', PhysicalKeyboardKey.numpad1: 'Numpad1',
    PhysicalKeyboardKey.numpad2: 'Numpad2', PhysicalKeyboardKey.numpad3: 'Numpad3',
    PhysicalKeyboardKey.numpad4: 'Numpad4', PhysicalKeyboardKey.numpad5: 'Numpad5',
    PhysicalKeyboardKey.numpad6: 'Numpad6', PhysicalKeyboardKey.numpad7: 'Numpad7',
    PhysicalKeyboardKey.numpad8: 'Numpad8', PhysicalKeyboardKey.numpad9: 'Numpad9',
    PhysicalKeyboardKey.numpadAdd:      'NumpadAdd',
    PhysicalKeyboardKey.numpadSubtract: 'NumpadSubtract',
    PhysicalKeyboardKey.numpadMultiply: 'NumpadMultiply',
    PhysicalKeyboardKey.numpadDivide:   'NumpadDivide',
    PhysicalKeyboardKey.numpadDecimal:  'NumpadDecimal',
  };

  // ── Logical key → key name ────────────────────────────────────────────────

  static final Map<LogicalKeyboardKey, String> _logicalToKey = {
    LogicalKeyboardKey.enter:        'Enter',
    LogicalKeyboardKey.numpadEnter:  'Enter',
    LogicalKeyboardKey.tab:          'Tab',
    LogicalKeyboardKey.backspace:    'Backspace',
    LogicalKeyboardKey.escape:       'Escape',
    LogicalKeyboardKey.delete:       'Delete',
    LogicalKeyboardKey.insert:       'Insert',
    LogicalKeyboardKey.home:         'Home',
    LogicalKeyboardKey.end:          'End',
    LogicalKeyboardKey.pageUp:       'PageUp',
    LogicalKeyboardKey.pageDown:     'PageDown',
    LogicalKeyboardKey.arrowUp:      'ArrowUp',
    LogicalKeyboardKey.arrowDown:    'ArrowDown',
    LogicalKeyboardKey.arrowLeft:    'ArrowLeft',
    LogicalKeyboardKey.arrowRight:   'ArrowRight',
    LogicalKeyboardKey.space:        ' ',
    LogicalKeyboardKey.shift:        'Shift',
    LogicalKeyboardKey.shiftLeft:    'Shift',
    LogicalKeyboardKey.shiftRight:   'Shift',
    LogicalKeyboardKey.control:      'Control',
    LogicalKeyboardKey.controlLeft:  'Control',
    LogicalKeyboardKey.controlRight: 'Control',
    LogicalKeyboardKey.alt:          'Alt',
    LogicalKeyboardKey.altLeft:      'Alt',
    LogicalKeyboardKey.altRight:     'Alt',
    LogicalKeyboardKey.meta:         'Meta',
    LogicalKeyboardKey.metaLeft:     'Meta',
    LogicalKeyboardKey.metaRight:    'Meta',
    LogicalKeyboardKey.capsLock:     'CapsLock',
    LogicalKeyboardKey.numLock:      'NumLock',
    LogicalKeyboardKey.scrollLock:   'ScrollLock',
    LogicalKeyboardKey.printScreen:  'PrintScreen',
    LogicalKeyboardKey.pause:        'Pause',
    LogicalKeyboardKey.f1:  'F1',  LogicalKeyboardKey.f2:  'F2',
    LogicalKeyboardKey.f3:  'F3',  LogicalKeyboardKey.f4:  'F4',
    LogicalKeyboardKey.f5:  'F5',  LogicalKeyboardKey.f6:  'F6',
    LogicalKeyboardKey.f7:  'F7',  LogicalKeyboardKey.f8:  'F8',
    LogicalKeyboardKey.f9:  'F9',  LogicalKeyboardKey.f10: 'F10',
    LogicalKeyboardKey.f11: 'F11', LogicalKeyboardKey.f12: 'F12',
  };

  /// Is this key a modifier key?
  static bool isModifier(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.shift ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.control ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.alt ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.meta ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight ||
        key == LogicalKeyboardKey.capsLock;
  }

  /// Is this key a Control key?
  static bool isControl(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.control ||
      key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight;

  /// Is this key a Meta (Cmd/Win) key?
  static bool isMeta(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.meta ||
      key == LogicalKeyboardKey.metaLeft ||
      key == LogicalKeyboardKey.metaRight;
}
