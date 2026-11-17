import 'package:dio/dio.dart';

import '../../../models/catalog.dart';
import '../../../models/track.dart';
import '../resolved_audio_stream.dart'
    show InnertubeException, ResolvedAudioStream;

/// Public, freely streamable Audius tracks. Gated or unavailable recordings
/// are excluded; availability is checked again just before resolving audio.
class AudiusCatalog {
  AudiusCatalog({Dio? client})
    : _client =
          client ??
          Dio(
            BaseOptions(
              baseUrl: const String.fromEnvironment(
                'AUDIO_CATALOG_URL',
                defaultValue: 'https://api.audius.co',
              ),
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              headers: {'User-Agent': userAgent, 'Accept': 'application/json'},
            ),
          );
  final Dio _client;
  static const userAgent =
      'Waveify/${String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0+1')} (+https://github.com/Pietrorocchi21/waveify)';
  void close() => _client.close(force: true);
  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : {};
  static String _cover(dynamic artwork) {
    final value = _map(artwork);
    return '${value['1000x1000'] ?? value['480x480'] ?? value['150x150'] ?? ''}';
  }

  static bool streamable(Map<String, dynamic> t) =>
      t['is_streamable'] == true &&
      t['is_stream_gated'] != true &&
      t['stream_conditions'] == null &&
      _map(t['access'])['stream'] != false &&
      t['is_delete'] != true &&
      t['is_unlisted'] != true &&
      t['is_available'] != false;
  String _streamUrl(String id) =>
      Uri.parse(_client.options.baseUrl)
          .resolve('/v1/tracks/${Uri.encodeComponent(id)}/stream')
          .replace(queryParameters: {'app_name': 'WAVEIFY'})
          .toString();
  Track _track(Map<String, dynamic> t) {
    final user = _map(t['user']);
    return Track(
      id: 'audius:${t['id']}',
      title: '${t['title'] ?? ''}',
      artists: '${user['name'] ?? user['handle'] ?? ''}',
      artistId: 'audius-user:${user['id']}',
      artistList: [
        TrackArtist(
          id: 'audius-user:${user['id']}',
          name: '${user['name'] ?? user['handle'] ?? ''}',
        ),
      ],
      coverUrl: _cover(t['artwork']),
      sourceUrl: _streamUrl('${t['id']}'),
      durationMs: ((t['duration'] as num?)?.toDouble() ?? 0).round() * 1000,
      downloadable:
          t['is_downloadable'] == true &&
          _map(t['access'])['download'] != false,
    );
  }

  Future<List<Map<String, dynamic>>> _get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final response = await _client.get<Map<String, dynamic>>(
      path,
      queryParameters: {'app_name': 'WAVEIFY', ...?query},
      options: Options(
        headers: {'User-Agent': userAgent, 'Accept': 'application/json'},
      ),
    );
    final data = response.data?['data'];
    final items = data is List
        ? data.map(_map).toList()
        : data is Map
        ? [_map(data)]
        : <Map<String, dynamic>>[];
    return items;
  }

  Future<List<SearchItem>> search(String query, {String type = 'all'}) async {
    if (query.trim().isEmpty) return [];
    if (type == 'all' || type == 'track') {
      final data = await _get(
        '/v1/tracks/search',
        query: {'query': query, 'limit': 30},
      );
      return [
        for (final t in data.where(streamable))
          SearchItem(
            type: 'track',
            id: 'audius:${t['id']}',
            title: '${t['title'] ?? ''}',
            track: _track(t),
            artists: _track(t).artistList ?? const [],
            cover: Cover(url: _cover(t['artwork'])),
          ),
      ];
    }
    if (type == 'artist') {
      final data = await _get(
        '/v1/users/search',
        query: {'query': query, 'limit': 20},
      );
      return [
        for (final u in data)
          SearchItem(
            type: 'artist',
            id: 'audius-user:${u['id']}',
            name: '${u['name'] ?? u['handle'] ?? ''}',
            cover: Cover(url: _cover(u['profile_picture'])),
          ),
      ];
    }
    if (type == 'album' || type == 'playlist') {
      final data = await _get(
        '/v1/playlists/search',
        query: {'query': query, 'limit': 30},
      );
      return [
        for (final p in data.where(
          (p) => (p['is_album'] == true) == (type == 'album'),
        ))
          SearchItem(
            type: type,
            id: 'audius-$type:${p['id']}',
            title: '${p['playlist_name'] ?? ''}',
            author: '${_map(p['user'])['name'] ?? ''}',
            cover: Cover(url: _cover(p['artwork'])),
          ),
      ];
    }
    return [];
  }

  Future<List<Track>> trending() async => (await _get(
    '/v1/tracks/trending',
    query: {'limit': 12, 'time': 'week'},
  )).where(streamable).map(_track).toList();
  static String _id(String id) => id.substring(id.indexOf(':') + 1);
  Future<Track> getTrack(String id) async {
    final data = await _get('/v1/tracks/${Uri.encodeComponent(_id(id))}');
    if (data.isEmpty || !streamable(data.first)) {
      throw const InnertubeException(
        'This recording is not freely streamable.',
        403,
      );
    }
    return _track(data.first);
  }

  Future<ResolvedAudioStream> resolveStream(
    String id, {
    bool requireDownload = false,
  }) async {
    final track = await getTrack(id);
    if (requireDownload && !track.downloadable) {
      throw const InnertubeException(
        'This provider permits streaming only for this recording.',
        403,
      );
    }
    // Resolve the public redirect immediately before playback. Only a tiny
    // range is requested; cancel its body instead of pre-downloading the song.
    final response = await _client.get<ResponseBody>(
      track.sourceUrl,
      options: Options(
        responseType: ResponseType.stream,
        headers: {'User-Agent': userAgent, 'Range': 'bytes=0-0'},
      ),
    );
    await response.data?.stream.listen((_) {}).cancel();
    final uri = response.realUri;
    if (uri.scheme != 'https' || uri.host.isEmpty) {
      throw const InnertubeException(
        'The provider returned an invalid audio URL.',
        502,
      );
    }
    return ResolvedAudioStream(
      url: uri.toString(),
      mimeType: 'audio/mpeg',
      durationMs: track.durationMs,
      headers: const {'User-Agent': userAgent},
    );
  }

  Future<CatalogPlaylistDetails> getPlaylist(String id) async {
    final plain = _id(id);
    final metadata = await _get('/v1/playlists/${Uri.encodeComponent(plain)}');
    if (metadata.isEmpty) {
      throw const InnertubeException('Playlist not found.', 404);
    }
    final p = metadata.first;
    final data = await _get(
      '/v1/playlists/${Uri.encodeComponent(plain)}/tracks',
      query: {'limit': 100},
    );
    final tracks = data.where(streamable).map(_track).toList();
    return CatalogPlaylistDetails(
      id: id,
      title: '${p['playlist_name'] ?? ''}',
      author: '${_map(p['user'])['name'] ?? ''}',
      cover: Cover(url: _cover(p['artwork'])),
      tracks: tracks,
      trackCount: tracks.length,
      durationMs: tracks.fold(0, (total, track) => total + track.durationMs),
    );
  }

  Future<AlbumDetails> getAlbum(String id) async {
    final p = await getPlaylist(id);
    return AlbumDetails(
      id: id,
      title: p.title,
      cover: p.cover,
      artists: [TrackArtist(name: p.author ?? '')],
      tracks: p.tracks,
      trackCount: p.trackCount,
      durationMs: p.durationMs,
    );
  }

  Future<ArtistDetails> getArtist(String id) async {
    final plain = _id(id);
    final metadata = await _get('/v1/users/${Uri.encodeComponent(plain)}');
    if (metadata.isEmpty) {
      throw const InnertubeException('Artist not found.', 404);
    }
    final user = metadata.first;
    final tracks = await _get(
      '/v1/users/${Uri.encodeComponent(plain)}/tracks',
      query: {'limit': 50},
    );
    return ArtistDetails(
      id: id,
      name: '${user['name'] ?? user['handle'] ?? ''}',
      bio: user['bio'] as String?,
      cover: Cover(url: _cover(user['profile_picture'])),
      tracks: tracks.where(streamable).map(_track).toList(),
    );
  }

  Future<RadioResponse> getRadio(
    String id, {
    List<String>? history,
    int? k,
  }) async {
    final seed = await getTrack(id);
    final results = await search(seed.artists, type: 'track');
    final excluded = {id, ...?history};
    return RadioResponse(
      items: results
          .map((r) => r.track!)
          .where((t) => !excluded.contains(t.id))
          .take(k ?? 20)
          .toList(),
    );
  }
}
