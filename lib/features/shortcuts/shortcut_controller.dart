import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'shortcut_settings.dart';

/// Holds the keyboard shortcuts of the application.
class ShortcutController extends Notifier<ShortcutSettings> {
  static const String _storageKey = 'waveify_shortcuts';

  @override
  ShortcutSettings build() {
    return ShortcutSettings.defaults();
  }

  /// Loads the saved bindings.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;

      final bindings = <ShortcutBinding>[];
      for (final entry in decoded.whereType<Map>()) {
        final action = ShortcutAction.fromId('${entry['action'] ?? ''}');
        final keys = '${entry['keys'] ?? ''}';
        if (action == null || keys.isEmpty) continue;
        bindings.add(ShortcutBinding(action, keys));
      }
      if (bindings.isEmpty) return;
      state = ShortcutSettings(bindings: bindings);
    } catch (_) {
      // The defaults are used when the saved shortcuts cannot be read.
    }
  }

  /// Binds an action to a new key combination.
  Future<void> setBinding(ShortcutAction action, String keys) async {
    state = state.withBinding(action, keys);
    await _save();
  }

  /// Restores the default bindings.
  Future<void> reset() async {
    state = state.reset();
    await _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode([
          for (final binding in state.bindings)
            {'action': binding.action.id, 'keys': binding.keys},
        ]),
      );
    } catch (_) {}
  }
}

/// The shortcut controller provider.
final shortcutControllerProvider =
    NotifierProvider<ShortcutController, ShortcutSettings>(
  ShortcutController.new,
);
