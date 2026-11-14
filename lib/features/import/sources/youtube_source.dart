/// The import of the YouTube playlists and videos.
///
/// Port of `src/features/library/services/import/sources/youtube/`.
library;

import '../../../core/media/innertube/innertube_client.dart';
import '../../../core/media/innertube/innertube_track_mapper.dart';
import '../../../core/utils/json.dart';
import '../matching/source_profile.dart';
import 'imported_playlist.dart';

/// The maximum number of pages fetched from a playlist.
const int maxContinuationPages = 50;

/// The YouTube import source.
class YoutubeSource {
  YoutubeSource({InnertubeClient? client, VisitorSession? visitorSession})
      : _client = client ?? InnertubeClient(),
        _visitorSession = visitorSession ?? VisitorSession();

  final InnertubeClient _client;
  final VisitorSession _visitorSession;

  /// The playlist id of a YouTube URL.
  static String? playlistIdFromYoutube(String rawUrl) {
    try {
      final uri = Uri.parse(rawUrl);
      final id = uri.queryParameters['list'];
      if (id == null || id.isEmpty) return null;
      return id.startsWith('VL') ? id : 'VL$id';
    } catch (_) {
      return null;
    }
  }

  /// The video id of a YouTube URL.
  static String? videoIdFromYoutube(String rawUrl) {
    try {
      final uri = Uri.parse(rawUrl);
      if (uri.host == 'youtu.be') {
        final id = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
        return id.length == 11 ? id : null;
      }
      final v = uri.queryParameters['v'];
      if (v != null && v.length == 11) return v;

      final segments = uri.pathSegments;
      for (final marker in const ['v', 'embed', 'shorts']) {
        final index = segments.indexOf(marker);
        if (index >= 0 && index + 1 < segments.length) {
          final id = segments[index + 1];
          if (id.length == 11) return id;
        }
      }
    } catch (_) {}
    return null;
  }

  /// The thumbnail of a video.
  static String youtubeThumbnailUrl(String videoId) {
    return 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
  }

  /// Imports a YouTube playlist (or a single video).
  Future<ImportedPlaylist> import(String rawUrl) async {
    final playlistId = playlistIdFromYoutube(rawUrl);
    if (playlistId == null) {
      final videoId = videoIdFromYoutube(rawUrl);
      if (videoId == null) {
        throw StateError(
          'The YouTube URL must contain a valid playlist or video id.',
        );
      }
      return _importSingleVideo(videoId, rawUrl);
    }

    final body = await _post('browse', {'browseId': playlistId});
    final tracks = <ImportedTrack>[];
    final seenIds = <String>{};
    _parseTracks(body, seenIds, tracks);
    await _collectContinuations(body, seenIds, tracks);

    if (tracks.isEmpty) {
      throw StateError(
        'No track could be extracted from this YouTube playlist. '
        'Check that the playlist is public.',
      );
    }

    final metadata = _parseMetadata(body) ?? const {};
    return ImportedPlaylist(
      source: 'youtube',
      sourceUrl: rawUrl,
      title: (metadata['title'] as String?) ?? '',
      author: (metadata['author'] as String?) ?? '',
      coverUrl: (metadata['coverUrl'] as String?) ?? '',
      tracks: tracks,
    );
  }

  Future<ImportedPlaylist> _importSingleVideo(
    String videoId,
    String rawUrl,
  ) async {
    final body = await _post('next', {'videoId': videoId});
    final tracks = <ImportedTrack>[];
    final seenIds = <String>{};
    _parseTracks(body, seenIds, tracks);

    // The video itself is the first item of the queue.
    final own = ImportedTrack(
      id: videoId,
      title: '',
      artists: const [],
      durationMs: null,
      coverUrl: youtubeThumbnailUrl(videoId),
    );
    final all = [own, ...tracks];

    return ImportedPlaylist(
      source: 'youtube',
      sourceUrl: rawUrl,
      title: all.first.title,
      coverUrl: all.first.coverUrl,
      tracks: all,
    );
  }

