class MappedTrack {
  const MappedTrack({
    required this.id,
    required this.title,
    this.artistList = const <MappedArtist>[],
    this.coverUrl = '',
    this.durationMs = 0,
  });

  final String id;
  final String title;
  final List<MappedArtist> artistList;
  final String coverUrl;
  final int durationMs;
}

class MappedArtist {
  const MappedArtist({required this.name});

  final String name;
}

class InnertubeTrackMapper {
  static MappedTrack? mapTrack(Map<String, dynamic> payload) {
    final raw = payload['musicResponsiveListItemRenderer'];
    if (raw is! Map) {
      return null;
    }

    final id = raw['videoId'] ?? raw['playlistId'] ?? 'unknown';
    final title = raw['title'];
    final titleValue = title is Map ? title['runs'] : title;
    final plainTitle = titleValue is List && titleValue.isNotEmpty
        ? titleValue.first['text'] ?? 'Untitled'
        : titleValue ?? 'Untitled';

    return MappedTrack(
      id: id.toString(),
      title: plainTitle.toString(),
      artistList: const <MappedArtist>[],
      coverUrl: '',
      durationMs: 0,
    );
  }
}
