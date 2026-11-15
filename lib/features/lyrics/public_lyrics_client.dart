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
  Future<LyricsCandidate?> get(Track track, {CancelToken? cancelToken}) async {
    if (track.title.trim().isEmpty || track.artists.trim().isEmpty) return null;
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
      final synced = data['syncedLyrics'] as String?;
      final plain = data['plainLyrics'] as String?;
      final content = synced?.trim().isNotEmpty == true ? synced : plain;
      if (content == null || content.trim().isEmpty) return null;
      return LyricsCandidate(
        provider: 'LRCLIB',
        format: synced?.isNotEmpty == true
            ? LyricsFormat.lrc
            : LyricsFormat.plain,
        content: content,
        contentKind: synced?.isNotEmpty == true
            ? LyricsContentKind.lineSynced
            : LyricsContentKind.plain,
        syncLevel: synced?.isNotEmpty == true
            ? LyricsSyncLevel.lineLevel
            : LyricsSyncLevel.plain,
        quality: const LyricsQuality(total: 80),
      );
    } on DioException {
      return null;
    }
  }

  void close() => _client.close(force: true);
}
