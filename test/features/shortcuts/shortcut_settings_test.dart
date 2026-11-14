import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waveify/features/shortcuts/shortcut_settings.dart';

void main() {
  group('parseShortcut', () {
    test('parses a single key', () {
      final activator = parseShortcut('Space');
      expect(activator, isNotNull);
      expect(activator!.trigger, LogicalKeyboardKey.space);
    });

    test('parses the arrow keys', () {
      expect(parseShortcut('Right')?.trigger, LogicalKeyboardKey.arrowRight);
      expect(parseShortcut('Left')?.trigger, LogicalKeyboardKey.arrowLeft);
      expect(parseShortcut('Up')?.trigger, LogicalKeyboardKey.arrowUp);
      expect(parseShortcut('Down')?.trigger, LogicalKeyboardKey.arrowDown);
    });

    test('parses a letter', () {
      expect(parseShortcut('M')?.trigger.keyId,
          LogicalKeyboardKey.keyM.keyId);
      expect(parseShortcut('q')?.trigger.keyId,
          LogicalKeyboardKey.keyQ.keyId);
    });

    test('parses a digit', () {
      expect(parseShortcut('5')?.trigger.keyId,
          LogicalKeyboardKey.digit5.keyId);
    });

    test('parses the modifiers', () {
      final activator = parseShortcut('Control+Right');
      expect(activator, isNotNull);
      expect(activator!.trigger, LogicalKeyboardKey.arrowRight);
      expect(activator.control, isTrue);
      expect(activator.shift, isFalse);
    });

    test('parses several modifiers', () {
      final activator = parseShortcut('Control+Shift+Alt+Left');
      expect(activator!.control, isTrue);
      expect(activator.shift, isTrue);
      expect(activator.alt, isTrue);
      expect(activator.trigger, LogicalKeyboardKey.arrowLeft);
    });

    test('accepts the alternative names of the modifiers', () {
      expect(parseShortcut('Ctrl+Right')?.control, isTrue);
      expect(parseShortcut('Cmd+Right')?.meta, isTrue);
      expect(parseShortcut('Option+Right')?.alt, isTrue);
    });

    test('rejects an empty or invalid binding', () {
      expect(parseShortcut(''), isNull);
      expect(parseShortcut('   '), isNull);
      expect(parseShortcut('Control'), isNull);
      expect(parseShortcut('NotAKey'), isNull);
    });

    test('parses every default binding', () {
      for (final entry in defaultShortcuts.entries) {
        expect(
          parseShortcut(entry.value),
          isNotNull,
          reason: 'the default binding of ${entry.key.id} is not parsable',
        );
      }
    });
  });

  group('ShortcutSettings', () {
    test('the defaults contain every action', () {
      final settings = ShortcutSettings.defaults();
      for (final action in ShortcutAction.values) {
        expect(settings.keysFor(action), isNotEmpty);
      }
    });

    test('a binding can be replaced', () {
      final settings = ShortcutSettings.defaults()
          .withBinding(ShortcutAction.toggleMute, 'X');
      expect(settings.keysFor(ShortcutAction.toggleMute), 'X');
      // The other bindings are untouched.
      expect(settings.keysFor(ShortcutAction.playPause), 'Space');
    });

    test('the defaults can be restored', () {
      final settings = ShortcutSettings.defaults()
          .withBinding(ShortcutAction.toggleMute, 'X')
          .reset();
      expect(settings.keysFor(ShortcutAction.toggleMute), 'M');
    });
  });
}
