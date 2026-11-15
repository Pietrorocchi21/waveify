import '../../core/config/app_config.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/providers/app_providers.dart';
import '../../models/auth.dart';

/// Authentication state.
class AuthState {
  const AuthState({
    this.user,
    this.isAuthenticated = false,
    this.isLoading = false,
    this.error,
    this.errorCode,
  });

  final PublicUser? user;
  final bool isAuthenticated;
  final bool isLoading;
  final String? error;
  final String? errorCode;

  AuthState copyWith({
    PublicUser? user,
    bool? isAuthenticated,
    bool? isLoading,
    String? error,
    String? errorCode,
    bool clearError = false,
  }) {
    return AuthState(
      user: user ?? this.user,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      errorCode: clearError ? null : (errorCode ?? this.errorCode),
    );
  }
}

/// Drives login, registration, session restore and logout.
class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    return const AuthState();
  }

  /// Restores a persisted session and validates it against the backend.
  Future<void> initialize() async {
    if (!AppConfig.hasConfiguredAccount) {
      await enterLocalMode();
      return;
    }
    final session = ref.read(sessionProvider);
    final stored = await session.load();
    if (stored == null) {
      state = const AuthState();
      return;
    }

    state = state.copyWith(
      user: stored.user,
      isAuthenticated: true,
      isLoading: true,
    );

    try {
      final api = ref.read(apiProvider);
      final user = await api.getMe().timeout(const Duration(seconds: 6));
      final cloudSession = ref
          .read(supabaseClientProvider)
          ?.auth
          .currentSession;
      if (cloudSession != null) {
        await session.save(
          AuthTokens(
            accessToken: cloudSession.accessToken,
            refreshToken: cloudSession.refreshToken ?? stored.refreshToken,
            expiresAt: cloudSession.expiresAt,
            user: user,
          ),
        );
      }
      state = state.copyWith(
        user: user,
        isAuthenticated: true,
        isLoading: false,
        clearError: true,
      );
    } on ApiException catch (err) {
      if (err.isUnauthorized) {
        final refreshed = await session.refresh();
        if (refreshed == null) {
          await session.clear();
          state = const AuthState();
          return;
        }
        try {
          final user = await ref.read(apiProvider).getMe();
          state = state.copyWith(
            user: user,
            isAuthenticated: true,
            isLoading: false,
          );
          return;
        } catch (_) {
          state = state.copyWith(isLoading: false);
          return;
        }
      }
      // Network / server error: keep the optimistic session.
      state = state.copyWith(isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> enterLocalMode() async {
    ref.read(useCloudAccountProvider.notifier).state = false;
    final user = await ref.read(apiProvider).getMe();
    state = AuthState(user: user, isAuthenticated: true);
  }

  Future<bool> login(String email, String password) async {
    ref.read(useCloudAccountProvider.notifier).state = true;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final tokens = await ref.read(apiProvider).login(email, password);
      await ref.read(sessionProvider).save(tokens);
      state = AuthState(
        user: tokens.user,
        isAuthenticated: true,
        isLoading: false,
      );
      return true;
    } on ApiException catch (err) {
      state = state.copyWith(
        isLoading: false,
        error: err.message,
        errorCode: err.code,
      );
      return false;
    } catch (err) {
      state = state.copyWith(isLoading: false, error: '$err');
      return false;
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    required String username,
    required String displayName,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final tokens = await ref
          .read(apiProvider)
          .register(
            email: email,
            password: password,
            username: username,
            displayName: displayName,
          );
      await ref.read(sessionProvider).save(tokens);
      state = AuthState(
        user: tokens.user,
        isAuthenticated: true,
        isLoading: false,
      );
      return true;
    } on ApiException catch (err) {
      state = state.copyWith(
        isLoading: false,
        error: err.message,
        errorCode: err.code,
      );
      return false;
    } catch (err) {
      state = state.copyWith(isLoading: false, error: '$err');
      return false;
    }
  }

  Future<void> logout() async {
    final session = ref.read(sessionProvider);
    final current = session.session;
    if (current != null) {
      try {
        await ref
            .read(apiProvider)
            .logout(current.accessToken, current.refreshToken);
      } catch (_) {
        // Best effort: the local session is wiped either way.
      }
    }
    await session.clear();
    state = const AuthState();
  }
}

/// The auth controller provider.
final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
