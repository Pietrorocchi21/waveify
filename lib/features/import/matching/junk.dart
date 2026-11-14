/// Removal of the noise (tags, promotions, file extensions) from the titles.
///
/// Port of `src/shared/media/matching/junk.ts`.
library;

import 'phonetic.dart';
import 'version_tags.dart';

/// The patterns of the noise, with the replacement.
final List<(RegExp, String)> _junkPatterns = [
  (RegExp(r'\.(?:mp3|wav|flac|m4a|aac|ogg)\b', caseSensitive: false), ''),
  (
    RegExp(
      r'(?:\(|\[|\{)?\s*(?:tgk|tg|t\.me|vk\.com|soundcloud\.com|soundcloud|instagram\.com|instagram|insta|inst|twitter\.com|x\.com)\s*[:/]?\s*[^)\]}]+(?:\)|\]|\})?',
      caseSensitive: false,
    ),
    '',
  ),
  (RegExp(r'@[\w.-]+'), ''),
  (
    RegExp(
      r'(?:\(|\[|\{)?\s*(?:prod(?:uced)?\s+by|beat\s+by|prod\b\.?|beat\b\.?)\s*[:/]?\s*[^)\]}]+(?:\)|\]|\})?',
      caseSensitive: false,
    ),
    '',
  ),
  (
    RegExp(
      r'(?:\(|\[|\{)\s*(?:free\s*(?:dl|download)|download(?:\s*link)?|free\s*beat|link\s+in\s+(?:bio|desc(?:ription)?)|out\s+now|stream\s+now|buy\s+now|premiere|exclusive|clip\s+officiel|official\s+video|official\s+audio|official\s+music\s+video|music\s+video|lyric\s+video|visualizer|official\s+visualizer|audio\s+visualizer|og\s+version|og\s+beat|full\s+version|hq|hd|4k)[^)\]}]*[)\]}]',
      caseSensitive: false,
    ),
    '',
  ),
  (
    RegExp(
      r'\s*[([{]\s*(?:remaster(?:ed)?(?:\s*\d{4})?|ремастеринг(?:\s*\d{4})?|deluxe(?:\s+edition)?|anniversary(?:\s+edition)?|original\s+mix|album\s+version|single\s+version|ost|soundtrack|из\s+(?:телесериала|фильма|к\/ф)[^)\]}]*)[^)\]}]*[)\]}]',
      caseSensitive: false,
    ),
    '',
  ),
  (
    RegExp(
      r'\s*[-–—|]\s*(?:out\s+now|premiere|exclusive|free\s*dl|official\s*video|visualizer|audio|remaster(?:ed)?|ремастеринг|prod\s+by[^\s]+).*$',
      caseSensitive: false,
    ),
    '',
  ),
  (RegExp(r'\*+[^*]+\*+'), ''),
  (RegExp(r'\(\s*\)|\[\s*\]|\{\s*\}'), ''),
];

/// Removes the noise from a string.
String stripJunk(String value) {
  var result = value;
  for (final (pattern, replacement) in _junkPatterns) {
    result = result.replaceAll(pattern, replacement);
  }
  return result.trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Removes the tags that are only useful for the search.
String cleanSearchTitle(String title) {
  return title
      .replaceAll(
        RegExp(
          r'[([]\s*(?:official\s+(?:music\s+)?(?:video|audio)|visualizer|lyrics?|audio|hd|4k|mood\s+video|music\s+video|best\s+part)\s*[)\]]',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'[([]\s*p(?:rod)?(?:\.|uced)?\s+by\s+[^)\]]+[)\]]', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\[\s*p\.[^\]]+\]', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'@\w+'), ' ')
      .replaceAll(RegExp(r'[([]\s*(?:explicit|e|18\+)\s*[)\]]', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// The title without the noise, without the version tags and normalized.
String cleanBaseTitle(String value) {
  var result = stripJunk(value);
  result = result.replaceAll(
    RegExp(r'[([{]?\s*(?:feat\.?|ft\.?|with)\s+[^)\]}]+[)\]}]?', caseSensitive: false),
    '',
  );
  result = result.replaceAll(
    RegExp(
      r'\s*[-–—]\s*(?:mono|stereo|remaster(?:ed)?(?:\s*\d{4})?|ремастеринг|live(?:\s+at[^)]+)?|acoustic|instrumental|radio\s+edit|single\s+version|original\s+mix|album\s+version)\b.*$',
      caseSensitive: false,
    ),
    '',
  );
  for (final pattern in versionPatterns) {
    result = result.replaceAll(pattern.regex, '');
  }
  return normalizeTrackString(result);
}

/// The cleaned title.
String cleanTitle(String value) => cleanBaseTitle(value);

/// The tokens of a title.
Set<String> tokens(String value) {
  return cleanBaseTitle(value)
      .split(' ')
      .where((token) => token.isNotEmpty)
      .toSet();
}

/// The overlap between the tokens of two titles, between 0 and 1.
double overlap(String left, String right) {
  final a = tokens(left);
  final b = tokens(right);
  if (a.isEmpty || b.isEmpty) return 0;
  final common = a.where(b.contains).length;
  return common / a.union(b).length;
}
