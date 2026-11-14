/// The parsing of the "artist - title" titles.
///
/// Port of `src/shared/media/matching/artistTitle.ts`.
library;

import 'junk.dart';
import 'version_tags.dart';

/// The title parsed into an artist and a title.
class ParsedArtistTitle {
  const ParsedArtistTitle({this.artist, required this.title, this.rawArtist, this.rawTitle});

  final String? artist;
  final String title;
  final String? rawArtist;
  final String? rawTitle;
}

/// The metadata extracted from a title.
class SourceMetadata {
  const SourceMetadata({
    required this.artist,
    required this.title,
    required this.cleanTitle,
    required this.versionTags,
    required this.searchQuery,
  });

  final String artist;
  final String title;
  final String cleanTitle;
  final Set<String> versionTags;
  final String searchQuery;
}

/// The delimiter between the artist and the title.
final RegExp titleDelimiter = RegExp(r'\s*[-–—:|~]\s*');

/// Splits a raw title into an artist and a title.
ParsedArtistTitle parseArtistAndTitle(String rawTitle) {
  final cleaned = stripJunk(rawTitle);
  final parts = cleaned.split(titleDelimiter);

  if (parts.length >= 3 &&
      parts[1].trim().length >= 2 &&
      parts[2].trim().isNotEmpty) {
    final artist = parts[1].trim();
    final title = parts.sublist(2).join(' - ').trim();
    return ParsedArtistTitle(
      artist: artist,
      title: title,
      rawArtist: artist,
      rawTitle: title,
    );
  }

  if (parts.length == 2 &&
      parts[0].trim().length >= 2 &&
      parts[1].trim().isNotEmpty &&
      RegExp(r'[^\p{N}\s]', unicode: true).hasMatch(parts[0])) {
    final artist = parts[0].trim();
    final title = parts[1].trim();
    return ParsedArtistTitle(
      artist: artist,
      title: title,
      rawArtist: artist,
      rawTitle: title,
    );
  }

  return ParsedArtistTitle(title: cleaned);
}

/// Extracts the metadata of a track from its title.
SourceMetadata cleanSourceMetadata(String rawTitle, [String? uploaderArtist]) {
  final parsed = parseArtistAndTitle(rawTitle);
  final versionTags = getVersionTags(rawTitle);
  final cleanedTitle = stripJunk(parsed.title);
  final artist = (parsed.artist ?? uploaderArtist ?? '').trim();

  final searchQuery = artist.isNotEmpty &&
          !cleanedTitle.toLowerCase().startsWith(artist.toLowerCase())
      ? '$artist $cleanedTitle'.trim()
      : cleanedTitle.trim();

  return SourceMetadata(
    artist: artist,
    title: cleanedTitle,
    cleanTitle: cleanBaseTitle(cleanedTitle),
    versionTags: versionTags,
    searchQuery: searchQuery.replaceAll(RegExp(r'\s+'), ' '),
  );
}
