import '../local/local_library_store.dart';
import '../media/innertube/innertube_catalog.dart';
import '../media/innertube/stream_resolver.dart';
import '../../models/track.dart';
import '../network/waveify_api.dart';

/// The provider family behind a music source.
enum MusicProviderKind {
  local,
  waveify,
  youtubeMusic,
  soundCloud,
  spotifyImport,
  deezerImport,
  appleMusicImport,
  generic,
}

/// A single track candidate coming from one provider.
class MusicSearchResult {
  const MusicSearchResult({
    required this.id,
    required this.title,
    required this.artists,
    required this.providerId,
    required this.sourceKind,
    this.coverUrl = '',
    this.durationMs = 0,
    this.streamUrl,
    this.score = 0,
    this.quality = 0,
    this.explicit = false,
  });

  final String id;
  final String title;
  final String artists;
  final String providerId;
  final MusicProviderKind sourceKind;
  final String coverUrl;
  final int durationMs;
  final String? streamUrl;
  final int score;
  final int quality;
  final bool explicit;

  String get dedupKey {
    final normalizedTitle = title.trim().toLowerCase();
    final normalizedArtists = artists.trim().toLowerCase();
    final seconds = durationMs == 0 ? 0 : (durationMs ~/ 1000);
    return '$normalizedTitle|$normalizedArtists|$seconds';
  }

  MusicSearchResult withScore({required int score, required int quality}) {
    return MusicSearchResult(
      id: id,
      title: title,
      artists: artists,
      providerId: providerId,
      sourceKind: sourceKind,
      coverUrl: coverUrl,
      durationMs: durationMs,
      streamUrl: streamUrl,
      score: score,
      quality: quality,
      explicit: explicit,
    );
  }
}

/// A music provider exposes the search and playback contract shared by the
/// player, regardless of provider implementation.
abstract class MusicSource {
  String get id;
  MusicProviderKind get kind;
  bool get isEnabled;

  Future<List<MusicSearchResult>> search(String query, {int limit = 20});

  Future<MusicSearchResult?> resolveTrack(String trackId);

  Future<String?> resolveStreamUrl(MusicSearchResult item);
}

/// Local-first client fallback: the app can run without a remote backend, but
/// every provider integration must still conform to the same contract.
class LocalMusicSource extends MusicSource {
  LocalMusicSource({this.store});
  final LocalLibraryStore? store;
  MusicSearchResult _result(Track track) => MusicSearchResult(
    id: track.id,
    title: track.title,
    artists: track.artists,
    providerId: id,
    sourceKind: kind,
    coverUrl: track.coverUrl,
    durationMs: track.durationMs,
    streamUrl: track.sourceUrl.isEmpty ? null : track.sourceUrl,
    score: 100,
    quality: 100,
  );
  @override
  String get id => 'local';

  @override
  MusicProviderKind get kind => MusicProviderKind.local;

  @override
  bool get isEnabled => true;

  @override
  Future<List<MusicSearchResult>> search(String query, {int limit = 20}) async {
    if (query.trim().isEmpty || store == null) return const [];
    return store!.read(
      (data) => (data['tracks'] as Map).values
          .map((raw) => Track.fromJson(Map<String, dynamic>.from(raw as Map)))
          .where(
            (track) => '${track.title} ${track.artists}'.toLowerCase().contains(
              query.trim().toLowerCase(),
            ),
          )
          .take(limit)
          .map(_result)
          .toList(),
    );
  }

  @override
  Future<MusicSearchResult?> resolveTrack(String trackId) async {
    if (store == null) return null;
    return store!.read((data) {
      final raw = (data['tracks'] as Map)[trackId];
      return raw == null
          ? null
          : _result(Track.fromJson(Map<String, dynamic>.from(raw as Map)));
    });
  }

  @override
  Future<String?> resolveStreamUrl(MusicSearchResult item) async =>
      item.streamUrl;
}

/// Remote provider backed by the generic Waveify backend.
///
/// This layer is intentionally thin: it does not hardcode any proprietary logic.
/// It only exposes a standard provider contract for a server that can resolve
/// tracks and streams.
class WaveifyRemoteSource extends MusicSource {
  WaveifyRemoteSource({required this._api});

  final WaveifyApi _api;

