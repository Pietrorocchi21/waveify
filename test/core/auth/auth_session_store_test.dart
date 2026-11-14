import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waveify/core/auth/auth_session_store.dart';
import 'package:waveify/models/auth.dart';

/// A storage that never answers, like a locked OS keyring.
class _HangingStorage extends FlutterSecureStorage {
  _HangingStorage() : super();

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    return Completer<void>().future;
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    return Completer<String?>().future;
  }
}

void main() {
  group('AuthSessionStore', () {
    const tokens = AuthTokens(
      accessToken: 'access',
      refreshToken: 'refresh',
      user: PublicUser(id: 'u1', username: 'tester'),
    );

    test('saves the session even when the keyring does not answer', () async {
      // Regression: on Linux a locked keyring never answers, and the store
      // used to hang forever, which froze the login.
      final store = AuthSessionStore(secureStorage: _HangingStorage());

      await store.save(tokens).timeout(const Duration(seconds: 20));

      // The session is usable in memory even if it was not persisted.
      expect(store.session?.accessToken, 'access');
      expect(store.isAuthenticated, isTrue);
    });

    test('loads the session even when the keyring does not answer', () async {
      final store = AuthSessionStore(secureStorage: _HangingStorage());

      final loaded = await store.load().timeout(const Duration(seconds: 20));

      expect(loaded, isNull);
    });

    test('clears the session even when the keyring does not answer', () async {
      final store = AuthSessionStore(secureStorage: _HangingStorage());
      await store.save(tokens).timeout(const Duration(seconds: 20));

      await store.clear().timeout(const Duration(seconds: 20));

      expect(store.session, isNull);
      expect(store.isAuthenticated, isFalse);
    });

    test('emits the session changes', () async {
      final store = AuthSessionStore(secureStorage: _HangingStorage());
      final seen = <AuthTokens?>[];
      final subscription = store.changes.listen(seen.add);
      addTearDown(subscription.cancel);

      await store.save(tokens).timeout(const Duration(seconds: 20));
      await store.clear().timeout(const Duration(seconds: 20));
      await Future<void>.delayed(Duration.zero);

      expect(seen, hasLength(2));
      expect(seen.first?.accessToken, 'access');
      expect(seen.last, isNull);
    });

    test('reports the expiry of the access token', () {
      final withSeconds = AuthTokens(
        accessToken: 'a',
        refreshToken: 'r',
        accessTokenExpiresAt:
            DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
      );
      expect(withSeconds.expiryMs, isNotNull);
      expect(
        withSeconds.expiryMs! - DateTime.now().millisecondsSinceEpoch,
        greaterThan(3000 * 1000),
      );
    });
  });
}
