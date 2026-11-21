import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:waveify/core/cloud/supabase_api_client.dart';
import 'package:waveify/core/network/api_exception.dart';
import 'package:waveify/core/local/local_library_store.dart';

void main() {
  test(
    'cloud reads require authentication rather than returning local data',
    () async {
      final supabase = SupabaseClient(
        'https://example.invalid',
        'public-test-key',
      );
      final api = SupabaseApiClient(supabase);
      await expectLater(
        api.request('/v1/me/playlists'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
      );
      await supabase.dispose();
    },
  );

  test(
    'public playlist fallback is read-only and preserves sanitized metadata',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final methods = <String>[];
      server.listen((request) async {
        await request.drain<void>();
        methods.add('${request.method} ${request.uri.path}');
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/auth/v1/token') {
          request.response.write(
            jsonEncode({
              'access_token': 'fake-token',
              'refresh_token': 'fake-refresh',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': '11111111-1111-4111-8111-111111111111',
                'aud': 'authenticated',
                'created_at': '2026-01-01T00:00:00Z',
                'app_metadata': {},
                'user_metadata': {},
              },
            }),
          );
        } else if (request.uri.path == '/rest/v1/waveify_libraries') {
          request.response.write(
            jsonEncode({
              'revision': 1,
              'data': {
                ...LocalLibraryStore.empty(),
                'tracks': {
                  'private': {
                    'id': 'private',
                    'title': 'Uploaded',
                    'sourceUrl': 'storage://waveify_media/owner/audio.mp3',
                    'cover': {'url': 'storage://waveify_media/owner/cover.png'},
                    'coverUrl': 'storage://waveify_media/owner/cover.png',
                  },
                },
              },
            }),
          );
        } else if (request.uri.path == '/rest/v1/waveify_public_playlists') {
          request.response.write(
            jsonEncode({
              'data': {
                'playlist': {
                  'id': 'shared',
                  'ownerId': 'another-user',
                  'isPublic': true,
                },
                'items': [
                  {
                    'id': 'item',
                    'track': {'id': 'youtube-id', 'title': 'Shared track'},
                  },
                ],
              },
            }),
          );
        } else if (request.uri.path ==
            '/storage/v1/object/sign/waveify_media/owner/cover.png') {
          request.response.write(
            jsonEncode({
              'signedURL':
                  '/object/sign/waveify_media/owner/cover.png?token=fresh',
            }),
          );
        } else {
          request.response.statusCode = 500;
          request.response.write('{}');
        }
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'public-test-key',
        authOptions: const AuthClientOptions(
          authFlowType: AuthFlowType.implicit,
        ),
      );
      try {
        await client.auth.signInWithPassword(
          email: 'test@example.test',
          password: 'test-password',
        );
        final api = SupabaseApiClient(client);
        final track = await api.request('/v1/tracks/private') as Map;
        expect(track['sourceUrl'], 'storage://waveify_media/owner/audio.mp3');
        expect((track['cover'] as Map)['url'], contains('?token=fresh'));
        expect(track['coverUrl'], (track['cover'] as Map)['url']);
        expect(
          methods.where((request) => request.contains('/storage/v1/')).length,
          1,
        );
        final canonical = await api.store.read(
          (data) => (data['tracks'] as Map)['private'],
        ) as Map;
        expect(
          (canonical['cover'] as Map)['url'],
          'storage://waveify_media/owner/cover.png',
        );
        final shared = await api.request('/v1/me/playlists/shared') as Map;
        expect((shared['playlist'] as Map)['ownerId'], 'another-user');
        await expectLater(
          api.request('/v1/me/playlists/shared', method: 'DELETE'),
          throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)),
        );
        expect(
          methods
              .where((entry) => entry.contains('/rest/v1/'))
              .every((entry) => entry.startsWith('GET ')),
          isTrue,
        );
      } finally {
        await client.dispose();
        await server.close(force: true);
      }
    },
  );

  test('signup with no session requires email confirmation', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <String>[];
    server.listen((request) async {
      requests.add(request.uri.path);
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'id': '11111111-1111-4111-8111-111111111111',
          'aud': 'authenticated',
          'role': 'authenticated',
          'email': 'person@example.test',
          'created_at': '2026-01-01T00:00:00Z',
          'app_metadata': {},
          'user_metadata': {},
        }),
      );
      await request.response.close();
    });
    final supabase = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'public-test-key',
      authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
    );
    try {
      await expectLater(
        SupabaseApiClient(supabase).request(
          '/v1/auth/register',
          method: 'POST',
          body: {
            'email': 'person@example.test',
            'password': 'password123',
            'username': 'person',
            'displayName': 'Person',
          },
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'EMAIL_CONFIRMATION_REQUIRED',
          ),
        ),
      );
      expect(requests, ['/auth/v1/signup']);
      expect(supabase.auth.currentSession, isNull);
    } finally {
      await supabase.dispose();
      await server.close(force: true);
    }
  });
}