  @override
  String get id => 'waveify-remote';

  @override
  MusicProviderKind get kind => MusicProviderKind.waveify;

  @override
  bool get isEnabled => true;

  @override
  Future<List<MusicSearchResult>> search(String query, {int limit = 20}) async {
    if (query.trim().isEmpty) return const [];

    try {
      final items = await _api.search(query, type: 'track');
      final matches = <MusicSearchResult>[];
      for (final item in items.take(limit)) {
        final track = item.track ?? const Track(id: '', title: '');
        final title = track.title.isEmpty ? item.displayTitle : track.title;
        final artists = track.artists.isEmpty
            ? item.displaySubtitle
            : track.artists;
        matches.add(
          MusicSearchResult(
            id: track.id.isEmpty ? item.id : track.id,
            title: title,
            artists: artists,
            providerId: id,
            sourceKind: kind,
            coverUrl: track.coverUrl.isEmpty
                ? (item.cover?.url ?? '')
                : track.coverUrl,
            durationMs: track.durationMs,
            score: 80,
            quality: 80,
            explicit: track.explicit ?? item.explicit,
          ),
        );
      }
      return matches;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<MusicSearchResult?> resolveTrack(String trackId) async {
    try {
      final track = await _api.getTrack(trackId);
      return MusicSearchResult(
        id: track.id,
        title: track.title,
        artists: track.artists,
        providerId: id,
        sourceKind: kind,
        coverUrl: track.coverUrl,
        durationMs: track.durationMs,
        score: 80,
        quality: 80,
        explicit: track.explicit ?? false,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> resolveStreamUrl(MusicSearchResult item) async {
    if (item.streamUrl != null && item.streamUrl!.isNotEmpty) {
      return item.streamUrl;
    }
    try {
      final stream = await _api.getTrackStream(item.id);
      return stream['url'] as String?;
    } catch (_) {
      return null;
    }
  }
}

/// A concrete YouTube-backed music provider placeholder.
///
/// The underlying catalog abstraction is intentionally generic: when a proper
/// YouTube Music client is enabled, this provider will resolve audio using the
/// existing stream resolver and fallback to the remote backend automatically.
class YouTubeMusicSource extends MusicSource {
  YouTubeMusicSource({InnertubeCatalog? catalog, StreamResolver? resolver})
    : _catalog = catalog ?? InnertubeCatalog(),
      _resolver = resolver ?? StreamResolver();

  final InnertubeCatalog _catalog;
  final StreamResolver _resolver;

  @override
  String get id => 'youtube-music';

  @override
  MusicProviderKind get kind => MusicProviderKind.youtubeMusic;

  @override
  bool get isEnabled => true;

  @override
  Future<List<MusicSearchResult>> search(String query, {int limit = 20}) async {
    if (query.trim().isEmpty) return const [];

    try {
      final items = await _catalog.search(query, type: 'track');
      return items
          .take(limit)
          .map((item) {
            final track = item.track ?? const Track(id: '', title: '');
            final title = track.title.isEmpty ? item.displayTitle : track.title;
            final artists = track.artists.isEmpty
                ? item.displaySubtitle
                : track.artists;
            return MusicSearchResult(
              id: track.id.isEmpty ? item.id : track.id,
              title: title,
              artists: artists,
              providerId: id,
              sourceKind: kind,
              coverUrl: track.coverUrl.isEmpty
                  ? (item.cover?.url ?? '')
                  : track.coverUrl,
              durationMs: track.durationMs,
              score: 70,
              quality: 70,
              explicit: track.explicit ?? item.explicit,
            );
          })
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<MusicSearchResult?> resolveTrack(String trackId) async {
    try {
      final track = await _catalog.getTrack(trackId);
      return MusicSearchResult(
        id: track.id,
        title: track.title,
        artists: track.artists,
        providerId: id,
        sourceKind: kind,
        coverUrl: track.coverUrl,
        durationMs: track.durationMs,
        score: 70,
        quality: 70,
        explicit: track.explicit ?? false,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> resolveStreamUrl(MusicSearchResult item) async {
    try {
      final stream = await _resolver.resolveDirectAudioStream(item.id);
      return stream.url.isNotEmpty ? stream.url : item.streamUrl;
    } catch (_) {
      return item.streamUrl;
    }
  }
}
