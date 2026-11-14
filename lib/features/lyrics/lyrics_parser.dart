import 'dart:convert';

import '../../models/lyrics.dart';

/// Lyrics wire formats understood by the parser.
enum LyricsFileFormat { lrc, ttml, qrc, plain }

/// Pure-Dart replacement for `@braccato/parsers`.
///
/// Supports the formats the backend can deliver:
///  * `richsync` — Musixmatch JSON with per-word offsets
///  * `lrc` / enhanced LRC — line and word level timestamps
///  * `ttml` — W3C timed text
///  * `qrc` — QQ Music format
///  * `plain` — unsynced text
///
/// Plus the Musixmatch "MXM subtitles" JSON variant.
class LyricsParser {
  LyricsParser._();

  /// Parses raw lyrics into timed lines plus a plain-text fallback.
  static ParsedLyrics parse(String? raw, {String? format, int? songDurationMs}) {
    if (raw == null || raw.trim().isEmpty) {
      return const ParsedLyrics();
    }

    final trimmed = raw.trim();

    try {
      final richsync = _tryParseRichsync(trimmed);
      if (richsync != null) return _fromLines(richsync);

      final mxm = _tryParseMxmSubtitles(trimmed);
      if (mxm != null) return _fromLines(mxm);

      final detected = _detectFormat(trimmed, format);
      final lines = switch (detected) {
        LyricsFileFormat.ttml => _parseTtml(trimmed),
        LyricsFileFormat.qrc => _parseQrc(trimmed),
        LyricsFileFormat.lrc => _parseLrc(trimmed),
        LyricsFileFormat.plain => const <SyncedLine>[],
      };

      if (lines.isEmpty) {
        return ParsedLyrics(plainLyrics: trimmed);
      }

      return _fromLines(lines);
    } catch (_) {
      return ParsedLyrics(plainLyrics: trimmed);
    }
  }

  static ParsedLyrics _fromLines(List<SyncedLine> lines) {
    final plain = lines.map((l) => l.text).join('\n').trim();
    return ParsedLyrics(
      syncedLines: lines,
      plainLyrics: plain.isEmpty ? null : plain,
    );
  }

  // ---------------------------------------------------------------------------
  // Format detection
  // ---------------------------------------------------------------------------

  static LyricsFileFormat _detectFormat(String raw, String? format) {
    switch (format) {
      case 'ttml':
        return LyricsFileFormat.ttml;
      case 'qrc':
        return LyricsFileFormat.qrc;
      case 'lrc':
        return LyricsFileFormat.lrc;
    }
    final head = raw.substring(0, raw.length < 200 ? raw.length : 200);
    if (head.contains('<tt') || head.contains('<TT')) {
      return LyricsFileFormat.ttml;
    }
    if (RegExp(r'^\[\d+:\d+[.:]?\d*\]', multiLine: true).hasMatch(raw)) {
      return LyricsFileFormat.lrc;
    }
    return LyricsFileFormat.plain;
  }

  // ---------------------------------------------------------------------------
  // Musixmatch richsync
  // ---------------------------------------------------------------------------

  static List<SyncedLine>? _tryParseRichsync(String raw) {
    if (!raw.startsWith('[')) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.isEmpty) return null;
      final first = decoded.first;
      if (first is! Map || first['ts'] is! num) return null;

