/// The import of the Deezer playlists and albums.
///
/// Port of `src/features/library/services/import/sources/deezerSource.ts`.
///
/// The Deezer API is public: no token is needed.
library;

import '../../../core/utils/json.dart';
import '../matching/source_profile.dart';
import 'imported_playlist.dart';
import 'public_fetcher.dart';

const String _deezerApi = 'https://api.deezer.com';
const int _maxPages = 50;

/// The Deezer import source.
class DeezerSource {
  DeezerSource({PublicFetcher? fetcher}) : _fetcher = fetcher ?? PublicFetcher();

  final PublicFetcher _fetcher;

  /// The identifier of a Deezer URL.
  static String? idFromUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !uri.hasScheme) return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    for (final segment in segments) {
      if (RegExp(r'^\d+$').hasMatch(segment)) return segment;
    }
    return null;
  }

  /// Imports a Deezer playlist or an album.
  Future<ImportedPlaylist> import(String rawUrl) async {
    final id = idFromUrl(rawUrl);
    if (id == null) {
      throw StateError('The Deezer URL is not valid.');
    }

    final body = await _fetcher.json('$_deezerApi/playlist/$id');
    if (body.isEmpty) {
      // It may be an album.
      final album = await _fetcher.json('$_deezerApi/album/$id');
      if (album.isEmpty) {
        throw StateError('The Deezer playlist or album was not found.');
      }
      return _toPlaylist(rawUrl, album, isAlbum: true);
    }

    return _toPlaylist(rawUrl, body, isAlbum: false);
  }

  Future<ImportedPlaylist> _toPlaylist(
    String rawUrl,
    Map<String, dynamic> body, {
    required bool isAlbum,
  }) async {
    // The tracks live under "tracks": the first page is inlined, the others
    // are behind the "next" link.
    final firstPage = asRecord(body['tracks']);
    final tracks = <ImportedTrack>[];
    _append(tracks, asArray(firstPage?['data']));

    // The playlist is paginated.
    var next = trimmedString(firstPage?['next']);
    var page = 0;
    while (next != null && page < _maxPages) {
      page += 1;
      final nextBody = await _fetcher.json(next);
      final data = asArray(nextBody['data']);
      if (data.isEmpty) break;
      final before = tracks.length;
      _append(tracks, data);
      if (tracks.length == before) break;
      next = trimmedString(nextBody['next']);
    }

    return ImportedPlaylist(
      source: 'deezer',
      sourceUrl: rawUrl,
      title: trimmedString(body['title']) ?? '',
      description: trimmedString(body['description']) ?? '',
      author: trimmedString(asRecord(body['creator'])?['name']) ?? '',
      coverUrl: trimmedString(body['cover_big']) ??
          trimmedString(body['cover']) ??
          '',
      tracks: tracks,
    );
  }

  void _append(List<ImportedTrack> tracks, List<Object?> data) {
    for (final raw in data) {
      final item = asRecord(raw);
      if (item == null) continue;
      final title = trimmedString(item['title']);
      final artist = trimmedString(asRecord(item['artist'])?['name']);
      if (title == null || artist == null) continue;

      final album = asRecord(item['album']);
      final duration = item['duration'];

      tracks.add(
        ImportedTrack(
          id: '${item['id'] ?? ''}',
          title: title,
          artists: [artist],
          album: trimmedString(album?['title']) ?? '',
          durationMs: duration is num ? (duration * 1000).round() : null,
          coverUrl: trimmedString(album?['cover_big']) ??
              trimmedString(album?['cover']) ??
              '',
        ),
      );
    }
  }
}