  Future<void> _collectContinuations(
    Map<String, dynamic> initialBody,
    Set<String> seenIds,
    List<ImportedTrack> tracks,
  ) async {
    var token = extractContinuationToken(initialBody);
    var pageCount = 0;

    while (token != null && pageCount < maxContinuationPages) {
      pageCount += 1;
      final Map<String, dynamic> body;
      try {
        body = await _post('browse', {'continuation': token});
      } catch (_) {
        break;
      }

      final previousCount = tracks.length;
      _parseTracks(body, seenIds, tracks);
      final nextToken = extractContinuationToken(body);
      if (nextToken == null ||
          nextToken == token ||
          tracks.length == previousCount) {
        break;
      }
      token = nextToken;
    }
  }

  void _parseTracks(
    Map<String, dynamic> body,
    Set<String> seenIds,
    List<ImportedTrack> tracks,
  ) {
    for (final raw in collectByKey(body, 'musicResponsiveListItemRenderer')) {
      final mapped = InnertubeTrackMapper.mapTrack({
        'musicResponsiveListItemRenderer': raw,
      });
      if (mapped == null || seenIds.contains(mapped.id)) continue;
      seenIds.add(mapped.id);
      tracks.add(
        ImportedTrack(
          id: mapped.id,
          title: mapped.title,
          artists: mapped.artistList
              .map((a) => a.name)
              .where((n) => n.isNotEmpty)
              .toList(),
          durationMs: mapped.durationMs > 0 ? mapped.durationMs : null,
          coverUrl: mapped.coverUrl.isNotEmpty
              ? mapped.coverUrl
              : youtubeThumbnailUrl(mapped.id),
        ),
      );
    }
  }

  /// The metadata of the page, taken from the microformat.
  ///
  /// The playlists and the albums do not carry a detail header: the title,
  /// the author and the cover are in the microformat.
  Map<String, dynamic>? _parseMetadata(Map<String, dynamic> body) {
    final micro = asRecord(
      asRecord(body['microformat'])?['microformatDataRenderer'],
    );
    if (micro == null) return null;

    final description = trimmedString(micro['description']) ?? '';
    // The description looks like "Playlist • The author".
    final author = description.contains('•')
        ? description.split('•').last.trim()
        : '';

    return {
      'title': trimmedString(micro['title']) ?? '',
      'author': author,
      'coverUrl': _parseMetadataCover(micro),
    };
  }

  String? _parseMetadataCover(Map<String, dynamic> micro) {
    final thumbnails = asArray(
      asRecord(asRecord(micro['thumbnail'])?['thumbnails']),
    );
    if (thumbnails.isEmpty) return null;
    final best = thumbnails
        .map((t) => asRecord(t))
        .whereType<Map<String, dynamic>>()
        .reduce((a, b) => asInt(a['width']) > asInt(b['width']) ? a : b);
    return asString(best['url']);
  }

  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    final visitorData = await _visitorSession.getVisitorData();
    return _client.post(
      endpoint,
      body,
      visitorData: visitorData,
    );
  }
}

/// The continuation token of a page, if any.
String? extractContinuationToken(Map<String, dynamic> body) {
  String? commandToken(Object? endpoint) {
    return trimmedString(
      asRecord(asRecord(endpoint)?['continuationCommand'])?['token'],
    );
  }

  final renderer = asRecord(findFirst(body, 'continuationItemRenderer'));
  return commandToken(renderer?['continuationEndpoint']) ??
      trimmedString(
        asRecord(findFirst(body, 'continuationCommand'))?['token'],
      ) ??
      commandToken(findFirst(body, 'continuationEndpoint')) ??
      trimmedString(
        asRecord(findFirst(body, 'nextContinuationData'))?['continuation'],
      ) ??
      trimmedString(
        asRecord(findFirst(body, 'reloadContinuationData'))?['continuation'],
      );
}