      return decoded.whereType<Map>().map(_richsyncLine).toList();
    } catch (_) {
      return null;
    }
  }

  static SyncedLine _richsyncLine(Map line) {
    final startMs = (((line['ts'] as num?)?.toDouble() ?? 0) * 1000).round();
    final endMs = (((line['te'] as num?)?.toDouble() ?? 0) * 1000).round();
    final durationMs = endMs > startMs ? endMs - startMs : 0;

    final rawWords = (line['l'] as List?) ?? const [];
    final merged = <Map<String, dynamic>>[];
    for (final w in rawWords.whereType<Map>()) {
      final c = w['c'];
      if (c is! String) continue;
      if (c.trim().isEmpty) {
        if (merged.isNotEmpty) {
          final last = merged.removeLast();
          last['c'] = '${last['c']}$c';
          merged.add(last);
        }
      } else {
        merged.add({'c': c, 'o': w['o']});
      }
    }

    final text = merged.map((w) => w['c'] as String).join();

    final words = <LyricWord>[];
    for (var i = 0; i < merged.length; i++) {
      final w = merged[i];
      final rawOffsetMs = (((w['o'] as num?) ?? 0) * 1000).round();
      final wordStart = rawOffsetMs >= startMs ? rawOffsetMs : startMs + rawOffsetMs;

      int nextWordStart;
      if (i + 1 < merged.length) {
        final nextRaw = ((merged[i + 1]['o'] as num?) ?? 0) * 1000;
        nextWordStart = nextRaw.round() >= startMs
            ? nextRaw.round()
            : startMs + nextRaw.round();
      } else {
        nextWordStart = endMs;
      }

      words.add(
        LyricWord(
          timeMs: wordStart,
          endMs: nextWordStart > wordStart ? nextWordStart : wordStart,
          text: w['c'] as String,
        ),
      );
    }

    return SyncedLine(
      timeMs: startMs,
      durationMs: durationMs,
      text: text,
      words: words,
    );
  }

  // ---------------------------------------------------------------------------
  // Musixmatch "MXM subtitles"
  // ---------------------------------------------------------------------------

  static List<SyncedLine>? _tryParseMxmSubtitles(String raw) {
    if (!raw.startsWith('[')) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.isEmpty) return null;
      final first = decoded.first;
      if (first is! Map || (first['time'] is! Map)) return null;

      final lines = <SyncedLine>[];
      for (final entry in decoded.whereType<Map>()) {
        final text = (entry['text'] as String?)?.trim() ?? '';
        if (text.isEmpty) continue;
        final time = entry['time'];
        final total = time is Map ? (time['total'] as num?)?.toDouble() ?? 0 : 0;
        lines.add(
          SyncedLine(timeMs: (total * 1000).round(), text: text),
        );
      }
      return lines;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // LRC (plain and enhanced / word level)
  // ---------------------------------------------------------------------------

  static final RegExp _lrcLine = RegExp(
    r'\[(\d+):(\d+)(?:[.:](\d+))?\]',
  );

  static final RegExp _lrcWord = RegExp(
    r'<(\d+):(\d+)(?:[.:](\d+))?>',
  );

  static List<SyncedLine> _parseLrc(String raw) {
    final lines = <SyncedLine>[];

    for (final rawLine in const LineSplitter().convert(raw)) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty) continue;

      // Collect every leading timestamp on this line (multi-timestamp LRC).
      final stamps = <int>[];
      var rest = trimmed;
      while (true) {
        final match = _lrcLine.firstMatch(rest);
        if (match == null) break;
        stamps.add(_lrcTimestampMs(match));
        rest = rest.substring(match.end);
      }
      if (stamps.isEmpty) continue;

      final text = rest.trim();
      final words = _parseLrcWords(text);

      for (final stamp in stamps) {
        lines.add(
          SyncedLine(
            timeMs: stamp,
            text: words.isEmpty ? text : words.map((w) => w.text).join(),
            words: words,
          ),
        );
      }
    }

    lines.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return _withDurations(lines);
  }

  static int _lrcTimestampMs(RegExpMatch match) {
    final minutes = int.parse(match.group(1)!);
    final seconds = int.parse(match.group(2)!);
    final fraction = match.group(3) ?? '0';
    // LRC fractions are hundredths of a second: ".5" and ".50" both mean
    // 500 ms, ".500" means 500 ms too.
    final fracMs = fraction.isEmpty
        ? 0
        : int.parse(fraction) * _fractionMultiplier(fraction.length);
    return minutes * 60000 + seconds * 1000 + fracMs;
  }

  /// Milliseconds represented by one unit of the fractional part.
  static int _fractionMultiplier(int length) {
    if (length <= 1) return 100; // tenths of a second
    if (length == 2) return 10; // hundredths of a second
    return 1; // thousandths of a second
  }

  /// Parses enhanced-LRC word tags: `<00:12.34> word`.
  static List<LyricWord> _parseLrcWords(String text) {
    final matches = _lrcWord.allMatches(text).toList();
    if (matches.isEmpty) return const [];

    final words = <LyricWord>[];
    for (var i = 0; i < matches.length; i++) {
      final start = _lrcTimestampMs(matches[i]);
      final contentStart = matches[i].end;
      final contentEnd =
          i + 1 < matches.length ? matches[i + 1].start : text.length;
      final word = text.substring(contentStart, contentEnd).trim();
      if (word.isEmpty) continue;
      final end = i + 1 < matches.length
          ? _lrcTimestampMs(matches[i + 1])
          : start + 500;
      words.add(LyricWord(timeMs: start, endMs: end, text: word));
    }
    return words;
  }

  // ---------------------------------------------------------------------------
  // QRC (QQ Music)
  // ---------------------------------------------------------------------------

  static final RegExp _qrcLine = RegExp(r'\[(\d+):(\d+)(?:[.:](\d+))?\]');

  static List<SyncedLine> _parseQrc(String raw) {
    final lines = <SyncedLine>[];

    for (final rawLine in const LineSplitter().convert(raw)) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty) continue;

      final stamp = _qrcLine.firstMatch(trimmed);
      if (stamp == null) continue;

      final minutes = int.parse(stamp.group(1)!);
      final seconds = int.parse(stamp.group(2)!);
      final fraction = stamp.group(3) ?? '0';
      final startMs = minutes * 60000 +
          seconds * 1000 +
          (fraction.isEmpty
              ? 0
              : int.parse(fraction) * _fractionMultiplier(fraction.length));

      final rest = trimmed.substring(stamp.end).trim();
      final words = <LyricWord>[];
      // QRC word format: `<startMs,durationMs>word`
      final wordRe = RegExp(r'<(\d+),(\d+)>');
      final parts = wordRe.allMatches(rest).toList();

      if (parts.isEmpty) {
        lines.add(SyncedLine(timeMs: startMs, text: rest));
        continue;
      }

      for (var i = 0; i < parts.length; i++) {
        final wordStart = int.parse(parts[i].group(1)!);
        final wordDuration = int.parse(parts[i].group(2)!);
        final contentStart = parts[i].end;
        final contentEnd =
            i + 1 < parts.length ? parts[i + 1].start : rest.length;
        final word = rest.substring(contentStart, contentEnd).trim();
        if (word.isEmpty) continue;
        words.add(
          LyricWord(
            timeMs: wordStart,
            endMs: wordStart + wordDuration,
            text: word,
          ),
        );
      }

      lines.add(
        SyncedLine(
          timeMs: startMs,
          text: words.map((w) => w.text).join(),
          words: words,
        ),
      );
    }

    lines.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return _withDurations(lines);
  }

  // ---------------------------------------------------------------------------
  // TTML
  // ---------------------------------------------------------------------------

  /// The `<span>` elements of a timed paragraph, with their own timing.
  static final RegExp _ttmlSpan = RegExp(
    r'<span\b([^>]*)>(.*?)</span>',
    dotAll: true,
    caseSensitive: false,
  );

  static List<SyncedLine> _parseTtml(String raw) {
    final lines = <SyncedLine>[];

    final pRe = RegExp(
      r'<p\b([^>]*)>(.*?)</p>',
      dotAll: true,
      caseSensitive: false,
    );

    for (final match in pRe.allMatches(raw)) {
      final attrs = match.group(1) ?? '';
      final body = match.group(2) ?? '';

      final beginMatch = RegExp(
        r'\bbegin\s*=\s*"([^"]+)"',
        caseSensitive: false,
      ).firstMatch(attrs);
      final endMatch = RegExp(
        r'\bend\s*=\s*"([^"]+)"',
        caseSensitive: false,
      ).firstMatch(attrs);

      final beginMs = _parseTtmlTime(beginMatch?.group(1));
      if (beginMs == null) continue;
      final endMs = _parseTtmlTime(endMatch?.group(1));

      final text = _stripTtmlTags(body);
      if (text.trim().isEmpty) continue;

      lines.add(
        SyncedLine(
          timeMs: beginMs,
          durationMs: (endMs != null && endMs > beginMs) ? endMs - beginMs : 0,
          text: text.trim(),
          words: _parseTtmlWords(body),
        ),
      );
    }

    lines.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return _withDurations(lines);
  }

  /// Extracts the word level timings of a paragraph.
  ///
  /// The providers mark the words with `<span begin="…" end="…">`, which is
  /// what enables the word-by-word highlighting.
  static List<LyricWord> _parseTtmlWords(String body) {
    final words = <LyricWord>[];
    for (final match in _ttmlSpan.allMatches(body)) {
      final attrs = match.group(1) ?? '';
      final text = _stripTtmlTags(match.group(2) ?? '').trim();
      if (text.isEmpty) continue;

      final beginMatch = RegExp(
        r'\bbegin\s*=\s*"([^"]+)"',
        caseSensitive: false,
      ).firstMatch(attrs);
      final endMatch = RegExp(
        r'\bend\s*=\s*"([^"]+)"',
        caseSensitive: false,
      ).firstMatch(attrs);

      final start = _parseTtmlTime(beginMatch?.group(1));
      if (start == null) continue;
      final end = _parseTtmlTime(endMatch?.group(1));

      words.add(
        LyricWord(
          timeMs: start,
          endMs: end != null && end > start ? end : start,
          text: text,
        ),
      );
    }
    return words;
  }

  static String _stripTtmlTags(String body) {
    return body
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');
  }

  /// Parses a TTML timestamp.
  ///
  /// The providers use several notations: `hh:mm:ss.mmm`, `mm:ss.mmm` and
  /// plain seconds (`18.893`), optionally with a `s` suffix.
  static int? _parseTtmlTime(String? value) {
    if (value == null) return null;
    var raw = value.trim();
    if (raw.isEmpty) return null;

    if (raw.endsWith('ms')) {
      final millis = int.tryParse(raw.substring(0, raw.length - 2));
      return millis;
    }
    if (raw.endsWith('s')) {
      raw = raw.substring(0, raw.length - 1);
    }

    final parts = raw.split(':');
    if (parts.length > 3) return null;

    var totalSeconds = 0.0;
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i].replaceAll(',', '.');
      if (i == parts.length - 1) {
        final seconds = double.tryParse(part);
        if (seconds == null) return null;
        totalSeconds += seconds;
      } else {
        final units = int.tryParse(part);
        if (units == null) return null;
        // With three parts the first one is the hours, with two the first is
        // the minutes.
        final multiplier = parts.length == 3
            ? (i == 0 ? 3600 : 60)
            : (i == 0 ? 60 : 1);
        totalSeconds += units * multiplier;
      }
    }

    return (totalSeconds * 1000).round();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Fills in per-line durations from the gap to the next line.
  static List<SyncedLine> _withDurations(List<SyncedLine> lines) {
    if (lines.length < 2) return lines;
    final result = <SyncedLine>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final next = i + 1 < lines.length ? lines[i + 1] : null;
      final duration = line.durationMs > 0
          ? line.durationMs
          : (next != null && next.timeMs > line.timeMs
              ? next.timeMs - line.timeMs
              : 0);
      result.add(
        SyncedLine(
          timeMs: line.timeMs,
          durationMs: duration,
          text: line.text,
          isInstrumental: line.isInstrumental,
          words: line.words,
        ),
      );
    }
    return result;
  }
}
