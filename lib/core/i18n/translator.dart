import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// The locales the app ships translations for.
const List<String> supportedLocales = [
  'en',
  'ru',
  'uk',
  'es',
  'de',
  'it',
  'fr',
  'pl',
  'tr',
  'pt',
];

/// A loaded translation table.
class Translations {
  Translations(this.locale, this.dict);

  final String locale;
  final Map<String, String> dict;

  static final Map<String, Translations> _cache = {};

  /// Loads (and caches) the translation table for a locale.
  static Future<Translations> load(String locale) async {
    final cached = _cache[locale];
    if (cached != null) return cached;

    final raw = await rootBundle.loadString('assets/locales/$locale.json');
    final decoded = jsonDecode(raw);
    final flat = <String, String>{};
    if (decoded is Map) _flatten(decoded, '', flat);

    final translations = Translations(locale, flat);
    _cache[locale] = translations;
    return translations;
  }

  static void _flatten(
    Map<dynamic, dynamic> source,
    String prefix,
    Map<String, String> target,
  ) {
    for (final entry in source.entries) {
      final key = entry.key.toString();
      final path = prefix.isEmpty ? key : '$prefix.$key';
      final value = entry.value;
      if (value is String) {
        target[path] = value;
      } else if (value is Map) {
        _flatten(value, path, target);
      }
    }
  }

  /// Looks up a key, returning null when it is missing.
  String? lookup(String key) => dict[key];
}

/// Resolves translation keys for one locale, with an English fallback.
///
/// Mirrors `createTranslatorSync` in `src/languages/translator.ts`.
class Translator {
  Translator(this.current, {Translations? fallback})
      : _fallback = fallback ?? current;

  final Translations current;
  final Translations? _fallback;

  /// Resolves a key and substitutes `{placeholders}`.
  String call(String key, [Map<String, Object?>? vars]) {
    String? template = current.lookup(key);

    if (vars != null && vars['count'] is num) {
      final count = (vars['count'] as num).toDouble();
      final category = _pluralCategory(count);
      template = current.lookup('${key}_$category') ??
          current.lookup('${key}_plural') ??
          _fallback?.lookup('${key}_$category') ??
          _fallback?.lookup('${key}_plural');
    }

    template ??= current.lookup(key) ?? _fallback?.lookup(key);
    if (template == null) return key;

    if (vars == null) return template;
    return _format(template, vars);
  }

  static String _format(String template, Map<String, Object?> vars) {
    var result = template;
    vars.forEach((key, value) {
      result = result.replaceAll('{$key}', '${value ?? ''}');
    });
    return result;
  }

  /// Resolves the CLDR plural category for a count.
  ///
  /// The app's translation keys use the `_one` / `_few` / `_many` / `_other`
  /// suffixes.
  static String _pluralCategory(double count) {
    final n = count.abs();
    if (n == 1) return 'one';
    if (n == 0) return 'other';
    if (n < 5) return 'few';
    return 'other';
  }
}
