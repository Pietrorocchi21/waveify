import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:waveify/core/auth/auth_session_store.dart';
import 'package:waveify/core/cloud/supabase_api_client.dart';
import 'package:waveify/core/local/local_api_client.dart';
import 'package:waveify/core/local/local_library_store.dart';
import 'package:waveify/core/providers/app_providers.dart';
import 'package:waveify/features/auth/auth_controller.dart';

class MemorySession extends AuthSessionStore {
  @override
  Future<void> clear() async {}
}

void main() {
  test(
    'register after guest use and logout selects the cloud signup service',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'waveify-register-mode-',
      );
      final store = LocalLibraryStore(directory: directory);
      await store.update((data) {
        (data['tracks'] as Map)['device-track'] = {
          'id': 'device-track',
          'title': 'Keep my device library',
        };
      });
      final requests = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests.add('${request.method} ${request.uri.path}');
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect(body['email'], 'person@example.test');
        expect(request.uri.path, '/auth/v1/signup');
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'id': '11111111-1111-4111-8111-111111111111',
            'aud': 'authenticated',
            'role': 'authenticated',
            'email': 'person@example.test',
            'created_at': '2026-01-01T00:00:00Z',
            'app_metadata': {},
            'user_metadata': {'username': 'person', 'displayName': 'Person'},
          }),
        );
        await request.response.close();
      });
      final cloud = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'public-test-key',
        authOptions: const AuthClientOptions(
          authFlowType: AuthFlowType.implicit,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          localLibraryStoreProvider.overrideWithValue(store),
          supabaseClientProvider.overrideWithValue(cloud),
          sessionProvider.overrideWithValue(MemorySession()),
        ],
      );
      try {
        final auth = container.read(authControllerProvider.notifier);
        await auth.enterLocalMode();
        expect(container.read(apiClientProvider), isA<LocalApiClient>());
        await auth.logout();
        expect(container.read(useCloudAccountProvider), isFalse);
        final signedIn = await auth.register(
          email: 'person@example.test',
          password: 'test-password-123',
          username: 'person',
          displayName: 'Person',
        );
        expect(
          signedIn,
          isFalse,
          reason: 'Email confirmation must happen before an authenticated session exists.',
        );
        expect(requests, ['POST /auth/v1/signup']);
        expect(container.read(apiClientProvider), isA<SupabaseApiClient>());
        expect(
          container.read(authControllerProvider).errorCode,
          'EMAIL_CONFIRMATION_REQUIRED',
        );
        expect(
          await store.read(
            (data) => (data['tracks'] as Map).containsKey('device-track'),
          ),
          isTrue,
        );
      } finally {
        container.dispose();
        await cloud.dispose();
        await server.close(force: true);
        await directory.delete(recursive: true);
      }
    },
  );
}
