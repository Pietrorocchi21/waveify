import 'package:dio/dio.dart';

import '../../models/lyrics.dart';
import '../../models/track.dart';

/// Optional public exact-match lyrics fallback; never substitutes another song.
class PublicLyricsClient {
  PublicLyricsClient({Dio? client})
    : _client =
          client ??
          Dio(
            BaseOptions(
              baseUrl: const String.fromEnvironment(
                'LYRICS_API_URL',
                defaultValue: 'https://lrclib.net',
              ),
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
            ),
          );
  final Dio _client;
  final _cache = <String, LyricsCandidate?>{};

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u00c0-\u024f]+'), ' ')
      .trim();

  bool _matches(Map<String, dynamic> data, Track track) {
    final duration = data['duration'];
    return _normalize('${data['trackName'] ?? ''}') ==
            _normalize(track.title) &&
        _normalize('${data['artistName'] ?? ''}') ==
            _normalize(track.artists) &&
        (track.durationMs <= 0 ||
            duration is num &&
                (duration * 1000 - track.durationMs).abs() <= 2000);
  }

  LyricsCandidate? _candidate(Map<String, dynamic> data) {
    final synced = data['syncedLyrics'] as String?;
    final plain = data['plainLyrics'] as String?;
    final isSynced = synced?.trim().isNotEmpty == true;
    final content = isSynced ? synced : plain;
    final instrumental = data['instrumental'] == true;
    if (!instrumental && (content == null || content.trim().isEmpty)) {
      return null;
    }
    return LyricsCandidate(
      provider: 'LRCLIB',
      format: isSynced ? LyricsFormat.lrc : LyricsFormat.plain,
      content: content ?? '',
      isInstrumental: instrumental,
      contentKind: isSynced
          ? LyricsContentKind.lineSynced
          : LyricsContentKind.plain,
      syncLevel: isSynced ? LyricsSyncLevel.lineLevel : LyricsSyncLevel.plain,
      quality: const LyricsQuality(total: 80),
      matchedTitle: data['trackName'] as String?,
      matchedArtists: ['${data['artistName'] ?? ''}'],
      matchedDurationMs:
          ((data['duration'] as num?)?.toDouble() ?? 0).round() * 1000,
    );
  }

  Future<LyricsCandidate?> get(Track track, {CancelToken? cancelToken}) async {
    if (track.title.trim().isEmpty || track.artists.trim().isEmpty) return null;
    final key =
        '${track.title}|${track.artists}|${track.album?.title}|${track.durationMs}';
    if (_cache.containsKey(key)) {
      final cached = _cache.remove(key);
      _cache[key] = cached;
      return cached;
    }
    LyricsCandidate? result;
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/get',
        queryParameters: {
          'track_name': track.title,
          'artist_name': track.artists,
          if (track.album != null) 'album_name': track.album!.title,
          if (track.durationMs > 0)
            'duration': (track.durationMs / 1000).round(),
        },
        cancelToken: cancelToken,
      );
      final data = response.data ?? {};
      if (_matches(data, track)) result = _candidate(data);
    } on DioException catch (error) {
      if (error.response?.statusCode != 404) rethrow;
      // Search can recover differing album metadata, but never a different
      // recording: title, full artist credit and known duration must agree.
      final response = await _client.get<List<dynamic>>(
        '/api/search',
        queryParameters: {
          'track_name': track.title,
          'artist_name': track.artists,
        },
        cancelToken: cancelToken,
      );
      for (final item in response.data ?? const []) {
        if (item is! Map) continue;
        final data = Map<String, dynamic>.from(item);
        if (!_matches(data, track)) continue;
        final candidate = _candidate(data);
        if (candidate != null &&
            (result == null ||
                candidate.syncLevel != LyricsSyncLevel.plain &&
                    result.syncLevel == LyricsSyncLevel.plain)) {
          result = candidate;
        }
      }
    }
    if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
    _cache[key] = result;
    if (_cache.length > 64) _cache.remove(_cache.keys.first);
    return result;
  }

  void close() => _client.close(force: true);
}
