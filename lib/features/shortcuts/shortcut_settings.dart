import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The actions that can be bound to a key.
enum ShortcutAction {
  playPause('playPause', 'play_pause'),
  nextTrack('nextTrack', 'next_track'),
  prevTrack('prevTrack', 'prev_track'),
  seekForward('seekForward', 'seek_forward'),
  seekBackward('seekBackward', 'seek_backward'),
  volumeUp('volumeUp', 'volume_up'),
  volumeDown('volumeDown', 'volume_down'),
  toggleMute('toggleMute', 'toggle_mute'),
  search('search', 'search'),
  toggleQueue('toggleQueue', 'toggle_queue'),
  toggleLyrics('toggleLyrics', 'toggle_lyrics'),
  toggleFullscreen('toggleFullscreen', 'toggle_fullscreen');

  const ShortcutAction(this.id, this.translationKey);

  final String id;

  /// The key of the translation, the one of the Electron client.
  final String translationKey;

  static ShortcutAction? fromId(String id) {
    for (final action in ShortcutAction.values) {
      if (action.id == id) return action;
    }
    return null;
  }
}

/// The default bindings of the main application.
///
/// Port of `DEFAULT_SHORTCUTS.mainApp` in `src/features/shortcuts/types.ts`.
const Map<ShortcutAction, String> defaultShortcuts = {
  ShortcutAction.playPause: 'Space',
  ShortcutAction.nextTrack: 'Control+Right',
  ShortcutAction.prevTrack: 'Control+Left',
  ShortcutAction.seekForward: 'Right',
  ShortcutAction.seekBackward: 'Left',
  ShortcutAction.volumeUp: 'Up',
  ShortcutAction.volumeDown: 'Down',
  ShortcutAction.toggleMute: 'M',
  ShortcutAction.search: '/',
  ShortcutAction.toggleQueue: 'Q',
  ShortcutAction.toggleLyrics: 'L',
  ShortcutAction.toggleFullscreen: 'F',
};

/// A shortcut binding, stored as a readable string.
class ShortcutBinding {
  const ShortcutBinding(this.action, this.keys);

  final ShortcutAction action;

  /// The binding, e.g. `Control+Right`.
  final String keys;

  ShortcutBinding copyWith({String? keys}) => ShortcutBinding(action, keys ?? this.keys);
}

/// The keyboard shortcuts of the application.
class ShortcutSettings {
  const ShortcutSettings({required this.bindings});

  factory ShortcutSettings.defaults() {
    return ShortcutSettings(
      bindings: [
        for (final entry in defaultShortcuts.entries)
          ShortcutBinding(entry.key, entry.value),
      ],
    );
  }

  final List<ShortcutBinding> bindings;

  String keysFor(ShortcutAction action) {
    for (final binding in bindings) {
      if (binding.action == action) return binding.keys;
    }
    return defaultShortcuts[action] ?? '';
  }

  ShortcutSettings withBinding(ShortcutAction action, String keys) {
    return ShortcutSettings(
      bindings: [
        for (final binding in bindings)
          if (binding.action == action) binding.copyWith(keys: keys) else binding,
      ],
    );
  }

  /// Restores the default bindings.
  ShortcutSettings reset() => ShortcutSettings.defaults();
}

/// The parts of a key combination.
class ShortcutParts {
  const ShortcutParts({
    required this.key,
    this.control = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
  });

  final LogicalKeyboardKey key;
  final bool control;
  final bool shift;
  final bool alt;
  final bool meta;
}

/// Splits a binding string into its parts.
///
/// The syntax is the one of the Electron client: the modifiers
/// (`Control`, `Shift`, `Alt`, `Meta`) followed by the key.
ShortcutParts? parseShortcutParts(String raw) {
  final parts = raw
      .split('+')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return null;

  var control = false;
  var shift = false;
  var alt = false;
  var meta = false;
  var key = '';

  for (final part in parts) {
    switch (part.toLowerCase()) {
      case 'control':
      case 'ctrl':
        control = true;
      case 'shift':
        shift = true;
      case 'alt':
      case 'option':
        alt = true;
      case 'meta':
      case 'cmd':
      case 'command':
        meta = true;
      default:
        key = part;
    }
  }

  if (key.isEmpty) return null;
  final logicalKey = logicalKeyFor(key);
  if (logicalKey == null) return null;

  return ShortcutParts(
    key: logicalKey,
    control: control,
    shift: shift,
    alt: alt,
    meta: meta,
  );
}

