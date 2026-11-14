import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../models/auth.dart';
import '../../models/history.dart';
import '../../models/playlist.dart';

/// The state of a public profile.
class ProfileState {
  const ProfileState({
    this.profile,
    this.playlists = const [],
    this.isLoading = false,
    this.isFollowing = false,
    this.error,
  });

  final UserProfile? profile;
  final List<UserPlaylist> playlists;
  final bool isLoading;

  /// True when the current user already follows this profile.
  final bool isFollowing;
  final String? error;

  ProfileState copyWith({
    UserProfile? profile,
    List<UserPlaylist>? playlists,
    bool? isLoading,
    bool? isFollowing,
    String? error,
    bool clearError = false,
  }) {
    return ProfileState(
      profile: profile ?? this.profile,
      playlists: playlists ?? this.playlists,
      isLoading: isLoading ?? this.isLoading,
      isFollowing: isFollowing ?? this.isFollowing,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Loads a public profile and follows or unfollows it.
class ProfileController extends Notifier<ProfileState> {
  @override
  ProfileState build() => const ProfileState();

  /// Loads the profile of a user.
  Future<void> load(String idOrUsername) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final api = ref.read(apiProvider);
      final profile = await api.getUserProfile(idOrUsername);
      final playlists = await _loadPlaylists(api, idOrUsername);
      state = state.copyWith(
        profile: profile,
        playlists: playlists,
        isFollowing: profile.isFollowing,
        isLoading: false,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: '$error');
    }
  }

  Future<List<UserPlaylist>> _loadPlaylists(
    dynamic api,
    String idOrUsername,
  ) async {
    try {
      return await api.getUserPlaylists(idOrUsername);
    } catch (_) {
      // The public playlists are optional: the profile is still usable.
      return const [];
    }
  }

  /// Follows or unfollows the profile.
  Future<void> toggleFollow() async {
    final profile = state.profile;
    if (profile == null) return;

    final wasFollowing = state.isFollowing;
    // The state changes immediately: the request may be refused by a
    // deployment that does not expose the social endpoints.
    state = state.copyWith(isFollowing: !wasFollowing);

    try {
      final api = ref.read(apiProvider);
      if (wasFollowing) {
        await api.unfollowUser(profile.user.id);
      } else {
        await api.followUser(profile.user.id);
      }
    } catch (error) {
      state = state.copyWith(isFollowing: wasFollowing, error: '$error');
    }
  }
}

/// The profile controller provider.
final profileControllerProvider =
    NotifierProvider<ProfileController, ProfileState>(ProfileController.new);

/// The state of a leaderboard.
class LeaderboardState {
  const LeaderboardState({
    this.entries = const [],
    this.isLoading = false,
    this.error,
  });

  final List<LeaderboardEntry> entries;
  final bool isLoading;
  final String? error;

  LeaderboardState copyWith({
    List<LeaderboardEntry>? entries,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return LeaderboardState(
      entries: entries ?? this.entries,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Loads the leaderboards.
class LeaderboardController extends Notifier<LeaderboardState> {
  @override
  LeaderboardState build() => const LeaderboardState();

  /// The global leaderboard.
  Future<void> loadGlobal({String period = 'weekly'}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final response = await ref
          .read(apiProvider)
          .getGlobalLeaderboard(period: period);
      state = state.copyWith(
        entries: response.entries,
        isLoading: false,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: '$error');
    }
  }

  /// The leaderboard of an artist.
  Future<void> loadArtist(String artistId, {String period = 'monthly'}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final response = await ref
          .read(apiProvider)
          .getArtistLeaderboard(artistId, period: period);
      state = state.copyWith(
        entries: response.entries,
        isLoading: false,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: '$error');
    }
  }
}

/// The leaderboard controller provider.
final leaderboardControllerProvider =
    NotifierProvider<LeaderboardController, LeaderboardState>(
  LeaderboardController.new,
);
