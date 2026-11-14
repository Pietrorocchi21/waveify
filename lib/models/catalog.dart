import '../core/utils/json.dart';
import 'track.dart';

/// A search result item — one of track / artist / album / playlist.
class SearchItem {
  const SearchItem({
    required this.type,
    required this.id,
    this.title = '',
    this.name = '',
    this.artists = const [],
    this.author,
    this.description,
    this.year,
    this.cover,
    this.track,
    this.explicit = false,
  });

  factory SearchItem.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SearchItem(type: 'track', id: '');
    final type = asString(json['type'], 'track');
    final cover = json['cover'] == null
        ? null
        : Cover.fromJson(asRecord(json['cover']));

    if (type == 'track') {
      return SearchItem(
        type: 'track',
        id: asString(json['id']),
        title: asString(json['title']),
        artists: (json['artists'] as List?)
                ?.map((e) => TrackArtist.fromJson(asRecord(e)))
                .toList(growable: false) ??
            const [],
        cover: cover,
        track: Track.fromJson(json),
        explicit: asBool(json['explicit']),
      );
    }

    return SearchItem(
      type: type,
      id: asString(json['id']),
      title: asString(json['title']),
      name: asString(json['name']),
      artists: (json['artists'] as List?)
              ?.map((e) => TrackArtist.fromJson(asRecord(e)))
              .toList(growable: false) ??
          const [],
      author: asStringOrNull(json['author']),
      description: asStringOrNull(json['description']),
      year: json['year'] == null ? null : asInt(json['year']),
      cover: cover,
      explicit: asBool(json['explicit']),
    );
  }

  final String type;
  final String id;
  final String title;
  final String name;
  final List<TrackArtist> artists;
  final String? author;
  final String? description;
  final int? year;
  final Cover? cover;
  final Track? track;
  final bool explicit;

  String get displayTitle => title.isNotEmpty ? title : name;

  String get displaySubtitle {
    if (artists.isNotEmpty) {
      return artists.map((a) => a.name).where((n) => n.isNotEmpty).join(', ');
    }
    return author ?? '';
  }
}

/// An album or release attached to an artist.
class ArtistAlbum {
  const ArtistAlbum({
    required this.id,
    required this.title,
    this.year,
    this.cover,
    this.explicit = false,
    this.trackCount = 0,
    this.releaseType = 'album',
  });

  factory ArtistAlbum.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ArtistAlbum(id: '', title: '');
    return ArtistAlbum(
      id: asString(json['id']),
      title: asString(json['title']),
      year: json['year'] == null ? null : asInt(json['year']),
      cover: json['cover'] == null
          ? null
          : Cover.fromJson(asRecord(json['cover'])),
      explicit: asBool(json['explicit']),
      trackCount: asInt(json['trackCount'] ?? json['totalTracks']),
      releaseType: asString(json['releaseType'], 'album'),
    );
  }

  final String id;
  final String title;
  final int? year;
  final Cover? cover;
  final bool explicit;
  final int trackCount;
  final String releaseType;
}

/// Full artist page payload.
class ArtistDetails {
  const ArtistDetails({
    required this.id,
    required this.name,
    this.bio,
    this.cover,
    this.monthlyListeners,
    this.verified = false,
    this.geniusImageUrl,
    this.geniusAka = const [],
    this.geniusUsername,
    this.tracks = const [],
    this.albums = const [],
    this.singles = const [],
  });

