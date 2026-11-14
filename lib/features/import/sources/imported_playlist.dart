import '../matching/source_profile.dart';

/// A playlist coming from an external source.
class ImportedPlaylist {
  const ImportedPlaylist({
    required this.source,
    required this.sourceUrl,
    this.title = '',
    this.description = '',
    this.author = '',
    this.coverUrl = '',
    this.tracks = const [],
  });

  final String source;
  final String sourceUrl;
  final String title;
  final String description;
  final String author;
  final String coverUrl;
  final List<ImportedTrack> tracks;
}
