import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/auth.dart';

/// Persists and refreshes the auth session.
///
/// Mirrors `src/shared/api/auth-session.ts`: a single-flight refresh, a
/// proactive refresh when the access token expires within 120 s, and a
/// session wipe only when the refresh token itself is rejected.
class AuthSessionStore {
  AuthSessionStore({
    FlutterSecureStorage? secureStorage,
  })  : _storage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const String _storageKey = 'liner_auth_session';

  /// The key of the fallback storage.
  ///
  /// Some systems do not give the application a usable keyring: the Windows
  /// credential manager refuses the write when the application is started
  /// from a folder that the user does not own, and the Linux keyring stays
  /// locked. Without a fallback the session would be lost at every start.
  static const String _fallbackStorageKey = 'liner_auth_session_fallback';
  static const Duration _proactiveRefreshWindow = Duration(seconds: 120);

  /// The secure storage is backed by the OS keyring on Linux and by the
  /// keychain on macOS. Both can be locked or unavailable, in which case the
  /// platform channel never answers: the calls are bounded so the app never
  /// hangs on a locked keyring.
  static const Duration _storageTimeout = Duration(seconds: 5);

  final FlutterSecureStorage _storage;

  /// Performs the network call of a session refresh.
  ///
  /// It is assigned by the provider layer because the API client needs the
  /// store to read the token, while the store needs the API to refresh it.
  Future<AuthTokens> Function(String refreshToken)? refreshPerform;

  AuthTokens? _session;
  Future<AuthTokens?>? _refreshInFlight;
  final StreamController<AuthTokens?> _changes =
      StreamController<AuthTokens?>.broadcast();

  AuthTokens? get session => _session;

  Stream<AuthTokens?> get changes => _changes.stream;

  bool get isAuthenticated =>
      _session != null && _session!.accessToken.isNotEmpty;

  /// Loads a persisted session from disk, if any.
  Future<AuthTokens?> load() async {
    if (_session != null) return _session;

    var raw = await _readSecure();
    if (raw == null || raw.isEmpty) {
      // The keyring was empty or unusable: the fallback has the session.
      raw = await _readFallback();
    }
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      _session = AuthTokens.fromJson(Map<String, dynamic>.from(decoded));
      return _session;
    } catch (error) {
      debugPrint('[session] sessione illeggibile: $error');
      return null;
    }
  }

  /// Reads the session from the keyring.
  Future<String?> _readSecure() async {
    try {
      return await _storage
          .read(key: _storageKey)
          .timeout(_storageTimeout);
    } catch (error) {
      debugPrint('[session] keyring non utilizzabile: $error');
      return null;
    }
  }

  /// Reads the session from the fallback storage.
  Future<String?> _readFallback() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_fallbackStorageKey);
    } catch (error) {
      debugPrint('[session] storage di riserva non leggibile: $error');
      return null;
    }
  }

  Future<void> save(AuthTokens tokens) async {
    _session = tokens;
    final payload = jsonEncode(tokens.toJson());

    try {
      await _storage
          .write(key: _storageKey, value: payload)
          .timeout(_storageTimeout);
      return;
    } catch (error) {
      // The keyring is not always available: the session goes to the
      // fallback storage, so the user does not have to sign in again.
      debugPrint('[session] keyring non scrivibile, uso il riservo: $error');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_fallbackStorageKey, payload);
    } catch (error) {
      // Storage failures must never break the session in memory.
      debugPrint('[session] sessione non salvata: $error');
    }
    _changes.add(tokens);
  }

  Future<void> clear() async {
    _session = null;
    try {
      await _storage.delete(key: _storageKey).timeout(_storageTimeout);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_fallbackStorageKey);
    } catch (_) {}
    _changes.add(null);
  }

  /// Returns a valid access token, refreshing proactively when needed.
  Future<String?> validAccessToken() async {
    final refreshInFlight = _refreshInFlight;
    if (refreshInFlight != null) {
      final refreshed = await refreshInFlight;
      return refreshed?.accessToken ?? _session?.accessToken;
    }

    final current = _session;
    if (current == null || current.accessToken.isEmpty) return null;

    final expiryMs = current.expiryMs;
    if (expiryMs != null &&
        expiryMs - DateTime.now().millisecondsSinceEpoch <
            _proactiveRefreshWindow.inMilliseconds) {
      final refreshed = await refresh();
      if (refreshed?.accessToken.isNotEmpty == true) return refreshed!.accessToken;
      // Transient failure: keep using the current token while it is valid.
      if (expiryMs > DateTime.now().millisecondsSinceEpoch) {
        return current.accessToken;
      }
      return null;
    }

    return current.accessToken;
  }

  /// Performs a single-flight session refresh.
  ///
  /// The network call is delegated to [refreshPerform]. When it fails with a
  /// 401/403 the session is wiped; on a transient failure the session is kept.
  Future<AuthTokens?> refresh() {
    final existing = _refreshInFlight;
    if (existing != null) return existing;

    final current = _session;
    final perform = refreshPerform;
    if (current == null || current.refreshToken.isEmpty || perform == null) {
      return Future.value(null);
    }

    final future = _doRefresh(current, perform);
    _refreshInFlight = future;
    future.whenComplete(() => _refreshInFlight = null);
    return future;
  }

  Future<AuthTokens?> _doRefresh(
    AuthTokens current,
    Future<AuthTokens> Function(String refreshToken) perform,
  ) async {
    try {
      final refreshed = await perform(current.refreshToken);
      final merged = AuthTokens(
        accessToken: refreshed.accessToken,
        refreshToken: refreshed.refreshToken.isEmpty
            ? current.refreshToken
            : refreshed.refreshToken,
        accessTokenExpiresAt: refreshed.accessTokenExpiresAt,
        user: refreshed.user ?? current.user,
        expiresAt: refreshed.expiresAt,
      );
      await save(merged);
      return merged;
    } catch (err) {
      final status = _statusOf(err);
      if (status == 401 || status == 403) {
        await clear();
      }
      return null;
    }
  }

  static int _statusOf(Object err) {
    try {
      final dynamic e = err;
      final value = e.status;
      if (value is int) return value;
    } catch (_) {}
    return 0;
  }
  /// Convenience accessor for non-secure preferences.
  static Future<SharedPreferences> get prefs => SharedPreferences.getInstance();
}
