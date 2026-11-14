import '../core/utils/json.dart';
import 'track.dart';

/// A playlist owned by a user.
class UserPlaylist {
  const UserPlaylist({
    required this.id,
    required this.title,
    this.description,
    this.isPublic = false,
    this.createdAt = '',
    this.updatedAt = '',
    this.revision = 0,
    this.ownerId,
    this.ownerUsername,
    this.ownerDisplayName,
    this.ownerAvatarUrl,
  });

  factory UserPlaylist.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const UserPlaylist(id: '', title: '');
    final owner = asRecord(json['owner']);
    return UserPlaylist(
      id: asString(json['id']),
      title: asString(json['title']),
      description: asStringOrNull(json['description']),
      isPublic: asBool(json['isPublic']),
      createdAt: asString(json['createdAt']),
      updatedAt: asString(json['updatedAt']),
      revision: asInt(json['revision']),
      ownerId: asStringOrNull(json['ownerId']),
      ownerUsername: owner == null ? null : asStringOrNull(owner['username']),
      ownerDisplayName:
          owner == null ? null : asStringOrNull(owner['displayName']),
      ownerAvatarUrl: owner == null ? null : asStringOrNull(owner['avatarUrl']),
    );
  }

  final String id;
  final String title;
  final String? description;
  final bool isPublic;
  final String createdAt;
  final String updatedAt;
  final int revision;
  final String? ownerId;
  final String? ownerUsername;
  final String? ownerDisplayName;
  final String? ownerAvatarUrl;

  /// A copy with a different title.
  UserPlaylist copyWith({String? title, String? description}) {
    return UserPlaylist(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      isPublic: isPublic,
      createdAt: createdAt,
      updatedAt: updatedAt,
      revision: revision,
      ownerId: ownerId,
      ownerUsername: ownerUsername,
      ownerDisplayName: ownerDisplayName,
      ownerAvatarUrl: ownerAvatarUrl,
    );
  }
}

/// A single entry inside a user playlist.
class UserPlaylistItem {
  const UserPlaylistItem({
    required this.id,
    required this.track,
    this.position = 0,
    this.addedAt = '',
  });

  factory UserPlaylistItem.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const UserPlaylistItem(id: '', track: Track(id: '', title: ''));
    return UserPlaylistItem(
      id: asString(json['id']),
      track: Track.fromJson(asRecord(json['track'])),
      position: asInt(json['position']),
      addedAt: asString(json['addedAt']),
    );
  }

  final String id;
  final Track track;
  final int position;
  final String addedAt;
}

/// A page of liked tracks.
class LikedTracksPage {
  const LikedTracksPage({this.items = const [], this.nextCursor});

  factory LikedTracksPage.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const LikedTracksPage();
    return LikedTracksPage(
      items: (json['items'] as List?)
              ?.map((e) {
                final record = asRecord(e) ?? const {};
                return (
                  Track.fromJson(asRecord(record['track'])),
                  asString(record['likedAt']),
                );
              })
              .toList(growable: false) ??
          const [],
      nextCursor: asStringOrNull(json['nextCursor']),
    );
  }

  final List<(Track, String)> items;
  final String? nextCursor;
}

/// A saved collection (album / artist / playlist) in the user's library.
class SavedCollection {
  const SavedCollection({
    required this.type,
    required this.id,
    this.title = '',
    this.subtitle = '',
    this.coverUrl = '',
    this.savedAt = '',
  });

  factory SavedCollection.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const SavedCollection(type: 'albums', id: '');
    }
    final type = asString(json['type'], 'albums');
    final cover = asRecord(json['cover']);
    return SavedCollection(
      type: type,
      id: asString(json['id']),
      title: asString(
        json['title'] ?? json['name'] ?? json['album'] ?? json['artist'],
      ),
      subtitle: asString(json['subtitle'] ?? json['artists'] ?? json['author']),
      coverUrl: asString(
        cover?['url'] ?? json['coverUrl'] ?? json['cover_url'] ?? json['cover'],
      ),
      savedAt: asString(json['savedAt']),
    );
  }

  final String type;
  final String id;
  final String title;
  final String subtitle;
  final String coverUrl;
  final String savedAt;
}
