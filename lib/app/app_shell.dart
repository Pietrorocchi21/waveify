import 'playback_video_backdrop.dart';
import 'listening_room.dart';
import '../features/library/library_controller.dart';
import '../shared/widgets/waveify_brand.dart';

import 'package:flutter/services.dart';
import 'package:waveify/core/theme/artwork_palette.dart';
import 'package:waveify/features/player/player_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:waveify/core/platform/window_service.dart';
import 'package:waveify/core/providers/app_providers.dart';
import 'package:waveify/features/connectivity/connectivity_controller.dart';
import 'package:waveify/features/connectivity/connectivity_wall.dart';
import 'package:waveify/features/overlay/overlay_service.dart';
import 'package:waveify/features/customization/customization_controller.dart';
import 'package:waveify/features/player/ui/mini_player.dart';
import 'package:waveify/features/shortcuts/shortcut_scope.dart';
import 'package:waveify/features/settings/ui/update_notice.dart';
import 'package:waveify/shared/widgets/glass.dart';

/// The destinations of the main navigation.
class AppDestination {
  const AppDestination(this.route, this.icon, this.activeIcon, this.labelKey);

  final String route;
  final IconData icon;
  final IconData activeIcon;
  final String labelKey;
}

const List<AppDestination> appDestinations = [
  AppDestination(
    '/',
    Icons.home_outlined,
    Icons.home_rounded,
    'common.sidebar.home',
  ),
  AppDestination(
    '/search',
    Icons.search_outlined,
    Icons.search_rounded,
    'common.sidebar.search',
  ),
  AppDestination(
    '/library',
    Icons.library_music_outlined,
    Icons.library_music_rounded,
    'common.sidebar.library',
  ),
  AppDestination(
    '/downloads',
    Icons.download_for_offline_outlined,
    Icons.download_for_offline_rounded,
    'common.sidebar.downloads',
  ),
  AppDestination(
    '/remote',
    Icons.devices_other_outlined,
    Icons.devices_other_rounded,
    'common.sidebar.remote',
  ),
  AppDestination(
    '/settings',
    Icons.settings_outlined,
    Icons.settings_rounded,
    'common.sidebar.settings',
  ),
];

