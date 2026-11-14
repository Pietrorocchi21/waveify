import '../core/utils/json.dart';

/// Public user profile.
class PublicUser {
  const PublicUser({
    required this.id,
    this.email,
    this.username,
    this.displayName,
    this.avatarUrl,
    this.bio,
    this.isPublic = false,
    this.showActivity = true,
    this.showHistory = true,
    this.showLikedTracks = true,
    this.participateLeaderboards = true,
  });

  factory PublicUser.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const PublicUser(id: '');
    return PublicUser(
      id: asString(json['id']),
      email: asStringOrNull(json['email']),
      username: asStringOrNull(json['username']),
      displayName: asStringOrNull(json['displayName']),
      avatarUrl: asStringOrNull(json['avatarUrl']),
      bio: asStringOrNull(json['bio']),
      isPublic: asBool(json['isPublic']),
      showActivity: asBool(json['showActivity'], true),
      showHistory: asBool(json['showHistory'], true),
      showLikedTracks: asBool(json['showLikedTracks'], true),
      participateLeaderboards: asBool(json['participateLeaderboards'], true),
    );
  }

  final String id;
  final String? email;
  final String? username;
  final String? displayName;
  final String? avatarUrl;
  final String? bio;
  final bool isPublic;
  final bool showActivity;
  final bool showHistory;
  final bool showLikedTracks;
  final bool participateLeaderboards;

  String get displayLabel {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final handle = username?.trim();
    if (handle != null && handle.isNotEmpty) return '@$handle';
    return email ?? 'Unknown';
  }
}

/// Auth tokens returned by the API.
class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    this.accessTokenExpiresAt,
    this.user,
    this.expiresAt,
  });

  factory AuthTokens.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const AuthTokens(accessToken: '', refreshToken: '');
    }
    return AuthTokens(
      accessToken: asString(json['accessToken']),
      refreshToken: asString(json['refreshToken']),
      accessTokenExpiresAt: asStringOrNull(json['accessTokenExpiresAt']),
      user: json['user'] == null
          ? null
          : PublicUser.fromJson(asRecord(json['user'])),
      expiresAt: json['expiresAt'] == null
          ? null
          : asInt(json['expiresAt']),
    );
  }

  final String accessToken;
  final String refreshToken;
  final String? accessTokenExpiresAt;
  final PublicUser? user;
  final int? expiresAt;

  /// Expiry in milliseconds, normalising second-precision timestamps.
  int? get expiryMs {
    final raw = accessTokenExpiresAt;
    if (raw != null && raw.isNotEmpty) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null && parsed.millisecondsSinceEpoch > 0) {
        return parsed.millisecondsSinceEpoch;
      }
      final numeric = int.tryParse(raw);
      if (numeric != null && numeric > 0) {
        return numeric < 10000000000 ? numeric * 1000 : numeric;
      }
    }
    if (expiresAt != null && expiresAt! > 0) {
      return expiresAt! < 10000000000 ? expiresAt! * 1000 : expiresAt!;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        if (accessTokenExpiresAt != null)
          'accessTokenExpiresAt': accessTokenExpiresAt,
        if (user != null) 'user': _userToJson(user!),
        if (expiresAt != null) 'expiresAt': expiresAt,
      };

  static Map<String, dynamic> _userToJson(PublicUser user) => {
        'id': user.id,
        if (user.email != null) 'email': user.email,
        if (user.username != null) 'username': user.username,
        if (user.displayName != null) 'displayName': user.displayName,
        if (user.avatarUrl != null) 'avatarUrl': user.avatarUrl,
        if (user.bio != null) 'bio': user.bio,
        'isPublic': user.isPublic,
        'showActivity': user.showActivity,
        'showHistory': user.showHistory,
        'showLikedTracks': user.showLikedTracks,
        'participateLeaderboards': user.participateLeaderboards,
      };
}

/// Extended profile with social counters.
class UserProfile {
  const UserProfile({
    required this.user,
    this.followersCount = 0,
    this.followingCount = 0,
    this.isFollowing = false,
    this.createdAt = '',
  });

  factory UserProfile.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const UserProfile(user: PublicUser(id: ''));
    return UserProfile(
      user: PublicUser.fromJson(json),
      followersCount: asInt(json['followersCount']),
      followingCount: asInt(json['followingCount']),
      isFollowing: asBool(json['isFollowing']),
      createdAt: asString(json['createdAt']),
    );
  }

  final PublicUser user;
  final int followersCount;
  final int followingCount;
  final bool isFollowing;
  final String createdAt;
}
