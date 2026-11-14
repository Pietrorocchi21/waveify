import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'global_shortcut_settings.dart';

/// True when the operating system can catch the global shortcuts.
///
/// The package supports the desktop only: on the mobile the plugin is not
/// registered and the call would fail.
bool get globalShortcutsSupported =>
    Platform.isLinux || Platform.isMacOS || Platform.isWindows;

/// Registers the system shortcuts with the operating system.
///
/// The shortcuts are caught even when another application has the focus,
/// which is what distinguishes them from the in-app shortcuts.
class GlobalShortcutService {
  /// The hotkeys that are currently registered, by action.
  final Map<String, HotKey> _registered = {};

  /// Applies the bindings.
  ///
  /// The hotkeys of the previous bindings are released first, so a rebinding
  /// never leaves the old combination active.
  Future<void> apply(
    GlobalShortcutSettings settings, {
    required void Function(GlobalShortcutAction action) onAction,
  }) async {
    if (!globalShortcutsSupported) return;

    await release();

    for (final binding in settings.bindings) {
      final hotKey = parseGlobalHotKey(
        binding.keys,
        identifier: binding.action.id,
      );
      if (hotKey == null) continue;

      try {
        await HotKeyManager.instance.register(
          hotKey,
          keyDownHandler: (_) => onAction(binding.action),
        );
        _registered[binding.action.id] = hotKey;
        debugPrint('[shortcuts] registrato ${binding.keys} (${binding.action.id})');
      } catch (error) {
        // The system refuses the combinations that another application
        // already uses: the shortcut is simply not registered.
        debugPrint('[shortcuts] ${binding.keys} non registrato: $error');
      }
    }
  }

  /// Releases the registered shortcuts.
  Future<void> release() async {
    for (final hotKey in _registered.values) {
      try {
        await HotKeyManager.instance.unregister(hotKey);
      } catch (_) {
        // The hotkey may already be gone: nothing to release.
      }
    }
    _registered.clear();
  }

  /// The bindings that are currently active.
  Set<String> get activeActions => _registered.keys.toSet();

  /// The bindings that are currently active, with their combination.
  Map<String, String> get activeBindings => {
    for (final entry in _registered.entries) entry.key: entry.value.debugName,
  };
}
