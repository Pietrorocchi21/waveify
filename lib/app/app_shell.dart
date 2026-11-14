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
  const AppDestination(
    this.route,
    this.icon,
    this.activeIcon,
    this.labelKey,
  );

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

/// The application frame: navigation, content and the docked mini player.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translatorProvider);
    final isWide = MediaQuery.sizeOf(context).width >= 900;

    // The diagnostics wall replaces the app when the connection breaks.
    final connectivity = ref.watch(connectivityControllerProvider);
    if (connectivity.visible) {
      return const Scaffold(body: ConnectivityWall());
    }

    // In the overlay mode the window is the mini player: it floats above the
    // other applications.
    final overlay = ref.watch(overlayServiceProvider);
    if (overlay.isOpen) {
      return AmbientBackground(
        child: ShortcutScope(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: WindowDragArea(
              child: MiniPlayer(
                onOpen: () =>
                    ref.read(overlayServiceProvider.notifier).close(),
              ),
            ),
          ),
        ),
      );
    }

    final content = Column(
      children: [
        Expanded(child: child),
        const _MiniPlayerWrapper(),
      ],
    );

    final body = isWide
        ? Scaffold(
            backgroundColor: Colors.transparent,
            body: Row(
              children: [
                _GlassSidebarWrapper(child: const _SideNavigation()),
                const _GlassDivider(),
                Expanded(
                  child: GlassPanel(
                    borderRadius: 0,
                    borderOpacity: 0,
                    padding: EdgeInsets.zero,
                    opacity: 0,
                    blur: 0,
                    dim: 0,
                    shadows: [],
                    child: Column(
                      children: [
                        // The draggable bar of the frameless window.
                        WindowDragArea(
                          child: SizedBox(
                            height: 32,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: const WindowControls(),
                            ),
                          ),
                        ),
                        Expanded(child: content),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          )
        : Scaffold(
            backgroundColor: Colors.transparent,
            body: GlassPanel(
              borderRadius: 0,
              borderOpacity: 0,
              padding: EdgeInsets.zero,
              opacity: 0,
              blur: 0,
              dim: 0,
              shadows: [],
              child: content,
            ),
            bottomNavigationBar: _GlassBottomNav(
              selectedIndex: _selectedIndex(context),
              onDestinationSelected: (index) => _go(context, index),
              destinations: [
                for (final destination in appDestinations)
                  NavigationDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.activeIcon),
                    label: t(destination.labelKey),
                  ),
              ],
            ),
          );

    return AmbientBackground(child: ShortcutScope(child: body));
  }

  static int _selectedIndex(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final index = appDestinations.indexWhere((d) => d.route == path);
    return index < 0 ? 0 : index;
  }

  static void _go(BuildContext context, int index) {
    final destination = appDestinations[index];
    if (destination.route == '/') {
      context.go('/');
    } else {
      context.go(destination.route);
    }
  }
}

class _GlassSidebarWrapper extends StatelessWidget {
  const _GlassSidebarWrapper({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GlassSidebar(
      width: 220,
      child: Container(
        color: Colors.transparent,
        child: child,
      ),
    );
  }
}

class _GlassDivider extends StatelessWidget {
  const _GlassDivider();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 1,
      color: Colors.white.withValues(alpha: 0.06),
    );
  }
}

class _GlassBottomNav extends ConsumerWidget {
  const _GlassBottomNav({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return GlassPanel(
      borderRadius: 0,
      borderOpacity: 0,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      opacity: DesignTokens.glassOpacityStrong,
      blur: DesignTokens.glassBlurStrong,
      dim: DesignTokens.glassDimStrong,
      shadows: DesignTokens.shadowPlayer,
      child: SafeArea(
        top: false,
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: destinations,
          backgroundColor: Colors.transparent,
          indicatorColor: Colors.transparent,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          height: 64,
          elevation: 0,
        ),
      ),
    );
  }
}

class _MiniPlayerWrapper extends ConsumerWidget {
  const _MiniPlayerWrapper();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final (currentTrack, status) = ref.watch(
      playerControllerProvider.select((s) => (s.currentTrack, s.status)),
    );

    if (currentTrack == null) {
      return const SizedBox.shrink();
    }

    return GlassPlayerBar(
      accentColor: theme.colorScheme.primary,
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceXl,
        vertical: DesignTokens.spaceMd,
      ),
      child: MiniPlayer(onOpen: null),
    );
  }
}

class _SideNavigation extends ConsumerWidget {
  const _SideNavigation();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);
    final path = GoRouterState.of(context).uri.path;
    final selected = appDestinations.indexWhere((d) => d.route == path);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: NavigationRail(
        extended: true,
        minExtendedWidth: 190,
        selectedIndex: selected < 0 ? 0 : selected,
        onDestinationSelected: (index) {
          final destination = appDestinations[index];
          context.go(destination.route);
        },
        leading: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Icon(
            Icons.graphic_eq_rounded,
            color: theme.colorScheme.primary,
            size: 26,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        indicatorColor: theme.colorScheme.primary.withValues(alpha: 0.12),
        selectedIconTheme: IconThemeData(
          color: theme.colorScheme.primary,
          size: 24,
        ),
        unselectedIconTheme: IconThemeData(
          color: theme.colorScheme.onSurfaceVariant,
          size: 24,
        ),
        selectedLabelTextStyle: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        destinations: [
          for (final destination in appDestinations)
            NavigationRailDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.activeIcon),
              label: Text(t(destination.labelKey)),
            ),
        ],
      ),
    );
  }
}