/// Shared frame reserves real layout space for the dock and safe areas.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(ambientAccentProvider);
    final t = ref.watch(translatorProvider);
    final path = GoRouterState.of(context).uri.path;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 900;
    final room = width >= 1120;
    final showQueue =
        room &&
        path == '/' &&
        ref.watch(playerControllerProvider.select((s) => s.queue.isNotEmpty));
    if (ref.watch(overlayServiceProvider).isOpen) {
      return AmbientBackground(
        accentColor: accent,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                ref.read(overlayServiceProvider.notifier).close(),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const WindowDragArea(
                      child: SizedBox(
                        width: 25,
                        height: 72,
                        child: Icon(Icons.drag_indicator_rounded, size: 19),
                      ),
                    ),
                    const Expanded(
                      child: Center(child: MiniPlayer(fullControls: true)),
                    ),
                    IconButton(
                      tooltip: t('player.open_player'),
                      icon: const Icon(Icons.open_in_full_rounded, size: 19),
                      onPressed: () =>
                          ref.read(overlayServiceProvider.notifier).close(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (ref.watch(connectivityControllerProvider).visible) {
      return const Scaffold(body: ConnectivityWall());
    }
    final main = Column(
      children: [
        if (wide || WindowService.instance.isDesktop)
          const SizedBox(
            height: 32,
            child: WindowDragArea(
              child: Align(
                alignment: Alignment.centerRight,
                child: WindowControls(),
              ),
            ),
          ),
        const UpdateNotice(),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 0, 12),
                  child: SizedBox(
                    width: room ? (width * .155).clamp(180.0, 230.0) : 64,
                    child: GlassPanel(
                      borderRadius: 24,
                      borderOpacity: .18,
                      padding: room
                          ? const EdgeInsets.symmetric(horizontal: 10)
                          : null,
                      child: _SideNavigation(path: path, expanded: room),
                    ),
                  ),
                ),
              Expanded(
                child: DecoratedBlock(
                  block: CustomizationBlock.contentView,
                  child: child,
                ),
              ),
              if (showQueue)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 12, 18, 12),
                  child: SizedBox(
                    width: (width * .212).clamp(235.0, 330.0),
                    child: const ListeningRoomQueue(),
                  ),
                ),
            ],
          ),
        ),
        if (room)
          Padding(
            padding: const EdgeInsets.fromLTRB(34, 2, 34, 18),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1500),
                child: const ListeningRoomDock(),
              ),
            ),
          )
        else
          const _MiniPlayerWrapper(),
      ],
    );
    return AmbientBackground(
      accentColor: accent,
      child: WallpaperBackground(
        fallback: Theme.of(context).brightness == Brightness.dark
            ? const _ListeningBackdrop()
            : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const PlaybackVideoBackdrop(),
            ShortcutScope(
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: SafeArea(bottom: false, child: main),
                bottomNavigationBar: wide
                    ? null
                    : GlassPanel(
                        borderRadius: 0,
                        blur: 16,
                        padding: EdgeInsets.zero,
                        child: SafeArea(
                          top: false,
                          child: NavigationBar(
                            height: 68,
                            selectedIndex: path == '/'
                                ? 0
                                : path.startsWith('/search')
                                ? 1
                                : path.startsWith('/library')
                                ? 2
                                : 3,
                            onDestinationSelected: (index) {
                              if (index < 3) {
                                context.go(appDestinations[index].route);
                                return;
                              }
                              showModalBottomSheet<void>(
                                context: context,
                                builder: (sheetContext) => GlassSheet(
                                  maxHeight: 280,
                                  padding: const EdgeInsets.all(16),
                                  child: ListView(
                                    children: [
                                      for (final destination
                                          in appDestinations.skip(3))
                                        ListTile(
                                          leading: Icon(destination.icon),
                                          title: Text(t(destination.labelKey)),
                                          onTap: () {
                                            Navigator.pop(sheetContext);
                                            context.go(destination.route);
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            destinations: [
                              for (final destination in appDestinations.take(3))
                                NavigationDestination(
                                  icon: Icon(destination.icon),
                                  selectedIcon: Icon(destination.activeIcon),
                                  label: t(destination.labelKey),
                                ),
                              NavigationDestination(
                                icon: const Icon(Icons.more_horiz_rounded),
                                label: MaterialLocalizations.of(context)
                                    .moreButtonTooltip,
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniPlayerWrapper extends ConsumerWidget {
  const _MiniPlayerWrapper();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(
      playerControllerProvider.select((s) => s.currentTrack),
    );
    if (track == null) return const SizedBox.shrink();
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        wide ? 24 : 10,
        8,
        wide ? 24 : 10,
        wide ? 20 : 8,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 940),
          child: DecoratedBlock(
            block: CustomizationBlock.miniplayer,
            child: GlassPlayerBar(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: MiniPlayer(onOpen: () => context.push('/player')),
            ),
          ),
        ),
      ),
    );
  }
}

class _SideNavigation extends ConsumerWidget {
  const _SideNavigation({required this.path, required this.expanded});
  final String path;
  final bool expanded;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);
    if (expanded) {
      final playlists = ref.watch(
        libraryControllerProvider.select((s) => s.playlists),
      );
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 18),
        children: [
          Center(
            child: TextButton(
              onPressed: () => context.go('/'),
              child: const WaveifyWordmark(stacked: true),
            ),
          ),
          const SizedBox(height: 24),
          for (final destination in appDestinations.take(3))
            _navigationTile(context, destination, t(destination.labelKey)),
          if (playlists.isNotEmpty) ...[
            const Divider(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                t('home.your_playlists'),
                style: theme.textTheme.labelLarge,
              ),
            ),
            for (final playlist in playlists)
              ListTile(
                dense: true,
                leading: const Icon(Icons.queue_music_rounded, size: 20),
                title: Text(
                  playlist.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => context.push(
                  Uri(
                    path: '/library/playlist',
                    queryParameters: {'id': playlist.id},
                  ).toString(),
                ),
              ),
          ],
          const Divider(height: 28),
          for (final destination in appDestinations.skip(3))
            _navigationTile(context, destination, t(destination.labelKey)),
          ListTile(
            dense: true,
            leading: const Icon(Icons.person_outline_rounded, size: 22),
            title: Text(t('profile.title')),
            onTap: () => context.push('/profile'),
          ),
        ],
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 32),
          child: IconButton(
            tooltip: 'Waveify',
            onPressed: () => context.go('/'),
            icon: const WaveifyMark(width: 34),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final destination in appDestinations)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: IconButton(
                      tooltip: t(destination.labelKey),
                      isSelected: destination.route == '/'
                          ? path == '/'
                          : path.startsWith(destination.route),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        backgroundColor:
                            (destination.route == '/'
                                ? path == '/'
                                : path.startsWith(destination.route))
                            ? theme.colorScheme.primary.withValues(alpha: 0.12)
                            : Colors.transparent,
                        foregroundColor: theme.colorScheme.onSurfaceVariant,
                      ),
                      selectedIcon: Icon(
                        destination.activeIcon,
                        color: theme.colorScheme.primary,
                      ),
                      icon: Icon(destination.icon, size: 22),
                      onPressed: () => context.go(destination.route),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: IconButton(
            tooltip: t('profile.title'),
            onPressed: () => context.push('/profile'),
            icon: const Icon(Icons.person_outline_rounded),
          ),
        ),
      ],
    );
  }

  Widget _navigationTile(
    BuildContext context,
    AppDestination destination,
    String label,
  ) {
    final selected = destination.route == '/'
        ? path == '/'
        : path.startsWith(destination.route);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        selected: selected,
        selectedTileColor: Theme.of(context).colorScheme.primary
            .withValues(alpha: .18),
        leading: Icon(
          selected ? destination.activeIcon : destination.icon,
          size: 22,
        ),
        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () => context.go(destination.route),
      ),
    );
  }
}

class _ListeningBackdrop extends StatelessWidget {
  const _ListeningBackdrop();

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(
        'assets/images/listening-room.webp',
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x66101529), Color(0xA6192036), Color(0x73101A2E)],
          ),
        ),
      ),
    ],
  );
}
