import 'package:waveify/core/config/app_config.dart';
import 'package:waveify/core/utils/json.dart';

/// A track artist reference.
class TrackArtist {
  const TrackArtist({this.id = '', required this.name});

  factory TrackArtist.fromJson(Object? json) {
    if (json == null) return const TrackArtist(name: '');
    if (json is String) return TrackArtist(name: json);
    final map = json is Map
        ? Map<String, dynamic>.from(json)
        : const <String, dynamic>{};
    return TrackArtist(
      id: asString(map['id'] ?? map['artistId']),
      name: asString(map['name'] ?? map['title']),
    );
  }

  final String id;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  @override
  bool operator ==(Object other) =>
      other is TrackArtist && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// A track album reference.
class TrackAlbum {
  const TrackAlbum({this.id = '', required this.title});

  factory TrackAlbum.fromJson(Object? json) {
    if (json == null) return const TrackAlbum(title: '');
    final map = json is Map
        ? Map<String, dynamic>.from(json)
        : const <String, dynamic>{};
    return TrackAlbum(
      id: asString(map['id']),
      title: asString(map['title'] ?? map['name']),
    );
  }

  final String id;
  final String title;

  Map<String, dynamic> toJson() => {'id': id, 'title': title};

  @override
  bool operator ==(Object other) =>
      other is TrackAlbum && other.id == id && other.title == title;

  @override
  int get hashCode => Object.hash(id, title);
}

/// Cover artwork descriptor.
class Cover {
  const Cover({
    required this.url,
    this.width = 0,
    this.height = 0,
    this.fallbackUrl,
  });

  factory Cover.fromJson(Object? json) {
    if (json == null) return const Cover(url: '');
    if (json is String) return Cover(url: json);
    final map = json is Map
        ? Map<String, dynamic>.from(json)
        : const <String, dynamic>{};
    return Cover(
      url: asString(map['url']),
      width: asInt(map['width']),
      height: asInt(map['height']),
      fallbackUrl: asStringOrNull(map['fallbackUrl']),
    );
  }

  final String url;
  final int width;
  final int height;
  final String? fallbackUrl;

  Map<String, dynamic> toJson() => {
    'url': url,
    'width': width,
    'height': height,
    if (fallbackUrl != null) 'fallbackUrl': fallbackUrl,
  };
}

/// The canonical client-side track.
///
/// Mirrors `src/shared/types/track.ts` plus the fields carried by the API
/// contracts (`src/shared/contracts/track.ts`).
class Track {
  const Track({
    required this.id,
    required this.title,
    this.artists = '',
    this.artistId,
    this.artistList = const [],
    this.coverUrl = '',
    this.sourceUrl = '',
    this.durationMs = 0,
    this.playCount = 0,
    this.explicit,
    this.releaseDate,
    this.album,
    this.playlistItemId,
    this.viewerLiked = false,
    this.downloadable = true,
  });