/// Converts a binding string into a Flutter activator.
SingleActivator? parseShortcut(String raw) {
  final parts = parseShortcutParts(raw);
  if (parts == null) return null;

  return SingleActivator(
    parts.key,
    control: parts.control,
    shift: parts.shift,
    alt: parts.alt,
    meta: parts.meta,
  );
}

/// The logical key of a key name.
LogicalKeyboardKey? logicalKeyFor(String name) {
  switch (name.toLowerCase()) {
    case 'space':
      return LogicalKeyboardKey.space;
    case 'up':
    case 'arrowup':
      return LogicalKeyboardKey.arrowUp;
    case 'down':
    case 'arrowdown':
      return LogicalKeyboardKey.arrowDown;
    case 'left':
    case 'arrowleft':
      return LogicalKeyboardKey.arrowLeft;
    case 'right':
    case 'arrowright':
      return LogicalKeyboardKey.arrowRight;
    case 'enter':
    case 'return':
      return LogicalKeyboardKey.enter;
    case 'escape':
    case 'esc':
      return LogicalKeyboardKey.escape;
    case 'tab':
      return LogicalKeyboardKey.tab;
    case 'backspace':
      return LogicalKeyboardKey.backspace;
    case 'delete':
      return LogicalKeyboardKey.delete;
    case 'home':
      return LogicalKeyboardKey.home;
    case 'end':
      return LogicalKeyboardKey.end;
    case 'pageup':
      return LogicalKeyboardKey.pageUp;
    case 'pagedown':
      return LogicalKeyboardKey.pageDown;
    case '/':
    case 'slash':
      return LogicalKeyboardKey.slash;
    case '.':
    case 'period':
      return LogicalKeyboardKey.period;
    case ',':
    case 'comma':
      return LogicalKeyboardKey.comma;
    case ';':
    case 'semicolon':
      return LogicalKeyboardKey.semicolon;
    case '-':
    case 'minus':
      return LogicalKeyboardKey.minus;
    case '=':
    case 'equal':
      return LogicalKeyboardKey.equal;
    case '\\':
    case 'backslash':
      return LogicalKeyboardKey.backslash;
    case "'":
    case 'quote':
      return LogicalKeyboardKey.quote;
    case '[':
    case 'bracketleft':
      return LogicalKeyboardKey.bracketLeft;
    case ']':
    case 'bracketright':
      return LogicalKeyboardKey.bracketRight;
    default:
      break;
  }

  if (name.length == 1) {
    final upper = name.toUpperCase();
    final letter = _letters[upper];
    if (letter != null) return letter;
    final digitIndex = int.tryParse(name) ?? -1;
    if (digitIndex >= 0 && digitIndex < _digits.length) {
      final digit = _digits[digitIndex];
      if (digit != null) return digit;
    }
  }

  return null;
}

/// The letters of the keyboard.
const Map<String, LogicalKeyboardKey> _letters = {
  'A': LogicalKeyboardKey.keyA,
  'B': LogicalKeyboardKey.keyB,
  'C': LogicalKeyboardKey.keyC,
  'D': LogicalKeyboardKey.keyD,
  'E': LogicalKeyboardKey.keyE,
  'F': LogicalKeyboardKey.keyF,
  'G': LogicalKeyboardKey.keyG,
  'H': LogicalKeyboardKey.keyH,
  'I': LogicalKeyboardKey.keyI,
  'J': LogicalKeyboardKey.keyJ,
  'K': LogicalKeyboardKey.keyK,
  'L': LogicalKeyboardKey.keyL,
  'M': LogicalKeyboardKey.keyM,
  'N': LogicalKeyboardKey.keyN,
  'O': LogicalKeyboardKey.keyO,
  'P': LogicalKeyboardKey.keyP,
  'Q': LogicalKeyboardKey.keyQ,
  'R': LogicalKeyboardKey.keyR,
  'S': LogicalKeyboardKey.keyS,
  'T': LogicalKeyboardKey.keyT,
  'U': LogicalKeyboardKey.keyU,
  'V': LogicalKeyboardKey.keyV,
  'W': LogicalKeyboardKey.keyW,
  'X': LogicalKeyboardKey.keyX,
  'Y': LogicalKeyboardKey.keyY,
  'Z': LogicalKeyboardKey.keyZ,
};

