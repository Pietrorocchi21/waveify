import 'package:dio/dio.dart';

import '../../../models/catalog.dart';
import '../../../models/track.dart';

/// A generic catalog facade used by the app. The production backend is the
/// source of truth; this interface keeps the app compile-able without any
/// proprietary third-party catalog implementation.
class InnertubeCatalog {
  Future<List<SearchItem>> search(
    String query, {
    String type = 'all',
    CancelToken? cancelToken,
  }) async => const <SearchItem>[];

  Future<Track> getTrack(String id) async => Track(id: id, title: 'Unknown track');

  Future<AlbumDetails> getAlbum(String id) async =>
      AlbumDetails(id: id, title: 'Unknown album');

  Future<CatalogPlaylistDetails> getPlaylist(String id) async =>
      CatalogPlaylistDetails(id: id, title: 'Unknown playlist');

  Future<ArtistDetails> getArtist(String id) async =>
      ArtistDetails(id: id, name: 'Unknown artist');

  Future<RadioResponse> getRadio(
    String id, {
    int? k,
    String? waveId,
    List<String>? history,
  }) async => const RadioResponse(items: []);
}