  /// Normalises the many shapes the API uses for a track into one model.
  ///
  /// Mirrors `toClientTrack` in `src/shared/api/track.ts`.
  factory Track.fromJson(Map<String, dynamic>? source) {
    if (source == null) {
      return const Track(id: '', title: '');
    }

    var artistsList = <TrackArtist>[];

    final rawArtistList = source['artistList'];
    if (rawArtistList is List && rawArtistList.isNotEmpty) {
      artistsList = rawArtistList
          .map((e) => TrackArtist.fromJson(asRecord(e)))
          .toList(growable: false);
    } else {
      final rawArtists = source['artists'];
      if (rawArtists is List && rawArtists.isNotEmpty) {
        artistsList = rawArtists
            .map((e) => TrackArtist.fromJson(asRecord(e)))
            .toList(growable: false);
      } else if (source['artist'] is Map) {
        artistsList = [TrackArtist.fromJson(asRecord(source['artist']))];
      } else if (rawArtists is String && rawArtists.trim().isNotEmpty) {
        final rawArtistId = asString(source['artistId'] ?? source['artist_id']);
        final parts = rawArtists
            .split(',')
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toList();
        artistsList = [
          for (var i = 0; i < parts.length; i++)
            TrackArtist(id: i == 0 ? rawArtistId : '', name: parts[i]),
        ];
      } else if (source['artist'] is String &&
          (source['artist'] as String).trim().isNotEmpty) {
        artistsList = [
          TrackArtist(
            id: asString(source['artistId'] ?? source['artist_id']),
            name: (source['artist'] as String).trim(),
          ),
        ];
      }
    }

    String artistsString;
    final rawArtists = source['artists'];
    if (rawArtists is String) {
      artistsString = rawArtists;
    } else if (source['artist'] is String) {
      artistsString = source['artist'] as String;
    } else {
      artistsString = artistsList
          .map((a) => a.name)
          .where((n) => n.isNotEmpty)
          .join(', ');
    }

    final knownArtist = artistsList.firstWhere(
      (a) => a.id.isNotEmpty && a.id != 'unknown',
      orElse: () => const TrackArtist(name: ''),
    );
    final fallbackArtistId = asString(
      source['artistId'] ?? source['artist_id'],
    );
    final primaryArtistId = knownArtist.id.isNotEmpty
        ? knownArtist.id
        : (fallbackArtistId.isNotEmpty && fallbackArtistId != 'unknown'
              ? fallbackArtistId
              : (artistsList.isNotEmpty && artistsList.first.id != 'unknown'
                    ? artistsList.first.id
                    : null));

    final rawCover = source['cover'];
    String coverUrl = '';
    if (rawCover is Map) {
      coverUrl = asString(rawCover['url'] ?? rawCover);
    } else if (rawCover is String) {
      coverUrl = rawCover;
    } else if (rawCover != null) {
      coverUrl = asString(rawCover);
    }
    if (coverUrl.isEmpty) {
      coverUrl = asString(source['coverUrl'] ?? source['cover_url']);
    }
    // The backend can answer with a relative path.
    coverUrl = AppConfig.mediaUrl(coverUrl);

    TrackAlbum? album;
    final rawAlbum = source['album'];
    if (rawAlbum is Map) {
      final parsed = TrackAlbum.fromJson(asRecord(rawAlbum));
      if (parsed.id.isNotEmpty || parsed.title.isNotEmpty) album = parsed;
    }

    final viewer = asRecord(source['viewer']);

    return Track(
      id: asString(source['id']),
      title: asString(source['title']),
      artists: artistsString,
      artistId: primaryArtistId,
      artistList: artistsList.isEmpty ? null : artistsList,
      coverUrl: coverUrl,
      sourceUrl: asString(
        source['sourceUrl'] ?? source['streamUrl'] ?? source['audioUrl'],
      ),
      durationMs: asDurationMs(source),
      playCount: asInt(source['playCount']),
      explicit: source['explicit'] == null ? null : asBool(source['explicit']),
      releaseDate: asStringOrNull(source['releaseDate']),
      album: album,
      playlistItemId: asStringOrNull(source['playlistItemId']),
      viewerLiked: viewer != null && asBool(viewer['liked']),
      downloadable: source['downloadable'] != false,
    );
  }

  final String id;
  final String title;
  final String artists;
  final String? artistId;
  final List<TrackArtist>? artistList;
  final String coverUrl;
  final String sourceUrl;
  final int durationMs;
  final int playCount;
  final bool? explicit;
  final String? releaseDate;
  final TrackAlbum? album;
  final String? playlistItemId;
  final bool viewerLiked;
  final bool downloadable;

  /// Snapshot shape sent to the server when liking a track.
  Map<String, dynamic> toSnapshot() => {
    'id': id,
    'title': title,
    if (sourceUrl.isNotEmpty) 'sourceUrl': sourceUrl,
    'artists': [
      for (final a
          in (artistList?.isNotEmpty == true
              ? artistList!
              : [TrackArtist(id: artistId ?? '', name: artists)]))
        {'id': a.id.isEmpty ? 'unknown' : a.id, 'name': a.name},
    ],
    if (album != null) 'album': {'id': album!.id, 'title': album!.title},
    if (coverUrl.isNotEmpty)
      'cover': {'url': coverUrl, 'width': 512, 'height': 512},
    'durationMs': durationMs,
    'downloadable': downloadable,
  };

  Track copyWith({
    String? id,
    String? title,
    String? artists,
    String? artistId,
    List<TrackArtist>? artistList,
    String? coverUrl,
    String? sourceUrl,
    int? durationMs,
    int? playCount,
    bool? explicit,
    String? releaseDate,
    TrackAlbum? album,
    String? playlistItemId,
    bool? viewerLiked,
    bool? downloadable,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artists: artists ?? this.artists,
      artistId: artistId ?? this.artistId,
      artistList: artistList ?? this.artistList,
      coverUrl: coverUrl ?? this.coverUrl,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      durationMs: durationMs ?? this.durationMs,
      playCount: playCount ?? this.playCount,
      explicit: explicit ?? this.explicit,
      releaseDate: releaseDate ?? this.releaseDate,
      album: album ?? this.album,
      playlistItemId: playlistItemId ?? this.playlistItemId,
      viewerLiked: viewerLiked ?? this.viewerLiked,
      downloadable: downloadable ?? this.downloadable,
    );
  }

  @override
  String toString() => 'Track($id, $title)';
}
