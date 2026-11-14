import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'package:waveify/core/providers/app_providers.dart';
import 'package:waveify/shared/widgets/common.dart';
import 'global_shortcut_controller.dart';
import 'global_shortcut_settings.dart';
import 'shortcut_controller.dart';
import 'shortcut_settings.dart';

/// The keyboard shortcuts of the application, with a recorder to rebind them.
///
/// Two scopes are available: the shortcuts of the application, that work when
/// it has the focus, and the system shortcuts, that the operating system
/// catches even when another window is in the foreground.
class ShortcutsSettingsPage extends ConsumerStatefulWidget {
  const ShortcutsSettingsPage({super.key});

  @override
  ConsumerState<ShortcutsSettingsPage> createState() =>
      _ShortcutsSettingsPageState();
}

class _ShortcutsSettingsPageState extends ConsumerState<ShortcutsSettingsPage> {
  ShortcutAction? _recording;
  GlobalShortcutAction? _recordingGlobal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);
    final settings = ref.watch(shortcutControllerProvider);
    final controller = ref.read(shortcutControllerProvider.notifier);
    final global = ref.watch(globalShortcutControllerProvider);
    final globalController = ref.read(globalShortcutControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(t('settings.shortcuts.main_app_section')),
      ),
      body: Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text(
              t('settings.shortcuts.main_app_section'),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              t('settings.shortcuts.main_app_desc'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTertiary,
              ),
            ),
            const SizedBox(height: 20),
            for (final binding in settings.bindings)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  t(
                    'settings.shortcuts.${binding.action.translationKey}',
                  ),
                ),
                subtitle: Text(
                  binding.keys,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTertiary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                trailing: _recording == binding.action
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: const Icon(Icons.keyboard_rounded, size: 18),
                        tooltip: t('settings.shortcuts.recording_hint'),
                        onPressed: () => setState(() => _recording = binding.action),
                      ),
                onTap: _recording == binding.action
                    ? null
                    : () => setState(() => _recording = binding.action),
              ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: controller.reset,
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: Text(t('settings.shortcuts.reset_all_button')),
            ),

            // The system shortcuts, caught by the operating system.
            const SizedBox(height: 28),
            Text(
              t('settings.shortcuts.global_section'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              t('settings.shortcuts.global_desc'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTertiary,
              ),
            ),
            const SizedBox(height: 12),
            for (final binding in global.bindings)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  t(
                    'settings.shortcuts.${binding.action.translationKey}',
                  ),
                ),
                subtitle: Text(
                  binding.keys,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTertiary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                trailing: _recordingGlobal == binding.action
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: const Icon(Icons.keyboard_rounded, size: 18),
                        tooltip: t('settings.shortcuts.recording_hint'),
                        onPressed: () => setState(
                          () => _recordingGlobal = binding.action,
                        ),
                      ),
                onTap: _recordingGlobal == binding.action
                    ? null
                    : () => setState(
                        () => _recordingGlobal = binding.action,
                      ),
              ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: globalController.reset,
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: Text(t('settings.shortcuts.reset_all_button')),
            ),
          ],
        ),
        // The recorder captures the next key combination.
        if (_recording != null)
          Positioned.fill(
            child: Material(
              color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.6),
              child: ShortcutRecorder(
                action: _recording!,
                onCaptured: (keys) {
                  controller.setBinding(_recording!, keys);
                  setState(() => _recording = null);
                },
                onCancel: () => setState(() => _recording = null),
              ),
            ),
          ),
        // The recorder of the system shortcuts.
        if (_recordingGlobal != null)
          Positioned.fill(
            child: Material(
              color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.6),
              child: _GlobalRecorder(
                action: _recordingGlobal!,
                onCaptured: (keys) {
                  globalController.setBinding(_recordingGlobal!, keys);
                  setState(() => _recordingGlobal = null);
                },
                onCancel: () => setState(() => _recordingGlobal = null),
              ),
            ),
          ),
      ],
      ),
    );
  }
}

/// Wraps the recorder: it captures the next key combination.
class ShortcutRecorder extends ConsumerStatefulWidget {
  const ShortcutRecorder({
    super.key,
    required this.action,
    required this.onCaptured,
    required this.onCancel,
  });

  final ShortcutAction action;
  final void Function(String keys) onCaptured;
  final VoidCallback onCancel;

  @override
  ConsumerState<ShortcutRecorder> createState() => _ShortcutRecorderState();
}

class _ShortcutRecorderState extends ConsumerState<ShortcutRecorder> {
  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final keys = describeKeyEvent(event);
        if (keys.isEmpty) return KeyEventResult.handled;
        widget.onCaptured(keys);
        return KeyEventResult.handled;
      },
      child: const SizedBox.shrink(),
    );
  }
}

/// The recorder of the system shortcuts.
///
/// The combination is captured by the operating system, so the widget of the
/// package is used: it listens to the hardware keyboard directly.
class _GlobalRecorder extends ConsumerWidget {
  const _GlobalRecorder({
    required this.action,
    required this.onCaptured,
    required this.onCancel,
  });

  final GlobalShortcutAction action;
  final void Function(String keys) onCaptured;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translatorProvider);
    return Center(
      child: AppPanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t('settings.shortcuts.recording_hint')),
            const SizedBox(height: 16),
            HotKeyRecorder(
              onHotKeyRecorded: (hotKey) {
                final keys = describeHotKey(hotKey);
                if (keys.isEmpty) return;
                onCaptured(keys);
              },
            ),
            const SizedBox(height: 16),
            TextButton(onPressed: onCancel, child: Text(t('common.cancel'))),
          ],
        ),
      ),
    );
  }
}
