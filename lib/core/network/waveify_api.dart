import '../utils/json.dart';
import '../../models/auth.dart';
import '../../models/catalog.dart';
import '../../models/history.dart';
import '../../models/playlist.dart';
import '../../models/track.dart';
import 'api_client.dart';

/// Typed access to the Waveify backend.
class WaveifyApi {
  WaveifyApi(this.client);

  final ApiClient client;

  Future<AuthTokens> login(String email, String password) async {
    final data = await client.request(
      '/v1/auth/login',
      method: 'POST',
      body: {'email': email, 'password': password},
      allowRefresh: false,
      skipAuth: true,
    );
    return AuthTokens.fromJson(asRecord(data));
  }

  Future<AuthTokens> register({
    required String email,
    required String password,
    required String username,
    required String displayName,
  }) async {
    final data = await client.request(
      '/v1/auth/register',
      method: 'POST',
      body: {
        'email': email,
        'password': password,
        'username': username.trim().toLowerCase(),
        'displayName': displayName.trim(),
      },
      allowRefresh: false,
      skipAuth: true,
    );
    return AuthTokens.fromJson(asRecord(data));
  }

  Future<AuthTokens> refreshSession(String refreshToken) async {
    final data = await client.request(
      '/v1/auth/refresh',
      method: 'POST',
      body: {'refreshToken': refreshToken},
      allowRefresh: false,
      skipAuth: true,
    );
    return AuthTokens.fromJson(asRecord(data));
  }

  Future<void> logout(String accessToken, String refreshToken) async {
    await client.request(
      '/v1/auth/logout',
      method: 'POST',
      body: {'refreshToken': refreshToken},
      skipAuth: true,
    );
  }

  Future<PublicUser> getMe() async {
    final data = await client.request('/v1/me');
    return PublicUser.fromJson(asRecord(data));
  }

  Future<PublicUser> updateProfile(Map<String, dynamic> input) async {
    final data = await client.request(
      '/v1/users/me',
      method: 'PATCH',
      body: input,
    );
    return PublicUser.fromJson(asRecord(data));
  }

  Future<UserProfile> getUserProfile(String idOrUsername) async {
    final data = await client.request(
      '/v1/users/${Uri.encodeComponent(idOrUsername)}',
    );
    return UserProfile.fromJson(asRecord(data));
  }

  Future<List<UserProfile>> searchUsers(String query) async {
    final data = await client.request(
      '/v1/users/search',
      query: {'q': query},
    );
    return (asArray(data))
        .map((e) => UserProfile.fromJson(asRecord(e)))
        .toList(growable: false);
  }

  Future<void> followUser(String idOrUsername) async {
    await client.request(
      '/v1/users/${Uri.encodeComponent(idOrUsername)}/follow',
      method: 'POST',
    );
  }

  Future<void> unfollowUser(String idOrUsername) async {
    await client.request(
      '/v1/users/${Uri.encodeComponent(idOrUsername)}/follow',
      method: 'DELETE',
    );
  }

  Future<List<UserProfile>> getUserFollowers(String idOrUsername) async {
    final data = await client.request(
      '/v1/users/${Uri.encodeComponent(idOrUsername)}/followers',
    );
    return (asArray(data))
        .map((e) => UserProfile.fromJson(asRecord(e)))
        .toList(growable: false);
  }

  Future<List<UserProfile>> getUserFollowing(String idOrUsername) async {
    final data = await client.request(
      '/v1/users/${Uri.encodeComponent(idOrUsername)}/following',
    );
    return (asArray(data))
        .map((e) => UserProfile.fromJson(asRecord(e)))
        .toList(growable: false);
  }

  Future<List<UserProfile>> getUserPlaylists(String idOrUsername) async {
    final data = await client.request(
      '/v1/users/${Uri.encodeComponent(idOrUsername)}/playlists',
    );
    return (asRecord(data)?['items'] as List? ?? const [])
        .map((e) => UserProfile.fromJson(asRecord(e)))
        .toList(growable: false);
  }

  Future<List<SearchItem>> search(String query, {String type = 'all'}) async {
    final data = await client.request(
      '/v1/search',
      query: {'q': query, 'type': type},
    );
    return (asRecord(data)?['items'] as List? ?? const [])
        .map((e) => SearchItem.fromJson(asRecord(e)))
        .toList(growable: false);
  }

  Future<Track> getTrack(String id) async {
    final data = await client.request('/v1/tracks/${Uri.encodeComponent(id)}');
    return Track.fromJson(asRecord(data));
  }

