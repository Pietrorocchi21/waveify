import 'music_source.dart';

/// Merges results from multiple music providers and resolves the best candidate
/// for a track, while keeping the app local-first and resilient to failures.
class AggregatedMusicRepository {
  AggregatedMusicRepository({List<MusicSource>? sources})
      : _sources = sources ?? const <MusicSource>[];

  final List<MusicSource> _sources;

  List<MusicSource> get sources => List<MusicSource>.unmodifiable(_sources);

  Future<List<MusicSearchResult>> search(String query, {int limit = 20}) async {
    if (query.trim().isEmpty) return const [];

    final results = <MusicSearchResult>[];
    for (final source in _sources.where((s) => s.isEnabled)) {
      try {
        final found = await source.search(query, limit: limit);
        results.addAll(found);
      } catch (_) {
        // Providers can fail independently; the repository must keep going.
      }
    }

    final byKey = <String, MusicSearchResult>{};
    for (final result in results) {
      final current = byKey[result.dedupKey];
      if (current == null ||
          result.score > current.score ||
          (result.score == current.score && result.quality > current.quality)) {
        byKey[result.dedupKey] = result;
      }
    }

    final merged = byKey.values.toList()
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        final byQuality = b.quality.compareTo(a.quality);
        if (byQuality != 0) return byQuality;
        return b.durationMs.compareTo(a.durationMs);
      });

    if (merged.length > limit) {
      return merged.take(limit).toList(growable: false);
    }
    return merged;
  }

  Future<String?> resolveStreamUrl(MusicSearchResult item) async {
    final ordered = _sources.where((s) => s.isEnabled).toList();
    
    // Try primary source first
    for (final source in ordered) {
      if (source.id == item.providerId) {
        try {
          final url = await source.resolveStreamUrl(item);
          if (url != null && url.isNotEmpty) return url;
        } catch (_) {}
      }
    }
    
    // Fallback: try to resolve the track in other sources and get their stream URL
    for (final source in ordered) {
      if (source.id == item.providerId) continue;
      try {
        // Try to find the track in this source
        final candidate = await source.resolveTrack(item.id);
        if (candidate != null) {
          final url = await source.resolveStreamUrl(candidate);
          if (url != null && url.isNotEmpty) return url;
        }
      } catch (_) {
        continue;
      }
    }
    
    return null;
  }

  Future<MusicSearchResult?> resolveBestCandidate(String trackId) async {
    for (final source in _sources.where((s) => s.isEnabled)) {
      try {
        final candidate = await source.resolveTrack(trackId);
        if (candidate != null) return candidate;
      } catch (_) {
        continue;
      }
    }
    return null;
  }
}
