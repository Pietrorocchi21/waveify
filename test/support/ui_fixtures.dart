import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:waveify/core/auth/auth_session_store.dart';
import 'package:waveify/core/media/innertube/innertube_catalog.dart';
import 'package:waveify/core/network/api_client.dart';
import 'package:waveify/core/network/waveify_api.dart';
import 'package:waveify/models/auth.dart';
import 'package:waveify/models/catalog.dart';
import 'package:waveify/models/history.dart';
import 'package:waveify/models/playlist.dart';
import 'package:waveify/models/track.dart';

/// Answers every request with an empty JSON object.
class FixtureAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        'date': [DateTime.now().toUtc().toString()],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A stand-in for the backend, so the widget test never touches the network.
class FixtureApi extends WaveifyApi {
  FixtureApi() : super(_buildClient());

  static const user = PublicUser(
    id: 'u1',
    email: 'test@example.com',
    username: 'tester',
    displayName: 'Tester',
  );

  static ApiClient _buildClient() {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
      ..httpClientAdapter = FixtureAdapter();
    return ApiClient(dio: dio);
  }

  @override
  Future<AuthTokens> login(String email, String password) async {
    return const AuthTokens(
      accessToken: 'token',
      refreshToken: 'refresh',
      user: user,
    );
  }

  @override
  Future<PublicUser> getMe() async => user;

  @override
  Future<PopularTracksResponse> getPopularTracks({
    String window = '7d',
    int limit = 50,
  }) async {
    return PopularTracksResponse(
      items: [
        for (var i = 0; i < fixtureTracks.length; i++)
          PopularTrackItem(rank: i + 1, track: fixtureTracks[i]),
      ],
    );
  }

  @override
  Future<DailyMixesResponse> getDailyMixes() async {
    return DailyMixesResponse(
      items: [
        for (var i = 0; i < fixtureTracks.length; i++)
          DailyMixItem(
            id: '$i',
            title: ['After hours', 'Blue room', 'Slow motion'][i],
            description: 'A quieter kind of listening',
            tracks: [fixtureTracks[i]],
          ),
      ],
    );
  }

  @override
  Future<PlaybackHistoryResponse> getHistory({
    String? cursor,
    int limit = 30,
  }) async {
    return PlaybackHistoryResponse(
      items: [
        for (final track in fixtureTracks)
          PlaybackHistoryItem(id: track.id, track: track),
      ],
    );
  }

  @override
  Future<List<UserPlaylist>> listPlaylists() async => const <UserPlaylist>[];

  @override
  Future<LikedTracksPage> listLikedTracks({
    int limit = 100,
    String? cursor,
  }) async {
    return const LikedTracksPage();
  }

  @override
  Future<List<SavedCollection>> listSavedCollections(String type) async =>
      const <SavedCollection>[];
}

/// A session store that keeps the session in memory, so the test never
/// touches the platform keyring.
class FixtureSessionStore extends AuthSessionStore {
  AuthTokens? _tokens;

  @override
  Future<AuthTokens?> load() async => _tokens;

  @override
  Future<void> save(AuthTokens tokens) async => _tokens = tokens;

  @override
  Future<void> clear() async => _tokens = null;
}

/// A catalog that answers with empty results.
class FixtureCatalog extends InnertubeCatalog {
  @override
  Future<List<SearchItem>> search(
    String query, {
    String type = 'all',
    CancelToken? cancelToken,
  }) async => const <SearchItem>[];

  @override
  Future<Track> getTrack(String id) async => Track(id: id, title: 'x');
}

const fixtureTracks = [
  Track(
    id: 't1',
    coverUrl: 'https://waveify.fixture/0.png',
    title: 'A moment between the waves',
    artists: 'Studio session · 2026',
    durationMs: 240000,
  ),
  Track(
    id: 't2',
    coverUrl: 'https://waveify.fixture/1.png',
    title: 'Blue room',
    artists: 'Evening sketches',
    durationMs: 184000,
  ),
  Track(
    id: 't3',
    coverUrl: 'https://waveify.fixture/2.png',
    title: 'Slow motion',
    artists: 'Late night recordings',
    durationMs: 212000,
  ),
];
