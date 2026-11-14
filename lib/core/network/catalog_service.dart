import '../media/innertube/innertube_catalog.dart';
import 'waveify_api.dart';
import '../../models/catalog.dart';
import '../../models/track.dart';

/// Resolves catalog entities (search, tracks, albums, playlists, artists).
///
/// The production backend only exposes the account, popularity and lyrics
/// endpoints: the catalog itself is resolved client-side through InnerTube,
/// like the Electron client does. When a deployment does expose the
/// catalog endpoints, the server is used as a fallback.
class CatalogService {
  CatalogService({
    required InnertubeCatalog catalog,
    required WaveifyApi api,
  })  : _catalog = catalog,
        _api = api;

  final InnertubeCatalog _catalog;
  final WaveifyApi _api;

  /// Searches tracks, artists, albums and playlists.
  Future<List<SearchItem>> search(String query, {String type = 'all'}) async {
    try {
      final results = await _catalog.search(query, type: type);
      if (results.isNotEmpty) return results;
    } catch (_) {
      // Fall through to the server.
    }
    try {
      return await _api.search(query, type: type);
    } catch (_) {
      return const [];
    }
  }

  /// The details of a track.
  Future<Track> getTrack(String id) async {
    try {
      return await _catalog.getTrack(id);
    } catch (_) {
      return _api.getTrack(id);
    }
  }

  /// The details of an album.
  Future<AlbumDetails> getAlbum(String id) async {
    try {
      return await _catalog.getAlbum(id);
    } catch (_) {
      return _api.getAlbum(id);
    }
  }

  /// The details of a playlist.
  Future<CatalogPlaylistDetails> getPlaylist(String id) async {
    try {
      return await _catalog.getPlaylist(id);
    } catch (_) {
      return _api.getPlaylist(id);
    }
  }

  /// The details of an artist.
  Future<ArtistDetails> getArtist(String id) async {
    try {
      return await _catalog.getArtist(id);
    } catch (_) {
      return _api.getArtist(id);
    }
  }

  /// A radio station seeded by a track.
  Future<RadioResponse> getRadio(
    String id, {
    List<String>? history,
    int? k,
    String? waveId,
  }) async {
    try {
      return await _catalog.getRadio(id, k: k);
    } catch (_) {
      return _api.getRadio(id, history: history, k: k, waveId: waveId);
    }
  }
}
