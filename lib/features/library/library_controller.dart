import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../models/playlist.dart';
import '../../models/track.dart';
import '../auth/auth_controller.dart';

/// The user's library: liked tracks, saved collections and playlists.
class LibraryState {
  const LibraryState({
    this.likedTracks = const [],
    this.likedCursor,
    this.hasMoreLiked = true,
    this.savedAlbums = const [],
    this.savedArtists = const [],
    this.savedPlaylists = const [],
    this.playlists = const [],
    this.isLoadingLiked = false,
    this.isLoadingPlaylists = false,
    this.error,
  });

  final List<Track> likedTracks;
  final String? likedCursor;
  final bool hasMoreLiked;
  final List<SavedCollection> savedAlbums;
  final List<SavedCollection> savedArtists;
  final List<SavedCollection> savedPlaylists;
  final List<UserPlaylist> playlists;
  final bool isLoadingLiked;
  final bool isLoadingPlaylists;
  final String? error;

  LibraryState copyWith({
    List<Track>? likedTracks,
    String? likedCursor,
    bool clearLikedCursor = false,
    bool? hasMoreLiked,
    List<SavedCollection>? savedAlbums,
    List<SavedCollection>? savedArtists,
    List<SavedCollection>? savedPlaylists,
    List<UserPlaylist>? playlists,
    bool? isLoadingLiked,
    bool? isLoadingPlaylists,
    String? error,
    bool clearError = false,
  }) {
    return LibraryState(
      likedTracks: likedTracks ?? this.likedTracks,
      likedCursor: clearLikedCursor ? null : (likedCursor ?? this.likedCursor),
      hasMoreLiked: hasMoreLiked ?? this.hasMoreLiked,
      savedAlbums: savedAlbums ?? this.savedAlbums,
      savedArtists: savedArtists ?? this.savedArtists,
      savedPlaylists: savedPlaylists ?? this.savedPlaylists,
      playlists: playlists ?? this.playlists,
      isLoadingLiked: isLoadingLiked ?? this.isLoadingLiked,
      isLoadingPlaylists: isLoadingPlaylists ?? this.isLoadingPlaylists,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Loads and mutates the user's library.
class LibraryController extends Notifier<LibraryState> {
  int _generation = 0;

  @override
  LibraryState build() {
    final account = ref.watch(
      authControllerProvider.select(
        (auth) => auth.isAuthenticated ? auth.user?.id : null,
      ),
    );
    final generation = ++_generation;
    ref.onDispose(() => _generation++);
    if (account != null) {
      Future.microtask(() {
        if (generation != _generation) return;
        loadLikedTracks();
        loadPlaylists();
        loadSavedCollections();
      });
    }
    return const LibraryState();
  }

  /// Loads the first page of liked tracks.
  Future<void> loadLikedTracks({bool refresh = false}) async {
    final generation = _generation;
    if (state.isLoadingLiked) return;
    if (!refresh && state.likedTracks.isNotEmpty) return;

    state = state.copyWith(isLoadingLiked: true, clearError: true);
    try {
      final page = await ref.read(apiProvider).listLikedTracks(limit: 100);
      if (generation != _generation) return;
      state = state.copyWith(
        likedTracks: page.items.map((e) => e.$1).toList(growable: false),
        likedCursor: page.nextCursor,
        clearLikedCursor: page.nextCursor == null,
        hasMoreLiked: page.nextCursor != null,
        isLoadingLiked: false,
      );
    } catch (err) {
      if (generation != _generation) return;
      state = state.copyWith(isLoadingLiked: false, error: '$err');
    }
  }

  /// Loads the next page of liked tracks.
  Future<void> loadMoreLikedTracks() async {
    final generation = _generation;
    final cursor = state.likedCursor;
    if (cursor == null || state.isLoadingLiked) return;

    state = state.copyWith(isLoadingLiked: true);
    try {
      final page = await ref
          .read(apiProvider)
          .listLikedTracks(limit: 100, cursor: cursor);
      if (generation != _generation) return;
      state = state.copyWith(
        likedTracks: [...state.likedTracks, ...page.items.map((e) => e.$1)],
        likedCursor: page.nextCursor,
        clearLikedCursor: page.nextCursor == null,
        hasMoreLiked: page.nextCursor != null,
        isLoadingLiked: false,
      );
    } catch (err) {
      if (generation != _generation) return;
      state = state.copyWith(isLoadingLiked: false, error: '$err');
    }
  }

  /// Loads the saved collections of every type.
  Future<void> loadSavedCollections() async {
    final generation = _generation;
    final api = ref.read(apiProvider);
    try {
      final results = await Future.wait([
        api.listSavedCollections('albums'),
        api.listSavedCollections('artists'),
        api.listSavedCollections('playlists'),
      ]);
      if (generation != _generation) return;
      state = state.copyWith(
        savedAlbums: results[0],
        savedArtists: results[1],
        savedPlaylists: results[2],
        clearError: true,
      );
    } catch (err) {
      if (generation != _generation) return;
      state = state.copyWith(error: '$err');
    }
  }

  /// Loads the user's own playlists.
  Future<void> loadPlaylists({bool refresh = false}) async {
    final generation = _generation;
    if (state.isLoadingPlaylists) return;
    if (!refresh && state.playlists.isNotEmpty) return;

    state = state.copyWith(isLoadingPlaylists: true);
    try {
      final playlists = await ref.read(apiProvider).listPlaylists();
      if (generation != _generation) return;
      state = state.copyWith(playlists: playlists, isLoadingPlaylists: false);
    } catch (err) {
      if (generation != _generation) return;
      state = state.copyWith(isLoadingPlaylists: false, error: '$err');
    }
  }

  /// Likes a track, optimistically updating the library.
  Future<void> likeTrack(Track track) async {
    final wasLiked = state.likedTracks.any((t) => t.id == track.id);
    if (!wasLiked) {
      state = state.copyWith(likedTracks: [track, ...state.likedTracks]);
    }
    try {
      await ref.read(apiProvider).likeTrack(track.id, snapshot: track);
    } catch (err) {
      if (!wasLiked) {
        state = state.copyWith(
          likedTracks: state.likedTracks
              .where((t) => t.id != track.id)
              .toList(),
        );
      }
      state = state.copyWith(error: '$err');
    }
  }

  /// Removes the like from a track.
  Future<void> unlikeTrack(String trackId) async {
    final previous = state.likedTracks;
    state = state.copyWith(
      likedTracks: previous.where((t) => t.id != trackId).toList(),
    );
    try {
      await ref.read(apiProvider).unlikeTrack(trackId);
    } catch (err) {
      state = state.copyWith(likedTracks: previous, error: '$err');
    }
  }

  /// Toggles the like state of a track.
  Future<void> toggleLike(Track track) async {
    if (state.likedTracks.any((t) => t.id == track.id)) {
      await unlikeTrack(track.id);
    } else {
      await likeTrack(track);
    }
  }

  /// Saves a collection (album / artist / playlist) to the library.
  Future<void> saveCollection(String type, String id) async {
    try {
      await ref.read(apiProvider).saveCollection(type, id);
      await loadSavedCollections();
    } catch (err) {
      state = state.copyWith(error: '$err');
    }
  }

  /// Removes a collection from the library.
  Future<void> removeCollection(String type, String id) async {
    try {
      await ref.read(apiProvider).removeCollection(type, id);
      await loadSavedCollections();
    } catch (err) {
      state = state.copyWith(error: '$err');
    }
  }

  /// Creates a playlist.
  Future<UserPlaylist?> createPlaylist({
    required String title,
    String? description,
    bool isPublic = false,
  }) async {
    try {
      final playlist = await ref
          .read(apiProvider)
          .createPlaylist(
            title: title,
            description: description,
            isPublic: isPublic,
          );
      state = state.copyWith(playlists: [playlist, ...state.playlists]);
      return playlist;
    } catch (err) {
      state = state.copyWith(error: '$err');
      return null;
    }
  }

  /// Adds a track to one of the user's playlists.
  ///
  /// Returns true when the track was added.
  Future<bool> addTrackToPlaylist(String playlistId, Track track) async {
    try {
      await ref
          .read(apiProvider)
          .addPlaylistTrack(playlistId, track.id, snapshot: track);
      return true;
    } catch (err) {
      state = state.copyWith(error: '$err');
      return false;
    }
  }

  /// Adds several tracks to a playlist.
  ///
  /// The bulk endpoint is used, so the whole batch costs one request.
  /// Returns the number of tracks that were added.
  Future<int> addTracksToPlaylist(String playlistId, List<Track> tracks) async {
    if (tracks.isEmpty) return 0;
    try {
      final result = await ref
          .read(apiProvider)
          .addPlaylistTracks(playlistId, tracks);
      return result.added;
    } catch (err) {
      state = state.copyWith(error: '$err');
      return 0;
    }
  }

  /// Removes a track from one of the user's playlists.
  Future<bool> removeTrackFromPlaylist(String playlistId, String itemId) async {
    try {
      await ref.read(apiProvider).removePlaylistItem(playlistId, itemId);
      return true;
    } catch (err) {
      state = state.copyWith(error: '$err');
      return false;
    }
  }

  /// Renames a playlist.
  Future<bool> renamePlaylist(String playlistId, String title) async {
    final previous = state.playlists;
    state = state.copyWith(
      playlists: [
        for (final playlist in previous)
          if (playlist.id == playlistId)
            playlist.copyWith(title: title)
          else
            playlist,
      ],
    );
    try {
      await ref.read(apiProvider).updatePlaylist(playlistId, title: title);
      return true;
    } catch (err) {
      state = state.copyWith(playlists: previous, error: '$err');
      return false;
    }
  }

  /// Deletes a playlist.
  Future<void> deletePlaylist(String id) async {
    final previous = state.playlists;
    state = state.copyWith(
      playlists: previous.where((p) => p.id != id).toList(),
    );
    try {
      await ref.read(apiProvider).deletePlaylist(id);
    } catch (err) {
      state = state.copyWith(playlists: previous, error: '$err');
    }
  }
}

/// The library controller provider.
final libraryControllerProvider =
    NotifierProvider<LibraryController, LibraryState>(LibraryController.new);
