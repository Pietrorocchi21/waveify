import '../core/utils/json.dart';
import 'track.dart';

/// The context a track was played from.
class PlaybackContext {
  const PlaybackContext({required this.type, this.id});

  factory PlaybackContext.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const PlaybackContext(type: 'direct');
    return PlaybackContext(
      type: asString(json['type'], 'direct'),
      id: asStringOrNull(json['id']),
    );
  }

  final String type;
  final String? id;

  bool get isRadio => type == 'radio';

  Map<String, dynamic> toJson() => {'type': type, if (id != null) 'id': id};
}

/// One entry in the playback history.
class PlaybackHistoryItem {
  const PlaybackHistoryItem({
    required this.id,
    required this.track,
    this.playedDurationMs = 0,
    this.completionRate = 0,
    this.completed = false,
    this.skipped = false,
    this.loopCount = 0,
    this.hasSeekBackward = false,
    this.context,
    this.listenedAt = '',
  });

  factory PlaybackHistoryItem.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const PlaybackHistoryItem(id: '', track: Track(id: '', title: ''));
    }
    return PlaybackHistoryItem(
      id: asString(json['id']),
      track: Track.fromJson(asRecord(json['track'])),
      playedDurationMs: asInt(json['playedDurationMs']),
      completionRate: asDouble(json['completionRate']),
      completed: asBool(json['completed']),
      skipped: asBool(json['skipped']),
      loopCount: asInt(json['loopCount']),
      hasSeekBackward: asBool(json['hasSeekBackward']),
      context: json['context'] == null
          ? null
          : PlaybackContext.fromJson(asRecord(json['context'])),
      listenedAt: asString(json['listenedAt']),
    );
  }

  final String id;
  final Track track;
  final int playedDurationMs;
  final double completionRate;
  final bool completed;
  final bool skipped;
  final int loopCount;
  final bool hasSeekBackward;
  final PlaybackContext? context;
  final String listenedAt;
}

/// A page of playback history.
class PlaybackHistoryResponse {
  const PlaybackHistoryResponse({this.items = const [], this.nextCursor});

  factory PlaybackHistoryResponse.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const PlaybackHistoryResponse();
    return PlaybackHistoryResponse(
      items: (json['items'] as List?)
              ?.map((e) => PlaybackHistoryItem.fromJson(asRecord(e)))
              .toList(growable: false) ??
          const [],
      nextCursor: asStringOrNull(json['nextCursor']),
    );
  }

  final List<PlaybackHistoryItem> items;
  final String? nextCursor;
}

/// A track in the "popular" leaderboard.
class PopularTrackItem {
  const PopularTrackItem({
    required this.rank,
    required this.track,
    this.playCount = 0,
    this.uniqueListeners = 0,
    this.score = 0,
  });

  factory PopularTrackItem.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const PopularTrackItem(rank: 0, track: Track(id: '', title: ''));
    }
    return PopularTrackItem(
      rank: asInt(json['rank']),
      track: Track.fromJson(asRecord(json['track'])),
      playCount: asInt(json['playCount']),
      uniqueListeners: asInt(json['uniqueListeners']),
      score: asDouble(json['score']),
    );
  }

  final int rank;
  final Track track;
  final int playCount;
  final int uniqueListeners;
  final double score;
}

/// Popular tracks response.
class PopularTracksResponse {
  const PopularTracksResponse({
    this.window = '7d',
    this.generatedAt = '',
    this.items = const [],
  });

  factory PopularTracksResponse.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const PopularTracksResponse();
    return PopularTracksResponse(
      window: asString(json['window'], '7d'),
      generatedAt: asString(json['generatedAt']),
      items: (json['items'] as List?)
              ?.map((e) => PopularTrackItem.fromJson(asRecord(e)))
              .toList(growable: false) ??
          const [],
    );
  }

  final String window;
  final String generatedAt;
  final List<PopularTrackItem> items;
}

/// A daily mix recommendation.
class DailyMixItem {
  const DailyMixItem({
    required this.id,
    required this.title,
    this.description = '',
    this.clusterArtists = const [],
    this.cover,
    this.trackCount = 0,
    this.tracks = const [],
  });

  factory DailyMixItem.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DailyMixItem(id: '', title: '');
    return DailyMixItem(
      id: asString(json['id']),
      title: asString(json['title']),
      description: asString(json['description']),
      clusterArtists: (json['clusterArtists'] as List?)
              ?.map((e) => asString(e))
              .toList(growable: false) ??
          const [],
      cover: json['cover'] == null
          ? null
          : Cover.fromJson(asRecord(json['cover'])),
      trackCount: asInt(json['trackCount']),
      tracks: (json['tracks'] as List?)
              ?.map((e) => Track.fromJson(asRecord(e)))
              .toList(growable: false) ??
          const [],
    );
  }

  final String id;
  final String title;
  final String description;
  final List<String> clusterArtists;
  final Cover? cover;
  final int trackCount;
  final List<Track> tracks;
}

/// Daily mixes response.
class DailyMixesResponse {
  const DailyMixesResponse({this.items = const [], this.generatedAt = ''});

  factory DailyMixesResponse.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DailyMixesResponse();
    return DailyMixesResponse(
      items: (json['items'] as List?)
              ?.map((e) => DailyMixItem.fromJson(asRecord(e)))
              .toList(growable: false) ??
          const [],
      generatedAt: asString(json['generatedAt']),
    );
  }

  final List<DailyMixItem> items;
  final String generatedAt;
}

/// A leaderboard row.
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.userId,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.playedDurationMs = 0,
    this.playCount = 0,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const LeaderboardEntry(rank: 0, userId: '');
    final user = asRecord(json['user']);
    return LeaderboardEntry(
      rank: asInt(json['rank']),
      userId: asString(user?['id']),
      username: user == null ? null : asStringOrNull(user['username']),
      displayName: user == null ? null : asStringOrNull(user['displayName']),
      avatarUrl: user == null ? null : asStringOrNull(user['avatarUrl']),
      playedDurationMs: asInt(json['playedDurationMs']),
      playCount: asInt(json['playCount']),
    );
  }

  final int rank;
  final String userId;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final int playedDurationMs;
  final int playCount;

  String get label {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final handle = username?.trim();
    if (handle != null && handle.isNotEmpty) return '@$handle';
    return 'Unknown';
  }
}

/// A leaderboard response.
class LeaderboardResponse {
  const LeaderboardResponse({
    this.type = 'global',
    this.targetId = '',
    this.period = 'weekly',
    this.entries = const [],
    this.updatedAt = '',
  });

  factory LeaderboardResponse.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const LeaderboardResponse();
    return LeaderboardResponse(
      type: asString(json['type'], 'global'),
      targetId: asString(json['targetId']),
      period: asString(json['period'], 'weekly'),
      entries: (json['entries'] as List?)
              ?.map((e) => LeaderboardEntry.fromJson(asRecord(e)))
              .toList(growable: false) ??
          const [],
      updatedAt: asString(json['updatedAt']),
    );
  }

  final String type;
  final String targetId;
  final String period;
  final List<LeaderboardEntry> entries;
  final String updatedAt;
}