  factory ArtistDetails.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ArtistDetails(id: '', name: '');
    return ArtistDetails(
      id: asString(json['id']),
      name: asString(json['name']),
      bio: asStringOrNull(json['bio']),
      cover: json['cover'] == null
          ? null
          : Cover.fromJson(asRecord(json['cover'])),
      monthlyListeners: asStringOrNull(json['monthlyListeners']),
      verified: asBool(json['verified']),
      geniusImageUrl: asStringOrNull(json['geniusImageUrl']),
      geniusAka: (json['geniusAka'] as List?)
              ?.map((e) => asString(e))
              .where((e) => e.isNotEmpty)
              .toList(growable: false) ??
          const [],
      geniusUsername: asStringOrNull(json['geniusUsername']),
      tracks: (json['tracks'] as List?)
              ?.map((e) => Track.fromJson(asRecord(e)))
              .toList(growable: false) ??
          const [],
      albums: (json['albums'] as List?)
              ?.map((e) => ArtistAlbum.fromJson(asRecord(e)))
              .toList(growable: false) ??
          const [],
      singles: (json['singles'] as List?)
              ?.map((e) => ArtistAlbum.fromJson(asRecord(e)))
              .toList(growable: false) ??
          const [],
    );
  }

  final String id;
  final String name;
  final String? bio;
  final Cover? cover;
  final String? monthlyListeners;
  final bool verified;
  final String? geniusImageUrl;
  final List<String> geniusAka;
  final String? geniusUsername;
  final List<Track> tracks;
  final List<ArtistAlbum> albums;
  final List<ArtistAlbum> singles;
}

/// Full album payload.
class AlbumDetails {
  const AlbumDetails({
    required this.id,
    required this.title,
    this.artists = const [],
    this.year,
    this.cover,
    this.trackCount = 0,
    this.durationMs = 0,
    this.tracks = const [],
  });

  factory AlbumDetails.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AlbumDetails(id: '', title: '');
    return AlbumDetails(
      id: asString(json['id']),
      title: asString(json['title']),
      artists: (json['artists'] as List?)
              ?.map((e) => TrackArtist.fromJson(asRecord(e)))
              .toList(growable: false) ??
          const [],
      year: json['year'] == null ? null : asInt(json['year']),
      cover: json['cover'] == null
          ? null
          : Cover.fromJson(asRecord(json['cover'])),
      trackCount: asInt(json['trackCount']),
      durationMs: asDurationMs(json),
      tracks: (json['tracks'] as List?)
              ?.map((e) => Track.fromJson(asRecord(e)))
              .toList(growable: false) ??
          const [],
    );
  }

  final String id;
  final String title;
  final List<TrackArtist> artists;
  final int? year;
  final Cover? cover;
  final int trackCount;
  final int durationMs;
  final List<Track> tracks;
}

/// Full catalog playlist payload.
class CatalogPlaylistDetails {
  const CatalogPlaylistDetails({
    required this.id,
    required this.title,
    this.author,
    this.description,
    this.year,
    this.cover,
    this.trackCount = 0,
    this.durationMs = 0,
    this.tracks = const [],
  });

  factory CatalogPlaylistDetails.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const CatalogPlaylistDetails(id: '', title: '');
    return CatalogPlaylistDetails(
      id: asString(json['id']),
      title: asString(json['title']),
      author: asStringOrNull(json['author']),
      description: asStringOrNull(json['description']),
      year: json['year'] == null ? null : asInt(json['year']),
      cover: json['cover'] == null
          ? null
          : Cover.fromJson(asRecord(json['cover'])),
      trackCount: asInt(json['trackCount']),
      durationMs: asDurationMs(json),
      tracks: (json['tracks'] as List?)
              ?.map((e) => Track.fromJson(asRecord(e)))
              .toList(growable: false) ??
          const [],
    );
  }

  final String id;
  final String title;
  final String? author;
  final String? description;
  final int? year;
  final Cover? cover;
  final int trackCount;
  final int durationMs;
  final List<Track> tracks;
}

/// Radio station payload.
class RadioResponse {
  const RadioResponse({this.items = const []});

  factory RadioResponse.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const RadioResponse();
    return RadioResponse(
      items: (json['items'] as List?)
              ?.map((e) => Track.fromJson(asRecord(e)))
              .toList(growable: false) ??
          const [],
    );
  }

  final List<Track> items;
}
