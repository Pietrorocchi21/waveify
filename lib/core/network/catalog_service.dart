import '../media/innertube/innertube_catalog.dart';
import '../media/audius/audius_catalog.dart';
import 'waveify_api.dart';
import '../../models/catalog.dart';
import '../../models/track.dart';

/// Resolves catalog entities (search, tracks, albums, playlists, artists).
///
/// The production backend only exposes the account, popularity and lyrics
/// endpoints: the catalog itself is resolved client-side through InnerTube,
/// like the Electron client does. When a deployment does expose the
/// catalog endpoints, the server is used as a fallback.
enum CatalogSearchSource { all, online, youtube, library }

class CatalogService {
  CatalogService({required this._catalog, required this._api, this.audius});

  final AudiusCatalog? audius;

  final InnertubeCatalog _catalog;
  final WaveifyApi _api;

  /// Searches tracks, artists, albums and playlists.
  Future<List<SearchItem>> search(
    String query, {
    String type = 'all',
    CatalogSearchSource source = CatalogSearchSource.all,
  }) async {
    final uri = Uri.tryParse(query.trim());
    if (uri != null &&
        {'https', 'http'}.contains(uri.scheme) &&
        uri.host.isNotEmpty &&
        RegExp(
          r'\.(mp3|m4a|aac|wav|flac|ogg|opus|webm)$',
          caseSensitive: false,
        ).hasMatch(uri.path)) {
      final title = uri.pathSegments.isEmpty ? uri.host : uri.pathSegments.last;
      final track = Track(
        id: uri.toString(),
        title: title,
        artists: uri.host,
        sourceUrl: uri.toString(),
      );
      return [
        SearchItem(type: 'track', id: track.id, title: title, track: track),
      ];
    }
    if (source == CatalogSearchSource.youtube) {
      return _catalog.search(query, type: type);
    }
    if (source == CatalogSearchSource.library) {
      return _api.search(query, type: type);
    }
    if (source == CatalogSearchSource.all) {
      try {
        final results = await _api.search(query, type: type);
        if (results.isNotEmpty) return results;
      } catch (_) {
        /* An online catalog can still be used without an account. */
      }
    }
    if (audius != null) {
      try {
        final results = await audius!.search(query, type: type);
        if (source == CatalogSearchSource.online || results.isNotEmpty) {
          return results;
        }
      } catch (_) {
        if (source == CatalogSearchSource.online) rethrow;
      }
    }
    return _catalog.search(query, type: type);
  }

  /// The details of a track.
  Future<Track> getTrack(String id) async {
    if (id.startsWith('audius:') && audius != null) return audius!.getTrack(id);
    try {
      return await _api.getTrack(id);
    } catch (_) {
      return _catalog.getTrack(id);
    }
  }

  /// The details of an album.
  Future<AlbumDetails> getAlbum(String id) async {
    if (id.startsWith('audius-album:') && audius != null) {
      return audius!.getAlbum(id);
    }
    try {
      return await _api.getAlbum(id);
    } catch (_) {
      return _catalog.getAlbum(id);
    }
  }

  /// The details of a playlist.
  Future<CatalogPlaylistDetails> getPlaylist(String id) async {
    if (id.startsWith('audius-playlist:') && audius != null) {
      return audius!.getPlaylist(id);
    }
    try {
      return await _api.getPlaylist(id);
    } catch (_) {
      return _catalog.getPlaylist(id);
    }
  }

  /// The details of an artist.
  Future<ArtistDetails> getArtist(String id) async {
    if (id.startsWith('audius-user:') && audius != null) {
      return audius!.getArtist(id);
    }
    try {
      return await _api.getArtist(id);
    } catch (_) {
      return _catalog.getArtist(id);
    }
  }

  /// A radio station seeded by a track.
  Future<RadioResponse> getRadio(
    String id, {
    List<String>? history,
    int? k,
    String? waveId,
  }) async {
    if (id.startsWith('audius:') && audius != null) {
      return audius!.getRadio(id, history: history, k: k);
    }
    try {
      return await _catalog.getRadio(
        id,
        k: k,
        history: history,
        waveId: waveId,
      );
    } catch (_) {
      return _api.getRadio(id, history: history, k: k, waveId: waveId);
    }
  }
}