  Future<RadioResponse> getRadio(
    String id, {
    List<String>? history,
    int? k,
    double? driftRate,
    double? temperature,
    String? waveId,
  }) async {
    final payload = <String, dynamic>{};
    if (history != null && history.isNotEmpty) {
      payload['history'] = history;
    }
    if (k != null) payload['k'] = k;
    if (driftRate != null) payload['drift_rate'] = driftRate;
    if (temperature != null) payload['temperature'] = temperature;
    if (waveId != null) payload['wave_id'] = waveId;

    final query = <String, dynamic>{};
    if (k != null) query['k'] = k;
    if (driftRate != null) query['drift_rate'] = driftRate;
    if (temperature != null) query['temperature'] = temperature;
    if (waveId != null) query['wave_id'] = waveId;

    final data = await client.request(
      '/v1/tracks/${Uri.encodeComponent(id)}/radio',
      method: (history != null && history.isNotEmpty) ? 'POST' : 'GET',
      body: (history != null && history.isNotEmpty) ? payload : null,
      query: (history != null && history.isNotEmpty) ? null : query,
    );
    return RadioResponse.fromJson(asRecord(data));
  }

  Future<AlbumDetails> getAlbum(String id) async {
    final data = await client.request('/v1/albums/${Uri.encodeComponent(id)}');
    return AlbumDetails.fromJson(asRecord(data));
  }

  Future<ArtistDetails> getArtist(String id) async {
    final data = await client.request('/v1/artists/${Uri.encodeComponent(id)}');
    return ArtistDetails.fromJson(asRecord(data));
  }

  Future<CatalogPlaylistDetails> getPlaylist(String id) async {
    final data =
        await client.request('/v1/playlists/${Uri.encodeComponent(id)}');
    return CatalogPlaylistDetails.fromJson(asRecord(data));
  }

  Future<LikedTracksPage> listLikedTracks({
    int limit = 100,
    String? cursor,
  }) async {
    final query = <String, dynamic>{'limit': '$limit'};
    if (cursor != null && cursor.isNotEmpty) query['cursor'] = cursor;
    final data = await client.request(
      '/v1/me/library/tracks',
      query: query,
    );
    return LikedTracksPage.fromJson(asRecord(data));
  }

  Future<void> likeTrack(String id, {Track? snapshot}) async {
    await client.request(
      '/v1/me/library/tracks/${Uri.encodeComponent(id)}',
      method: 'PUT',
      body: snapshot == null ? null : {'track': snapshot.toSnapshot()},
    );
  }

  Future<void> unlikeTrack(String id) async {
    await client.request(
      '/v1/me/library/tracks/${Uri.encodeComponent(id)}',
      method: 'DELETE',
    );
  }

  Future<List<SavedCollection>> listSavedCollections(String type) async {
    final data = await client.request('/v1/me/library/$type');
    return (asRecord(data)?['items'] as List? ?? const [])
        .map((e) => SavedCollection.fromJson(asRecord(e)))
        .toList(growable: false);
  }

  Future<void> saveCollection(String type, String id) async {
    await client.request(
      '/v1/me/library/$type/${Uri.encodeComponent(id)}',
      method: 'PUT',
    );
  }

  Future<void> removeCollection(String type, String id) async {
    await client.request(
      '/v1/me/library/$type/${Uri.encodeComponent(id)}',
      method: 'DELETE',
    );
  }

  Future<List<UserPlaylist>> listPlaylists() async {
    final data = await client.request('/v1/me/playlists');
    return (asRecord(data)?['items'] as List? ?? const [])
        .map((e) => UserPlaylist.fromJson(asRecord(e)))
        .toList(growable: false);
  }

  Future<(UserPlaylist, List<UserPlaylistItem>)> getUserPlaylist(
    String id,
  ) async {
    final data = await client.request('/v1/me/playlists/${Uri.encodeComponent(id)}');
    final map = asRecord(data);
    final playlist = UserPlaylist.fromJson(asRecord(map?['playlist']));
    final items = (map?['items'] as List? ?? const [])
        .map((e) => UserPlaylistItem.fromJson(asRecord(e)))
        .toList(growable: false);
    return (playlist, items);
  }

  Future<UserPlaylist> createPlaylist({
    required String title,
    String? description,
    bool isPublic = false,
  }) async {
    final data = await client.request(
      '/v1/me/playlists',
      method: 'POST',
      body: {
        'title': title,
        if (description != null && description.isNotEmpty)
          'description': description,
        'isPublic': isPublic,
      },
    );
    return UserPlaylist.fromJson(asRecord(data));
  }

  Future<UserPlaylist> updatePlaylist(
    String id, {
    String? title,
    String? description,
    bool? isPublic,
  }) async {
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    if (description != null) body['description'] = description;
    if (isPublic != null) body['isPublic'] = isPublic;

    final data = await client.request(
      '/v1/me/playlists/${Uri.encodeComponent(id)}',
      method: 'PATCH',
      body: body,
    );
    return UserPlaylist.fromJson(asRecord(data));
  }

