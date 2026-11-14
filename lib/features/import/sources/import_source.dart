/// The detection of the source of an imported playlist.
///
/// Port of `src/features/library/services/import/detectImportSource.ts`.
library;

import 'apple_music_source.dart';
import 'deezer_source.dart';
import 'spotify_source.dart';
import 'youtube_source.dart';

/// The services an import can come from.
enum ImportSourceKind { youtube, spotify, deezer, appleMusic, unknown }

/// The detected source of a link.
class ImportSource {
  const ImportSource(this.kind, {this.id = '', this.type = ''});

  final ImportSourceKind kind;
  final String id;
  final String type;

  bool get isSupported =>
      kind == ImportSourceKind.youtube ||
      kind == ImportSourceKind.spotify ||
      kind == ImportSourceKind.deezer ||
      kind == ImportSourceKind.appleMusic;

  /// The name shown in the interface.
  String get label {
    switch (kind) {
      case ImportSourceKind.youtube:
        return 'YouTube';
      case ImportSourceKind.spotify:
        return 'Spotify';
      case ImportSourceKind.deezer:
        return 'Deezer';
      case ImportSourceKind.appleMusic:
        return 'Apple Music';
      case ImportSourceKind.unknown:
        return '';
    }
  }
}

/// Detects the source of a link.
ImportSource detectImportSource(String rawUrl) {
  final trimmed = rawUrl.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) {
    return const ImportSource(ImportSourceKind.unknown);
  }

  final host = uri.host.toLowerCase().replaceAll('music.', '');
  if (host.contains('youtube') || host == 'youtu.be') {
    final playlistId = YoutubeSource.playlistIdFromYoutube(trimmed);
    final videoId = YoutubeSource.videoIdFromYoutube(trimmed);
    return ImportSource(
      ImportSourceKind.youtube,
      id: playlistId ?? videoId ?? '',
      type: playlistId != null ? 'playlist' : 'video',
    );
  }

  if (host.contains('spotify')) {
    final entity = parseSpotifyUrl(trimmed);
    if (entity != null) {
      return ImportSource(
        ImportSourceKind.spotify,
        id: entity.id,
        type: entity.type.name,
      );
    }
    return const ImportSource(ImportSourceKind.spotify);
  }

  if (host.contains('deezer')) {
    return ImportSource(
      ImportSourceKind.deezer,
      id: DeezerSource.idFromUrl(trimmed) ?? '',
    );
  }

  if (host.contains('apple')) {
    final target = parseAppleMusicUrl(trimmed);
    return ImportSource(
      ImportSourceKind.appleMusic,
      id: target?.id ?? '',
      type: target?.type ?? '',
    );
  }

  return const ImportSource(ImportSourceKind.unknown);
}
