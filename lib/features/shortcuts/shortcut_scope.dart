import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../player/player_controller.dart';
import '../player/ui/mini_player.dart';
import '../player/ui/fullscreen_player_page.dart';
import 'shortcut_controller.dart';
import 'shortcut_settings.dart';

/// Binds the keyboard shortcuts to the player.
///
/// Port of the "Main Application" scope of the shortcut system of the
/// Electron client.
class ShortcutScope extends ConsumerWidget {
  const ShortcutScope({
    super.key,
    required this.child,
    this.onToggleQueue,
    this.onToggleLyrics,
    this.onToggleFullscreen,
    this.onSearch,
  });

  final Widget child;
  final VoidCallback? onToggleQueue;
  final VoidCallback? onToggleLyrics;
  final VoidCallback? onToggleFullscreen;
  final VoidCallback? onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(shortcutControllerProvider);
    final player = ref.read(playerControllerProvider.notifier);

    final bindings = <ShortcutActivator, VoidCallback>{};
    for (final binding in settings.bindings) {
      final activator = parseShortcut(binding.keys);
      if (activator == null) continue;
      bindings[activator] = () => _run(context, ref, player, binding.action);
    }

    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        final focused = FocusManager.instance.primaryFocus?.context;
        if (focused != null &&
            (focused.widget is EditableText ||
                focused.findAncestorWidgetOfExactType<EditableText>() !=
                    null)) {
          return KeyEventResult.ignored;
        }
        for (final entry in bindings.entries) {
          if (entry.key.accepts(event, HardwareKeyboard.instance)) {
            entry.value();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }

  void _run(
    BuildContext context,
    WidgetRef ref,
    PlayerController player,
    ShortcutAction action,
  ) {
    switch (action) {
      case ShortcutAction.playPause:
        player.togglePlayPause();
      case ShortcutAction.nextTrack:
        player.skipNext();
      case ShortcutAction.prevTrack:
        player.skipPrevious();
      case ShortcutAction.seekForward:
        player.seek(player.position + const Duration(seconds: 10));
      case ShortcutAction.seekBackward:
        player.seek(player.position - const Duration(seconds: 10));
      case ShortcutAction.volumeUp:
        player.setVolume(player.volume + 0.05);
      case ShortcutAction.volumeDown:
        player.setVolume(player.volume - 0.05);
      case ShortcutAction.toggleMute:
        player.setVolume(player.volume > 0 ? 0 : 1);
      case ShortcutAction.search:
        if (onSearch != null) {
          onSearch!();
        } else {
          GoRouter.of(context).go('/search');
        }
      case ShortcutAction.toggleQueue:
        if (onToggleQueue != null) {
          onToggleQueue!();
        } else {
          showQueueSheet(context, ref);
        }
      case ShortcutAction.toggleLyrics:
        if (onToggleLyrics != null) {
          onToggleLyrics!();
        } else {
          showLyricsSheet(context);
        }
      case ShortcutAction.toggleFullscreen:
        if (onToggleFullscreen != null) {
          onToggleFullscreen!();
        } else {
          context.push('/player');
        }
    }
  }
}