  Future<void> deletePlaylist(String id) async {
    await client.request(
      '/v1/me/playlists/${Uri.encodeComponent(id)}',
      method: 'DELETE',
    );
  }

  Future<UserPlaylistItem> addPlaylistTrack(
    String playlistId,
    String trackId, {
    Track? snapshot,
  }) async {
    final data = await client.request(
      '/v1/me/playlists/${Uri.encodeComponent(playlistId)}/tracks/${Uri.encodeComponent(trackId)}',
      method: 'POST',
      body: snapshot == null ? null : {'track': snapshot.toSnapshot()},
    );
    return UserPlaylistItem.fromJson(asRecord(data));
  }

  Future<({int added, int rejected})> addPlaylistTracks(
    String playlistId,
    List<Track> tracks,
  ) async {
    final data = await client.request(
      '/v1/me/playlists/${Uri.encodeComponent(playlistId)}/tracks',
      method: 'POST',
      body: {
        'tracks': tracks.map((t) => t.toSnapshot()).toList(),
      },
      timeout: const Duration(seconds: 60),
    );
    final map = asRecord(data);
    return (
      added: asInt(map?['added']),
      rejected: asInt(map?['rejected']),
    );
  }

  Future<void> removePlaylistItem(String playlistId, String itemId) async {
    await client.request(
      '/v1/me/playlists/${Uri.encodeComponent(playlistId)}/items/${Uri.encodeComponent(itemId)}',
      method: 'DELETE',
    );
  }

  Future<(UserPlaylist, List<UserPlaylistItem>)> movePlaylistItem(
    String playlistId,
    String itemId,
    String? beforeItemId,
    int revision,
  ) async {
    final data = await client.request(
      '/v1/me/playlists/${Uri.encodeComponent(playlistId)}/items/${Uri.encodeComponent(itemId)}/move',
      method: 'POST',
      body: {'beforeItemId': beforeItemId, 'revision': revision},
    );
    final map = asRecord(data);
    return (
      UserPlaylist.fromJson(asRecord(map?['playlist'])),
      (map?['items'] as List? ?? const [])
          .map((e) => UserPlaylistItem.fromJson(asRecord(e)))
          .toList(growable: false),
    );
  }

  Future<void> recordPlaybackEvent(Map<String, dynamic> payload) async {
    await client.request(
      '/v1/me/playback/events',
      method: 'POST',
      body: payload,
    );
  }

  Future<PlaybackHistoryResponse> getHistory({
    String? cursor,
    int limit = 30,
  }) async {
    final query = <String, dynamic>{'limit': '$limit'};
    if (cursor != null && cursor.isNotEmpty) query['cursor'] = cursor;
    final data = await client.request(
      '/v1/me/history',
      query: query,
    );
    return PlaybackHistoryResponse.fromJson(asRecord(data));
  }

  Future<PlaybackHistoryResponse> getUserHistory(
    String idOrUsername, {
    String? cursor,
    int limit = 30,
  }) async {
    final query = <String, dynamic>{'limit': '$limit'};
    if (cursor != null && cursor.isNotEmpty) query['cursor'] = cursor;
    final data = await client.request(
      '/v1/users/${Uri.encodeComponent(idOrUsername)}/history',
      query: query,
    );
    return PlaybackHistoryResponse.fromJson(asRecord(data));
  }

  Future<PopularTracksResponse> getPopularTracks({
    String window = '7d',
    int limit = 50,
  }) async {
    final data = await client.request(
      '/v1/explore/popular',
      query: {'window': window, 'limit': '$limit'},
    );
    return PopularTracksResponse.fromJson(asRecord(data));
  }

  Future<DailyMixesResponse> getDailyMixes() async {
    final data = await client.request('/v1/me/recommendations/daily-mixes');
    return DailyMixesResponse.fromJson(asRecord(data));
  }

  Future<LeaderboardResponse> getArtistLeaderboard(
    String artistId, {
    String period = 'monthly',
    int limit = 10,
  }) async {
    final data = await client.request(
      '/v1/leaderboards/artist/${Uri.encodeComponent(artistId)}',
      query: {'period': period, 'limit': '$limit'},
    );
    return LeaderboardResponse.fromJson(asRecord(data));
  }

  Future<LeaderboardResponse> getGlobalLeaderboard({
    String period = 'weekly',
    int limit = 20,
  }) async {
    final data = await client.request(
      '/v1/leaderboards/global',
      query: {'period': period, 'limit': '$limit'},
    );
    return LeaderboardResponse.fromJson(asRecord(data));
  }
}
