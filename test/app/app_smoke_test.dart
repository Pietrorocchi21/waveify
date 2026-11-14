import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waveify/app.dart';
import 'package:waveify/core/auth/auth_session_store.dart';
import 'package:waveify/core/media/innertube/innertube_catalog.dart';
import 'package:waveify/core/network/api_client.dart';
import 'package:waveify/core/network/waveify_api.dart';
import 'package:waveify/core/providers/app_providers.dart';
import 'package:waveify/models/auth.dart';
import 'package:waveify/models/catalog.dart';
import 'package:waveify/models/history.dart';
import 'package:waveify/models/playlist.dart';
import 'package:waveify/models/track.dart';

/// Answers every request with an empty JSON object.
class _FakeAdapter implements HttpClientAdapter {
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
class _FakeApi extends WaveifyApi {
  _FakeApi() : super(_buildClient());

  static const user = PublicUser(
    id: 'u1',
    email: 'test@example.com',
    username: 'tester',
    displayName: 'Tester',
  );

  static ApiClient _buildClient() {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
      ..httpClientAdapter = _FakeAdapter();
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
    return const PopularTracksResponse();
  }

  @override
  Future<DailyMixesResponse> getDailyMixes() async {
    return const DailyMixesResponse();
  }

  @override
  Future<PlaybackHistoryResponse> getHistory({
    String? cursor,
    int limit = 30,
  }) async {
    return const PlaybackHistoryResponse();
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
class _FakeSessionStore extends AuthSessionStore {
  AuthTokens? _tokens;

  @override
  Future<AuthTokens?> load() async => _tokens;

  @override
  Future<void> save(AuthTokens tokens) async => _tokens = tokens;

  @override
  Future<void> clear() async => _tokens = null;
}

/// A catalog that answers with empty results.
class _FakeCatalog extends InnertubeCatalog {
  @override
  Future<List<SearchItem>> search(
    String query, {
    String type = 'all',
    CancelToken? cancelToken,
  }) async =>
      const <SearchItem>[];

  @override
  Future<Track> getTrack(String id) async => Track(id: id, title: 'x');
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'shows the login page and lands on the home after signing in',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        apiProvider.overrideWithValue(_FakeApi()),
        sessionProvider.overrideWithValue(_FakeSessionStore()),
        innertubeCatalogProvider.overrideWithValue(_FakeCatalog()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const WaveifyApp(),
      ),
    );
    // A bounded pump: the app keeps an animation running (the loading
    // spinner of the home page), so `pumpAndSettle` would never return.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The app starts on the login page.
    expect(find.text('Sign in'), findsWidgets);

    // Fill the form and sign in.
    await tester.enterText(
      find.byType(TextFormField).first,
      'test@example.com',
    );
    await tester.enterText(
      find.byType(TextFormField).last,
      'password123',
    );
    await tester.tap(find.text('Sign in').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // The router redirects to the home page.
    expect(find.textContaining('Good'), findsOneWidget);
  });
}
