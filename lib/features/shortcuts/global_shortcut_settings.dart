import 'package:hotkey_manager/hotkey_manager.dart';

import 'shortcut_settings.dart';

/// The actions that work even when another window has the focus.
///
/// Port of the "Global" scope of the shortcut system of the Electron client.
enum GlobalShortcutAction {
  toggleOverlay('toggleOverlay', 'toggle_overlay'),
  quickLikeSong('quickLikeSong', 'quick_like_song');

  const GlobalShortcutAction(this.id, this.translationKey);

  final String id;

  /// The key of the translation, the one of the Electron client.
  final String translationKey;

  static GlobalShortcutAction? fromId(String id) {
    for (final action in GlobalShortcutAction.values) {
      if (action.id == id) return action;
    }
    return null;
  }
}

/// The default bindings of the system scope.
///
/// Port of `DEFAULT_SHORTCUTS.global` of the Electron client.
const Map<GlobalShortcutAction, String> defaultGlobalShortcuts = {
  GlobalShortcutAction.toggleOverlay: 'Alt+Shift+O',
  GlobalShortcutAction.quickLikeSong: 'Alt+Shift+L',
};

/// A system shortcut binding, stored as a readable string.
class GlobalShortcutBinding {
  const GlobalShortcutBinding(this.action, this.keys);

  final GlobalShortcutAction action;

  /// The binding, e.g. `Alt+Shift+O`.
  final String keys;

  GlobalShortcutBinding copyWith({String? keys}) =>
      GlobalShortcutBinding(action, keys ?? this.keys);
}

/// The system shortcuts of the application.
class GlobalShortcutSettings {
  const GlobalShortcutSettings({required this.bindings});

  factory GlobalShortcutSettings.defaults() {
    return GlobalShortcutSettings(
      bindings: [
        for (final entry in defaultGlobalShortcuts.entries)
          GlobalShortcutBinding(entry.key, entry.value),
      ],
    );
  }

  final List<GlobalShortcutBinding> bindings;

  String keysFor(GlobalShortcutAction action) {
    for (final binding in bindings) {
      if (binding.action == action) return binding.keys;
    }
    return defaultGlobalShortcuts[action] ?? '';
  }

  GlobalShortcutSettings withBinding(
    GlobalShortcutAction action,
    String keys,
  ) {
    return GlobalShortcutSettings(
      bindings: [
        for (final binding in bindings)
          if (binding.action == action)
            binding.copyWith(keys: keys)
          else
            binding,
      ],
    );
  }

  /// Restores the default bindings.
  GlobalShortcutSettings reset() => GlobalShortcutSettings.defaults();
}

/// Converts a binding string into a system hotkey.
///
/// The scope is always [HotKeyScope.system]: the shortcut is caught by the
/// operating system, so it works while another application has the focus.
/// The identifier is stable, so the hotkey can be registered again after a
/// rebinding without leaving the old one active.
HotKey? parseGlobalHotKey(String raw, {String? identifier}) {
  final parts = parseShortcutParts(raw);
  if (parts == null) return null;

  // The modifiers keep the canonical order, so the binding that is written
  // and the one that is read always look the same.
  final modifiers = <HotKeyModifier>[];
  if (parts.control) modifiers.add(HotKeyModifier.control);
  if (parts.alt) modifiers.add(HotKeyModifier.alt);
  if (parts.shift) modifiers.add(HotKeyModifier.shift);
  if (parts.meta) modifiers.add(HotKeyModifier.meta);

  return HotKey(
    identifier: identifier,
    key: parts.key,
    modifiers: modifiers,
    scope: HotKeyScope.system,
  );
}

/// Formats a hotkey as a binding string, for the recorder.
String describeHotKey(HotKey hotKey) {
  final label = physicalKeyLabel(hotKey.physicalKey);
  if (label == null) return '';

  final modifiers = hotKey.modifiers ?? const <HotKeyModifier>[];
  final parts = <String>[];
  if (modifiers.contains(HotKeyModifier.control)) parts.add('Control');
  if (modifiers.contains(HotKeyModifier.alt)) parts.add('Alt');
  if (modifiers.contains(HotKeyModifier.shift)) parts.add('Shift');
  if (modifiers.contains(HotKeyModifier.meta)) parts.add('Meta');
  parts.add(label);
  return parts.join('+');
}
