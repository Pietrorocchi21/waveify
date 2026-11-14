/// The import of the Spotify playlists, albums and tracks.
///
/// Port of `src/features/library/services/import/sources/spotify/`.
///
/// The data comes from the public embed page of Spotify: no token and no
/// secret are involved, so the import does not break when Spotify changes
/// its internal authentication.
library;

import 'dart:convert';

import '../../../core/utils/json.dart';
import '../matching/source_profile.dart';
import 'imported_playlist.dart';
import 'public_fetcher.dart';

/// The kind of entity a Spotify URL points at.
enum SpotifyEntityType { playlist, album, track }

/// The entity of a Spotify URL.
class SpotifyEntity {
  const SpotifyEntity(this.type, this.id);

  final SpotifyEntityType type;
  final String id;
}

/// Reads the entity of a Spotify URL.
SpotifyEntity? parseSpotifyUrl(String rawUrl) {
  final trimmed = rawUrl.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) return null;

  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

  // https://open.spotify.com/embed/playlist/<id>
  for (var i = 0; i + 1 < segments.length; i++) {
    final type = _entityTypeOf(segments[i]);
    if (type != null && RegExp(r'^[a-zA-Z0-9]+$').hasMatch(segments[i + 1])) {
      return SpotifyEntity(type, segments[i + 1]);
    }
  }

  // https://open.spotify.com/playlist/<id>
  if (segments.isNotEmpty) {
    final last = segments.last;
    if (RegExp(r'^[a-zA-Z0-9]+$').hasMatch(last)) {
      final typeSegment = segments
          .map(_entityTypeOf)
          .where((t) => t != null)
          .firstOrNull;
      return SpotifyEntity(typeSegment ?? SpotifyEntityType.playlist, last);
    }
  }

  return null;
}

SpotifyEntityType? _entityTypeOf(String segment) {
  switch (segment) {
    case 'playlist':
      return SpotifyEntityType.playlist;
    case 'album':
      return SpotifyEntityType.album;
    case 'track':
      return SpotifyEntityType.track;
    default:
      return null;
  }
}

/// The Spotify import source.
class SpotifySource {
  SpotifySource({PublicFetcher? fetcher}) : _fetcher = fetcher ?? PublicFetcher();

  final PublicFetcher _fetcher;

  /// Imports a Spotify playlist, album or track.
  Future<ImportedPlaylist> import(String rawUrl) async {
    final entity = parseSpotifyUrl(rawUrl);
    if (entity == null) {
      throw StateError('The Spotify URL is not valid.');
    }

    final url = 'https://open.spotify.com/embed/'
        '${entity.type.name}/${Uri.encodeComponent(entity.id)}';
    final html = await _fetcher.text(url);
    final data = _parseEmbedHtml(html, entity);

    if (data.tracks.isEmpty) {
      throw StateError(
        'No track could be extracted from this Spotify '
        '${entity.type.name}. Check that it is public.',
      );
    }

    return ImportedPlaylist(
      source: 'spotify',
      sourceUrl: rawUrl,
      title: data.title,
      description: data.description,
      author: data.author,
      coverUrl: data.coverUrl,
      tracks: data.tracks,
    );
  }

  /// The data extracted from the embed page.
  static SpotifyEmbedData _parseEmbedHtml(String html, SpotifyEntity entity) {
    final json = _embedJson(html);
    final pageProps = asRecord(asRecord(json?['props'])?['pageProps']);
    final state = asRecord(pageProps?['state']);
    final data = asRecord(state?['data']);
    final found = asRecord(data?['entity']) ?? asRecord(findFirst(json, 'entity'));
    if (found == null) return const SpotifyEmbedData();

    final title = trimmedString(found['title']) ?? trimmedString(found['name']) ?? '';
    final description = trimmedString(found['subtitle']) ?? '';

    final tracks = <ImportedTrack>[];
    for (final raw in asArray(found['trackList'])) {
      final item = asRecord(raw);
      if (item == null) continue;
      final trackTitle = trimmedString(item['title']);
      if (trackTitle == null) continue;

      final uri = item['uri'] is String ? item['uri'] as String : '';
      final sourceId =
          uri.isEmpty ? '${item['uid'] ?? ''}' : uri.split(':').last;

      tracks.add(
        ImportedTrack(
          id: sourceId,
          title: trackTitle,
          artists: _splitArtists(item['subtitle']),
          album: entity.type == SpotifyEntityType.album ? title : '',
          durationMs: _durationMs(item['duration']),
          coverUrl: '',
        ),
      );
    }

    // A single track has no track list.
    if (tracks.isEmpty && entity.type == SpotifyEntityType.track && title.isNotEmpty) {
      tracks.add(
        ImportedTrack(
          id: entity.id,
          title: title,
          artists: _splitArtists(found['subtitle']),
          durationMs: _durationMs(found['duration']),
        ),
      );
    }

    return SpotifyEmbedData(
      title: title,
      description: description,
      author: _splitArtists(found['subtitle']).firstOrNull ?? '',
      coverUrl: _coverUrl(found),
      tracks: tracks,
    );
  }

  static Map<String, dynamic>? _embedJson(String html) {
    final nextData = RegExp(
      r'<script id="__NEXT_DATA__"[^>]*>([\s\S]*?)</script>',
    ).firstMatch(html);
    if (nextData != null) {
      final parsed = _parseJson(nextData.group(1) ?? '');
      if (parsed != null) return parsed;
    }

    final initialState = RegExp(
      r'<script id="(?:initial-state|session)"[^>]*>([\s\S]*?)</script>',
    ).firstMatch(html);
    if (initialState != null) {
      return _parseJson(initialState.group(1) ?? '');
    }
    return null;
  }

  static Map<String, dynamic>? _parseJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  static List<String> _splitArtists(Object? subtitle) {
    if (subtitle is! String) return const [];
    return subtitle
        .split(RegExp(r',[\s ]+'))
        .map((artist) => artist.trim())
        .where((artist) => artist.isNotEmpty)
        .toList();
  }

  static int? _durationMs(Object? duration) {
    if (duration is num) return duration.round();
    if (duration is String) {
      // The embed uses "3:45".
      final parts = duration.split(':');
      if (parts.length == 2) {
        final minutes = int.tryParse(parts[0]);
        final seconds = int.tryParse(parts[1]);
        if (minutes != null && seconds != null) {
          return (minutes * 60 + seconds) * 1000;
        }
      }
    }
    return null;
  }

  static String _coverUrl(Map<String, dynamic> entity) {
    for (final key in const ['image', 'coverArt', 'coverImage']) {
      final value = asRecord(entity[key]);
      final sources = asRecord(value?['sources']);
      final url = trimmedString(sources?['large']);
      if (url != null) return url;
    }
    return '';
  }
}

/// The data extracted from the Spotify embed page.
class SpotifyEmbedData {
  const SpotifyEmbedData({
    this.title = '',
    this.description = '',
    this.author = '',
    this.coverUrl = '',
    this.tracks = const [],
  });

  final String title;
  final String description;
  final String author;
  final String coverUrl;
  final List<ImportedTrack> tracks;
}