/// The digits of the main block.
const List<LogicalKeyboardKey?> _digits = [
  LogicalKeyboardKey.digit0,
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

/// Formats a key event as a binding string, for the recorder.
String describeKeyEvent(KeyEvent event) {
  final key = event.logicalKey;
  if (key == LogicalKeyboardKey.space) return 'Space';

  final label = _labelFor(key);
  if (label == null) return '';

  final keyboard = HardwareKeyboard.instance;
  final parts = <String>[];
  if (keyboard.isControlPressed) parts.add('Control');
  if (keyboard.isShiftPressed) parts.add('Shift');
  if (keyboard.isAltPressed) parts.add('Alt');
  if (keyboard.isMetaPressed) parts.add('Meta');
  parts.add(label);
  return parts.join('+');
}

/// The label of a logical key, e.g. `Space` or `A`.
String? keyLabel(LogicalKeyboardKey key) => _labelFor(key);

/// The label of a physical key, e.g. `Space` or `A`.
String? physicalKeyLabel(PhysicalKeyboardKey key) {
  final name = key.debugName;
  if (name == null || name.isEmpty) return null;
  if (name == 'Space') return 'Space';

  // The letters and the digits of the main block are named "Key A" and
  // "Digit 1".
  for (final prefix in const ['Key ', 'Digit ', 'Numpad ']) {
    if (name.startsWith(prefix)) {
      return name.substring(prefix.length).toUpperCase();
    }
  }
  return null;
}

String? _labelFor(LogicalKeyboardKey key) {  if (key == LogicalKeyboardKey.arrowUp) return 'Up';
  if (key == LogicalKeyboardKey.arrowDown) return 'Down';
  if (key == LogicalKeyboardKey.arrowLeft) return 'Left';
  if (key == LogicalKeyboardKey.arrowRight) return 'Right';
  if (key == LogicalKeyboardKey.enter) return 'Enter';
  if (key == LogicalKeyboardKey.escape) return 'Escape';
  if (key == LogicalKeyboardKey.tab) return 'Tab';
  if (key == LogicalKeyboardKey.backspace) return 'Backspace';
  if (key == LogicalKeyboardKey.delete) return 'Delete';
  if (key == LogicalKeyboardKey.home) return 'Home';
  if (key == LogicalKeyboardKey.end) return 'End';
  if (key == LogicalKeyboardKey.pageUp) return 'PageUp';
  if (key == LogicalKeyboardKey.pageDown) return 'PageDown';
  if (key == LogicalKeyboardKey.slash) return '/';
  if (key == LogicalKeyboardKey.period) return '.';
  if (key == LogicalKeyboardKey.comma) return ',';
  if (key == LogicalKeyboardKey.semicolon) return ';';
  if (key == LogicalKeyboardKey.minus) return '-';
  if (key == LogicalKeyboardKey.equal) return '=';
  if (key == LogicalKeyboardKey.backslash) return '\\';
  if (key == LogicalKeyboardKey.quote) return "'";
  if (key == LogicalKeyboardKey.bracketLeft) return '[';
  if (key == LogicalKeyboardKey.bracketRight) return ']';

  for (final entry in _letters.entries) {
    if (entry.value.keyId == key.keyId) return entry.key;
  }

  final digitIndex = _digits.indexWhere((k) => k?.keyId == key.keyId);
  if (digitIndex >= 0) return '$digitIndex';

  return null;
}
