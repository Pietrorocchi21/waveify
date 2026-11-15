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
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (ref.watch(connectivityControllerProvider).visible) {
      return const Scaffold(body: ConnectivityWall());
    }
    if (ref.watch(overlayServiceProvider).isOpen) {
      return AmbientBackground(
        accentColor: accent,
        child: ShortcutScope(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: WindowDragArea(
              child: MiniPlayer(
                onOpen: () => ref.read(overlayServiceProvider.notifier).close(),
              ),
            ),
          ),
        ),
      );
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
        Expanded(
          child: DecoratedBlock(
            block: CustomizationBlock.contentView,
            child: child,
          ),
        ),
        const _MiniPlayerWrapper(),
      ],
    );
    return AmbientBackground(
      accentColor: accent,
      child: WallpaperBackground(
        child: ShortcutScope(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  if (wide)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 0, 16),
                      child: DecoratedBlock(
                        block: CustomizationBlock.sidebar,
                        child: SizedBox(
                          width: 64,
                          child: _SideNavigation(path: path),
                        ),
                      ),
                    ),
                  Expanded(child: main),
                ],
              ),
            ),
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
  const _SideNavigation({required this.path});
  final String path;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 32),
          child: IconButton(
            tooltip: 'Waveify',
            onPressed: () => context.go('/'),
            icon: Icon(
              Icons.graphic_eq_rounded,
              color: theme.colorScheme.primary,
              size: 28,
            ),
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
}
