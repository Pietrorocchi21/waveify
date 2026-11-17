import 'package:dio/dio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import '../../../models/catalog.dart';
import '../../../models/track.dart';

/// Public video/playlist metadata, using a maintained open-source client.
/// Unavailable/restricted media raises the provider's error; no fake results.
class InnertubeCatalog {
  InnertubeCatalog({yt.YoutubeExplode? client}) : _provided = client;
  final yt.YoutubeExplode? _provided;
  yt.YoutubeExplode? _owned;
  yt.YoutubeExplode get client => _provided ?? (_owned ??= yt.YoutubeExplode());
  void close() => _owned?.close();
  static String _artistName(String author) => author
      .replaceFirst(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
      .trim();
  static Track mapVideo(yt.Video video) => Track(
    id: video.id.value,
    title: video.title,
    artists: _artistName(video.author),
    artistId: video.channelId.value,
    artistList: [
      TrackArtist(id: video.channelId.value, name: _artistName(video.author)),
    ],
    coverUrl: video.thumbnails.highResUrl,
    durationMs: video.duration?.inMilliseconds ?? 0,
  );
  Future<List<SearchItem>> search(
    String query, {
    String type = 'all',
    CancelToken? cancelToken,
  }) async {
    if (query.trim().isEmpty) return [];
    if (cancelToken?.isCancelled == true) {
      throw cancelToken!.cancelError!;
    }
    if (type == 'track') {
      final videos = await client.search
          .search(query)
          .timeout(const Duration(seconds: 15));
      if (cancelToken?.isCancelled == true) {
        throw cancelToken!.cancelError!;
      }
      return [
        for (final video in videos)
          SearchItem(
            type: 'track',
            id: video.id.value,
            track: mapVideo(video),
            title: video.title,
            cover: Cover(url: video.thumbnails.highResUrl),
          ),
      ];
    }
    final result = await client.search
        .searchContent(
          query,
          filter: type == 'artist'
              ? yt.TypeFilters.channel
              : type == 'playlist' || type == 'album'
              ? yt.TypeFilters.playlist
              : const yt.SearchFilter(''),
        )
        .timeout(const Duration(seconds: 15));
    if (cancelToken?.isCancelled == true) {
      throw cancelToken!.cancelError!;
    }
    return [
      for (final item in result)
        if (item is yt.SearchVideo)
          SearchItem(
            type: 'track',
            id: item.id.value,
            title: item.title,
            track: Track(
              id: item.id.value,
              title: item.title,
              artists: _artistName(item.author),
              artistId: item.channelId,
              artistList: [
                TrackArtist(id: item.channelId, name: _artistName(item.author)),
              ],
              coverUrl: item.thumbnails.isEmpty
                  ? ''
                  : item.thumbnails.last.url.toString(),
              durationMs: _duration(item.duration),
            ),
            cover: Cover(
              url: item.thumbnails.isEmpty
                  ? ''
                  : item.thumbnails.last.url.toString(),
            ),
          )
        else if (item is yt.SearchPlaylist)
          SearchItem(
            type: type == 'album' ? 'album' : 'playlist',
            id: item.id.value,
            title: item.title,
            cover: Cover(
              url: item.thumbnails.isEmpty
                  ? ''
                  : item.thumbnails.last.url.toString(),
            ),
          )
        else if (item is yt.SearchChannel)
          SearchItem(
            type: 'artist',
            id: item.id.value,
            name: item.name,
            cover: Cover(
              url: item.thumbnails.isEmpty
                  ? ''
                  : item.thumbnails.last.url.toString(),
            ),
          ),
    ];
  }

  static int _duration(String text) {
    var seconds = 0;
    for (final part in text.split(':')) {
      seconds = seconds * 60 + (int.tryParse(part) ?? 0);
    }
    return seconds * 1000;
  }

  Future<Track> getTrack(String id) async => mapVideo(
    await client.videos.get(id).timeout(const Duration(seconds: 15)),
  );
  Future<CatalogPlaylistDetails> getPlaylist(String id) async {
    final metadata = await client.playlists
        .get(id)
        .timeout(const Duration(seconds: 15));
    final videos = await client.playlists
        .getVideos(id)
        .take(500)
        .toList()
        .timeout(const Duration(seconds: 30));
    final tracks = videos.map(mapVideo).toList();
    return CatalogPlaylistDetails(
      id: id,
      title: metadata.title,
      author: metadata.author,
      description: metadata.description,
      cover: Cover(url: metadata.thumbnails.highResUrl),
      trackCount: tracks.length,
      durationMs: tracks.fold(0, (n, t) => n + t.durationMs),
      tracks: tracks,
    );
  }

  Future<AlbumDetails> getAlbum(String id) async {
    final data = await getPlaylist(id);
    return AlbumDetails(
      id: id,
      title: data.title,
      artists: [TrackArtist(name: data.author ?? '')],
      cover: data.cover,
      trackCount: data.trackCount,
      durationMs: data.durationMs,
      tracks: data.tracks,
    );
  }

  Future<ArtistDetails> getArtist(String id) async {
    final channel = await client.channels
        .get(id)
        .timeout(const Duration(seconds: 15));
    final tracks = await client.channels
        .getUploads(id)
        .take(30)
        .map(mapVideo)
        .toList()
        .timeout(const Duration(seconds: 20));
    return ArtistDetails(
      id: id,
      name: channel.title,
      cover: Cover(url: channel.logoUrl),
      tracks: tracks,
    );
  }

  Future<RadioResponse> getRadio(
    String id, {
    int? k,
    String? waveId,
    List<String>? history,
  }) async {
    final track = await getTrack(id);
    final candidates = await search('${track.artists} music', type: 'track');
    final excluded = {id, ...?history};
    return RadioResponse(
      items: candidates
          .map((item) => item.track)
          .whereType<Track>()
          .where((t) => !excluded.contains(t.id))
          .take(k ?? 20)
          .toList(),
    );
  }
}
