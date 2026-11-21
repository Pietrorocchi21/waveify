import '../features/gallery/spatial_gallery_page.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/artist/ui/artist_page.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/ui/login_page.dart';
import '../features/collection/ui/collection_page.dart';
import '../features/downloads/downloads_page.dart';
import '../features/home/ui/home_page.dart';
import '../features/import/import_page.dart';
import '../features/library/ui/library_page.dart';
import '../features/library/ui/playlist_detail_page.dart';
import '../features/player/ui/fullscreen_player_page.dart';
import '../features/profile/leaderboard_page.dart';
import '../features/profile/profile_page.dart';
import '../features/remote/remote_page.dart';
import '../features/search/ui/search_page.dart';
import '../features/settings/ui/settings_page.dart';
import 'app_shell.dart';

/// The routes of the app.
class AppRoutes {
  AppRoutes._();

  static const home = '/';
  static const search = '/search';
  static const gallery = '/gallery';
  static const library = '/library';
  static const playlist = '/library/playlist';
  static const artist = '/artist';
  static const collection = '/collection';
  static const downloads = '/downloads';
  static const remote = '/remote';
  static const import = '/import';
  static const profile = '/profile';
  static const leaderboard = '/leaderboard';
  static const settings = '/settings';
  static const login = '/login';
  static const player = '/player';
}

/// The router of the app.
///
/// The authenticated pages live inside a shell (navigation + mini player);
/// the detail pages are pushed on top of it.
final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ValueNotifier<AuthState>(ref.read(authControllerProvider));
  ref.onDispose(notifier.dispose);

  ref.listen<AuthState>(authControllerProvider, (_, next) {
    notifier.value = next;
  });

  return GoRouter(
    initialLocation: AppRoutes.home,
    refreshListenable: notifier,
    redirect: (context, state) {
      final auth = notifier.value;
      final onLogin = state.matchedLocation == AppRoutes.login;
      if (!auth.isAuthenticated && !onLogin) return AppRoutes.login;
      if (auth.isAuthenticated && onLogin) return AppRoutes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginPage(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const _HomeRoute(),
          ),
          GoRoute(
            path: AppRoutes.search,
            builder: (context, state) =>
                SearchPage(initialQuery: state.uri.queryParameters['q'] ?? ''),
          ),
          GoRoute(
            path: AppRoutes.gallery,
            builder: (context, state) => SpatialGalleryPage(
              artistId: state.uri.queryParameters['artist'],
            ),
          ),
          GoRoute(
            path: AppRoutes.library,
            builder: (context, state) => const _LibraryRoute(),
          ),
          GoRoute(
            path: AppRoutes.downloads,
            builder: (context, state) => const _DownloadsRoute(),
          ),
          GoRoute(
            path: AppRoutes.remote,
            builder: (context, state) => const _RemoteRoute(),
          ),
          GoRoute(
            path: AppRoutes.import,
            builder: (context, state) => const _ImportRoute(),
          ),
          GoRoute(
            path: AppRoutes.player,
            builder: (context, state) => const _PlayerRoute(),
          ),
          GoRoute(
            path: AppRoutes.settings,
            builder: (context, state) => const _SettingsRoute(),
          ),
          GoRoute(
            path: AppRoutes.playlist,
            builder: (context, state) =>
                _PlaylistRoute(id: state.uri.queryParameters['id'] ?? ''),
          ),
          GoRoute(
            path: AppRoutes.artist,
            builder: (context, state) =>
                _ArtistRoute(id: state.uri.queryParameters['id'] ?? ''),
          ),
          GoRoute(
            path: AppRoutes.collection,
            builder: (context, state) =>
                _CollectionRoute(id: state.uri.queryParameters['id'] ?? ''),
          ),
          GoRoute(
            path: AppRoutes.profile,
            builder: (context, state) =>
                _ProfileRoute(userId: state.uri.queryParameters['id'] ?? ''),
          ),
          GoRoute(
            path: AppRoutes.leaderboard,
            builder: (context, state) => _LeaderboardRoute(
              artistId: state.uri.queryParameters['id'],
              artistName: state.uri.queryParameters['name'],
            ),
          ),
        ],
      ),
    ],
  );
});

class _HomeRoute extends StatelessWidget {
  const _HomeRoute();

  @override
  Widget build(BuildContext context) => const HomePage();
}

class _LibraryRoute extends StatelessWidget {
  const _LibraryRoute();

  @override
  Widget build(BuildContext context) => const LibraryPage();
}

class _DownloadsRoute extends StatelessWidget {
  const _DownloadsRoute();

  @override
  Widget build(BuildContext context) => const DownloadsPage();
}

class _RemoteRoute extends StatelessWidget {
  const _RemoteRoute();

  @override
  Widget build(BuildContext context) => const RemotePage();
}

class _ImportRoute extends StatelessWidget {
  const _ImportRoute();

  @override
  Widget build(BuildContext context) => const ImportPage();
}

class _SettingsRoute extends StatelessWidget {
  const _SettingsRoute();

  @override
  Widget build(BuildContext context) => const SettingsPage();
}

class _PlaylistRoute extends StatelessWidget {
  const _PlaylistRoute({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) => PlaylistDetailPage(playlistId: id);
}

class _ArtistRoute extends StatelessWidget {
  const _ArtistRoute({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) => ArtistPage(artistId: id);
}

class _CollectionRoute extends StatelessWidget {
  const _CollectionRoute({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) => CollectionPage(collectionId: id);
}

class _ProfileRoute extends StatelessWidget {
  const _ProfileRoute({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context) => ProfilePage(userId: userId);
}

class _LeaderboardRoute extends StatelessWidget {
  const _LeaderboardRoute({this.artistId, this.artistName});

  final String? artistId;
  final String? artistName;

  @override
  Widget build(BuildContext context) =>
      LeaderboardPage(artistId: artistId, artistName: artistName);
}

class _PlayerRoute extends StatelessWidget {
  const _PlayerRoute();

  @override
  Widget build(BuildContext context) =>
      const FullscreenPlayerPage(embedded: true);
}
