import '../core/utils/json.dart';

/// Lyrics sync granularity.
enum LyricsSyncLevel {
  plain('plain'),
  lineLevel('line_level'),
  wordLevel('word_level'),
  syllableLevel('syllable_level');

  const LyricsSyncLevel(this.raw);

  final String raw;

  static LyricsSyncLevel fromRaw(String? raw) {
    return LyricsSyncLevel.values.firstWhere(
      (e) => e.raw == raw,
      orElse: () => LyricsSyncLevel.plain,
    );
  }
}

/// Lyrics content kind.
enum LyricsContentKind {
  plain('plain'),
  lineSynced('line_synced'),
  wordSynced('word_synced'),
  syllableSynced('syllable_synced');

  const LyricsContentKind(this.raw);

  final String raw;

  static LyricsContentKind fromRaw(String? raw) {
    return LyricsContentKind.values.firstWhere(
      (e) => e.raw == raw,
      orElse: () => LyricsContentKind.plain,
    );
  }
}

/// Lyrics wire format.
enum LyricsFormat {
  plain('plain'),
  lrc('lrc'),
  ttml('ttml'),
  qrc('qrc'),
  richsync('richsync');

  const LyricsFormat(this.raw);

  final String raw;

  static LyricsFormat fromRaw(String? raw) {
    return LyricsFormat.values.firstWhere(
      (e) => e.raw == raw,
      orElse: () => LyricsFormat.plain,
    );
  }
}

/// Quality breakdown of a lyrics candidate.
class LyricsQuality {
  const LyricsQuality({
    this.total = 0,
    this.match = 0,
    this.content = 0,
    this.sync = 0,
    this.source = 0,
    this.reasons = const [],
  });

  factory LyricsQuality.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const LyricsQuality();
    return LyricsQuality(
      total: asInt(json['total']),
      match: asInt(json['match']),
      content: asInt(json['content']),
      sync: asInt(json['sync']),
      source: asInt(json['source']),
      reasons: (json['reasons'] as List?)
              ?.map((e) => asString(e))
              .where((e) => e.isNotEmpty)
              .toList(growable: false) ??
          const [],
    );
  }

  final int total;
  final int match;
  final int content;
  final int sync;
  final int source;
  final List<String> reasons;
}

/// A lyrics candidate returned by a provider.
class LyricsCandidate {
  const LyricsCandidate({
    required this.provider,
    required this.format,
    required this.content,
    this.contentKind = LyricsContentKind.plain,
    this.syncLevel = LyricsSyncLevel.plain,
    this.quality = const LyricsQuality(),
    this.topPriority = false,
    this.matchedTitle,
    this.matchedArtists = const [],
    this.matchedDurationMs,
  });

  factory LyricsCandidate.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const LyricsCandidate(
        provider: '',
        format: LyricsFormat.plain,
        content: '',
      );
    }
    final lyrics = asRecord(json['lyrics']);
    final matched = asRecord(json['matchedTrack']);
    return LyricsCandidate(
      provider: asString(json['provider']),
      format: LyricsFormat.fromRaw(asString(lyrics?['format'], 'plain')),
      content: asString(lyrics?['content']),
      contentKind: LyricsContentKind.fromRaw(asString(json['contentKind'])),
      syncLevel: LyricsSyncLevel.fromRaw(asString(json['syncLevel'])),
      quality: LyricsQuality.fromJson(asRecord(json['quality'])),
      topPriority: asBool(json['topPriority']),
      matchedTitle: matched == null ? null : asStringOrNull(matched['title']),
      matchedArtists: (matched?['artists'] as List?)
              ?.map((e) => asString(e))
              .toList(growable: false) ??
          const [],
      matchedDurationMs:
          matched == null ? null : asDurationMs(matched),
    );
  }

  final String provider;
  final LyricsFormat format;
  final String content;
  final LyricsContentKind contentKind;
  final LyricsSyncLevel syncLevel;
  final LyricsQuality quality;
  final bool topPriority;
  final String? matchedTitle;
  final List<String> matchedArtists;
  final int? matchedDurationMs;
}

/// A provider surfaced while streaming lyrics.
class LyricsProviderOption {
  const LyricsProviderOption({
    required this.provider,
    required this.syncLevel,
    required this.quality,
    this.candidate,
  });

  final String provider;
  final LyricsSyncLevel syncLevel;
  final int quality;
  final LyricsCandidate? candidate;
}

/// Events streamed by the lyrics SSE endpoint.
sealed class LyricsStreamEvent {
  const LyricsStreamEvent();
}

class LyricsMetadataEvent extends LyricsStreamEvent {
  const LyricsMetadataEvent(this.title, this.artists, this.durationMs);

  final String title;
  final List<String> artists;
  final int durationMs;
}

class LyricsProviderFoundEvent extends LyricsStreamEvent {
  const LyricsProviderFoundEvent(this.candidate, this.durationMs);

  final LyricsCandidate candidate;
  final int? durationMs;
}

class LyricsProviderNotFoundEvent extends LyricsStreamEvent {
  const LyricsProviderNotFoundEvent(this.provider, this.durationMs);

  final String provider;
  final int? durationMs;
}

class LyricsProviderErrorEvent extends LyricsStreamEvent {
  const LyricsProviderErrorEvent(this.provider, this.message, this.durationMs);

  final String provider;
  final String message;
  final int? durationMs;
}

class LyricsDoneEvent extends LyricsStreamEvent {
  const LyricsDoneEvent({
    required this.cached,
    this.bestProvider,
    this.bestQuality,
    this.bestSyncLevel,
    this.status,
  });

  final bool cached;
  final String? bestProvider;
  final int? bestQuality;
  final LyricsSyncLevel? bestSyncLevel;
  final String? status;
}

/// A word inside a synced line.
class LyricWord {
  const LyricWord({
    required this.timeMs,
    required this.endMs,
    required this.text,
    this.isBackground = false,
  });

  final int timeMs;
  final int endMs;
  final String text;
  final bool isBackground;
}

/// A timed lyrics line.
class SyncedLine {
  const SyncedLine({
    required this.timeMs,
    required this.text,
    this.durationMs = 0,
    this.isInstrumental = false,
    this.words = const [],
  });

  final int timeMs;
  final int durationMs;
  final String text;
  final bool isInstrumental;
  final List<LyricWord> words;

  SyncedLine offset(int offsetMs) => SyncedLine(
        timeMs: (timeMs + offsetMs).clamp(0, 1 << 62),
        durationMs: durationMs,
        text: text,
        isInstrumental: isInstrumental,
        words: [
          for (final w in words)
            LyricWord(
              timeMs: (w.timeMs + offsetMs).clamp(0, 1 << 62),
              endMs: (w.endMs + offsetMs).clamp(0, 1 << 62),
              text: w.text,
              isBackground: w.isBackground,
            ),
        ],
      );
}

/// The result of parsing raw lyrics.
class ParsedLyrics {
  const ParsedLyrics({
    this.syncedLines = const [],
    this.plainLyrics,
  });

  final List<SyncedLine> syncedLines;
  final String? plainLyrics;

  bool get isEmpty => syncedLines.isEmpty && (plainLyrics == null);

  ParsedLyrics offset(int offsetMs) {
    if (offsetMs == 0) return this;
    return ParsedLyrics(
      syncedLines: syncedLines.map((l) => l.offset(offsetMs)).toList(),
      plainLyrics: plainLyrics,
    );
  }
}
