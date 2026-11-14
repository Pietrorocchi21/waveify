import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../library/library_controller.dart';
import '../overlay/overlay_service.dart';
import '../player/player_controller.dart';
import 'global_shortcut_service.dart';
import 'global_shortcut_settings.dart';

/// The system shortcuts of the application.
///
/// They are registered with the operating system, so they work even when
/// another window has the focus.
class GlobalShortcutController extends Notifier<GlobalShortcutSettings> {
  static const String _storageKey = 'waveify_global_shortcuts';

  @override
  GlobalShortcutSettings build() {
    // The registration cannot be awaited here: it happens in the background
    // as soon as the bindings are known.
    Future.microtask(_sync);
    return GlobalShortcutSettings.defaults();
  }

  /// Loads the saved bindings.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;

      final bindings = <GlobalShortcutBinding>[];
      for (final entry in decoded.whereType<Map>()) {
        final action = GlobalShortcutAction.fromId('${entry['action'] ?? ''}');
        final keys = '${entry['keys'] ?? ''}';
        if (action == null || keys.isEmpty) continue;
        bindings.add(GlobalShortcutBinding(action, keys));
      }
      if (bindings.isEmpty) return;

      state = GlobalShortcutSettings(bindings: bindings);
      await _sync();
    } catch (_) {
      // The defaults are used when the saved shortcuts cannot be read.
    }
  }

  /// Binds an action to a new key combination.
  Future<void> setBinding(GlobalShortcutAction action, String keys) async {
    state = state.withBinding(action, keys);
    await _save();
    await _sync();
  }

  /// Restores the default bindings.
  Future<void> reset() async {
    state = state.reset();
    await _save();
    await _sync();
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

  /// Registers the bindings with the operating system.
  Future<void> _sync() async {
    if (!globalShortcutsSupported) return;
    await ref
        .read(globalShortcutServiceProvider)
        .apply(state, onAction: _dispatch);
  }

  /// Runs the action of a shortcut.
  void _dispatch(GlobalShortcutAction action) {
    switch (action) {
      case GlobalShortcutAction.toggleOverlay:
        ref.read(overlayServiceProvider.notifier).toggle();
      case GlobalShortcutAction.quickLikeSong:
        final track = ref.read(playerControllerProvider).currentTrack;
        if (track == null) return;
        ref.read(libraryControllerProvider.notifier).toggleLike(track);
    }
  }
}

/// The global shortcut controller provider.
final globalShortcutControllerProvider =
    NotifierProvider<GlobalShortcutController, GlobalShortcutSettings>(
  GlobalShortcutController.new,
);

/// The service that talks with the operating system.
final globalShortcutServiceProvider = Provider<GlobalShortcutService>((ref) {
  final service = GlobalShortcutService();
  ref.onDispose(service.release);
  return service;
});
