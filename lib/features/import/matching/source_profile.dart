/// The profile of the track that is being imported.
///
/// Port of `src/shared/media/matching/sourceProfile.ts`.
library;

import 'artist_title.dart';
import 'artists.dart';
import 'junk.dart';

/// A track coming from an external source.
class ImportedTrack {
  const ImportedTrack({
    required this.id,
    required this.title,
    required this.artists,
    this.durationMs,
    this.coverUrl = '',
    this.album = '',
  });

  final String id;
  final String title;
  final List<String> artists;
  final int? durationMs;
  final String coverUrl;
  final String album;
}

/// The normalized profile of an imported track.
class SourceProfile {
  const SourceProfile({
    required this.title,
    required this.meta,
    required this.baseTitle,
    required this.fullClean,
    required this.versionTags,
    required this.artists,
    required this.primaryArtist,
    required this.hasTwoParts,
    required this.part0Clean,
    required this.part1Clean,
    this.durationMs,
  });

  final String title;
  final SourceMetadata meta;
  final String baseTitle;
  final String fullClean;
  final Set<String> versionTags;
  final List<String> artists;
  final String primaryArtist;
  final bool hasTwoParts;
  final String part0Clean;
  final String part1Clean;
  final int? durationMs;
}

/// Builds the profile of an imported track.
SourceProfile buildSourceProfile(ImportedTrack source) {
  final meta = cleanSourceMetadata(
    source.title,
    source.artists.isNotEmpty ? source.artists.first : null,
  );
  final parsed = parseArtistAndTitle(source.title);

  final artists = [...source.artists];
  if (meta.artist.isNotEmpty &&
      !artists.any((artist) => artistsMatch(artist, meta.artist))) {
    artists.add(meta.artist);
  }

  final titleParts = stripJunk(source.title).split(titleDelimiter);
  final hasTwoParts = titleParts.length == 2 &&
      titleParts[0].trim().isNotEmpty &&
      titleParts[1].trim().isNotEmpty;

  return SourceProfile(
    title: source.title,
    meta: meta,
    baseTitle: cleanBaseTitle(parsed.title.isNotEmpty ? parsed.title : source.title),
    fullClean: cleanBaseTitle(source.title),
    versionTags: meta.versionTags,
    artists: artists,
    primaryArtist: artists.isNotEmpty ? artists.first : '',
    hasTwoParts: hasTwoParts,
    part0Clean: hasTwoParts ? cleanBaseTitle(titleParts[0]) : '',
    part1Clean: hasTwoParts ? cleanBaseTitle(titleParts[1]) : '',
    durationMs: source.durationMs,
  );
}
