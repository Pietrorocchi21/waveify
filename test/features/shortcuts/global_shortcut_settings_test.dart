import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:waveify/features/shortcuts/global_shortcut_settings.dart';

void main() {
  group('parseGlobalHotKey', () {
    test('reads the key and the modifiers', () {
      final hotKey = parseGlobalHotKey('Alt+Shift+O');

      expect(hotKey, isNotNull);
      expect(hotKey!.key, LogicalKeyboardKey.keyO);
      expect(hotKey.modifiers, containsAll(<HotKeyModifier>[
        HotKeyModifier.alt,
        HotKeyModifier.shift,
      ]));
      expect(hotKey.modifiers, hasLength(2));
    });

    test('the scope is always the system one', () {
      final hotKey = parseGlobalHotKey('Control+L');
      expect(hotKey!.scope, HotKeyScope.system);
    });

    test('accepts the aliases of the modifiers', () {
      final hotKey = parseGlobalHotKey('Ctrl+Alt+K');
      expect(hotKey!.key, LogicalKeyboardKey.keyK);
      expect(hotKey.modifiers, contains(HotKeyModifier.control));
      expect(hotKey.modifiers, contains(HotKeyModifier.alt));
    });

    test('the identifier is kept, so the hotkey can be rebound', () {
      final hotKey = parseGlobalHotKey('Alt+Shift+O', identifier: 'toggleOverlay');
      expect(hotKey!.identifier, 'toggleOverlay');
    });

    test('rejects an empty or an unknown binding', () {
      expect(parseGlobalHotKey(''), isNull);
      expect(parseGlobalHotKey('Alt+Shift'), isNull);
      expect(parseGlobalHotKey('Alt+Shift+NotAKey'), isNull);
    });
  });

  group('describeHotKey', () {
    test('formats the hotkey as a binding', () {
      final hotKey = parseGlobalHotKey('Alt+Shift+O')!;
      expect(describeHotKey(hotKey), 'Alt+Shift+O');
    });

    test('formats a hotkey without modifiers', () {
      final hotKey = parseGlobalHotKey('L')!;
      expect(describeHotKey(hotKey), 'L');
    });

    test('the round trip keeps the binding', () {
      for (final binding in defaultGlobalShortcuts.values) {
        final hotKey = parseGlobalHotKey(binding)!;
        expect(describeHotKey(hotKey), binding);
      }
    });
  });

  group('GlobalShortcutSettings', () {
    test('the defaults are the ones of the Electron client', () {
      final settings = GlobalShortcutSettings.defaults();
      expect(
        settings.keysFor(GlobalShortcutAction.toggleOverlay),
        'Alt+Shift+O',
      );
      expect(
        settings.keysFor(GlobalShortcutAction.quickLikeSong),
        'Alt+Shift+L',
      );
    });

    test('a binding can be replaced', () {
      final settings = GlobalShortcutSettings.defaults().withBinding(
        GlobalShortcutAction.toggleOverlay,
        'Control+Shift+O',
      );
      expect(
        settings.keysFor(GlobalShortcutAction.toggleOverlay),
        'Control+Shift+O',
      );
      expect(
        settings.keysFor(GlobalShortcutAction.quickLikeSong),
        'Alt+Shift+L',
      );
    });

    test('the reset restores the defaults', () {
      final settings = GlobalShortcutSettings.defaults()
          .withBinding(GlobalShortcutAction.toggleOverlay, 'F9')
          .reset();
      expect(
        settings.keysFor(GlobalShortcutAction.toggleOverlay),
        'Alt+Shift+O',
      );
    });
  });
}
