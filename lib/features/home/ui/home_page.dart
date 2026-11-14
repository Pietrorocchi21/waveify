import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../models/history.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/glass.dart';
import '../../../shared/widgets/track_widgets.dart';
import '../../player/player_controller.dart';

/// The daily mixes, refreshed on demand.
final dailyMixesProvider = FutureProvider<DailyMixesResponse>((ref) async {
  return ref.watch(apiProvider).getDailyMixes();
});

/// The popular tracks for a given time window.
final popularTracksProvider =
    FutureProvider.family<PopularTracksResponse, String>((ref, window) async {
  return ref.watch(apiProvider).getPopularTracks(window: window);
});

/// The most recently played tracks.
final recentlyPlayedProvider =
    FutureProvider<PlaybackHistoryResponse>((ref) async {
  return ref.watch(apiProvider).getHistory(limit: 12);
});

/// The landing page: mixes, popular tracks and recent listening.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  String _window = '7d';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);
    final hour = DateTime.now().hour;
    final greeting = hour < 5
        ? t('home.goodNight')
        : hour < 12
            ? t('home.goodMorning')
            : hour < 18
                ? t('home.goodAfternoon')
                : t('home.goodEvening');

    final mixes = ref.watch(dailyMixesProvider);
    final popular = ref.watch(popularTracksProvider(_window));
    final recent = ref.watch(recentlyPlayedProvider);

    return AmbientBackground(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(DesignTokens.spaceXxl, DesignTokens.spaceXxxl, DesignTokens.spaceXxl, DesignTokens.spaceLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    greeting,
                    style: DesignTokens.textDisplaySmall.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spaceXs),
                  Text(
                    t('common.app.description'),
                    style: DesignTokens.textBodyMedium.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

          mixes.when(
            loading: () => const SliverToBoxAdapter(child: LoadingState()),
            error: (err, _) => SliverToBoxAdapter(
              child: ErrorState(
                message: '',
                onRetry: () => ref.invalidate(dailyMixesProvider),
              ),
            ),
            data: (data) {
              if (data.items.isEmpty) return const SliverToBoxAdapter();
              return SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _GlassSectionHeader(
                      title: t('home.dailyMixes'),
                      subtitle: t('home.dailyMixesSubtitle'),
                    ),
                    SizedBox(
                      height: 250,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spaceXl),
                        itemCount: data.items.length,
                        separatorBuilder: (_, _) => const SizedBox(width: DesignTokens.spaceLg),
                        itemBuilder: (context, index) {
                          final mix = data.items[index];
                          return _GlassMixCard(
                            title: mix.title,
                            subtitle: mix.description,
                            coverUrl: mix.cover?.url ?? '',
                            onTap: () => ref
                                .read(playerControllerProvider.notifier)
                                .playTrack(
                                  mix.tracks.first,
                                  queue: mix.tracks,
                                  context: 'mix:',
                                  contextCover: mix.cover?.url,
                                ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          SliverToBoxAdapter(
            child: _GlassSectionHeader(
              title: t('home.whatEveryonesOn'),
              action: _windowToggle(t),
            ),
          ),
          popular.when(
            loading: () => const SliverToBoxAdapter(child: LoadingState()),
            error: (err, _) => SliverToBoxAdapter(
              child: ErrorState(
                message: '',
                onRetry: () => ref.invalidate(popularTracksProvider(_window)),
              ),
            ),
            data: (data) {
              if (data.items.isEmpty) {
                return SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.local_fire_department_outlined,
                    title: t('home.whatEveryonesOn'),
                  ),
                );
              }
              return SliverList.builder(
                itemCount: data.items.length,
                itemBuilder: (context, index) {
                  final item = data.items[index];
                  return _GlassTrackRow(
                    track: item.track,
                    queue: data.items.map((e) => e.track).toList(),
                    context_: 'explore:popular',
                    index: index,
                  );
                },
              );
            },
          ),

          SliverToBoxAdapter(
            child: _GlassSectionHeader(title: t('home.jumpBackIn')),
          ),
          recent.when(
            loading: () => const SliverToBoxAdapter(child: LoadingState()),
            error: (err, _) => SliverToBoxAdapter(
              child: ErrorState(
                message: '',
                onRetry: () => ref.invalidate(recentlyPlayedProvider),
              ),
            ),
            data: (data) {
              if (data.items.isEmpty) return const SliverToBoxAdapter();
              return SliverToBoxAdapter(
                child: SizedBox(
                  height: 220,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spaceXl),
                    itemCount: data.items.length,
                    separatorBuilder: (_, _) => const SizedBox(width: DesignTokens.spaceMd),
                    itemBuilder: (context, index) {
                      final track = data.items[index].track;
                      return SizedBox(
                        width: 260,
                        child: _GlassCollectionCard(
                          onTap: () => ref
                              .read(playerControllerProvider.notifier)
                              .playTrack(track, context: 'library:recent'),
                          child: Row(
                            children: [
                              GlassCover(
                                url: track.coverUrl,
                                size: 56,
                                borderRadius: DesignTokens.radiusMd,
                                fit: BoxFit.cover,
                              ),
                              const SizedBox(width: DesignTokens.spaceMd),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      track.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: DesignTokens.textBodyMedium.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: DesignTokens.spaceXs),
                                    Text(
                                      track.artists,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: DesignTokens.textBodySmall.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: DesignTokens.spaceXxxl)),
        ],
      ),
    );
  }

  Widget _windowToggle(dynamic t) {
    return SegmentedButton<String>(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(
          Theme.of(context).textTheme.labelSmall,
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Theme.of(context).colorScheme.primary.withValues(alpha: 0.15);
          }
          return Colors.transparent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Theme.of(context).colorScheme.primary;
          }
          return Theme.of(context).colorScheme.onSurfaceVariant;
        }),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return BorderSide(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
            );
          }
          return BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          );
        }),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusMd)),
        ),
      ),
      segments: [
        ButtonSegment(value: '24h', label: const Text('24h')),
        ButtonSegment(value: '7d', label: const Text('7d')),
        ButtonSegment(value: '30d', label: const Text('30d')),
        ButtonSegment(value: 'all', label: const Text('All')),
      ],
      selected: {_window},
      onSelectionChanged: (value) => setState(() => _window = value.first),
    );
  }
}

class _GlassSectionHeader extends StatelessWidget {
  const _GlassSectionHeader({
    required this.title,
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(DesignTokens.spaceXxl, DesignTokens.spaceXxl, DesignTokens.spaceXxl, DesignTokens.spaceMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: DesignTokens.textHeadlineSmall.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: DesignTokens.spaceXxs),
                  Text(
                    subtitle!,
                    style: DesignTokens.textBodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class _GlassMixCard extends StatelessWidget {
  const _GlassMixCard({
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String coverUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 180,
      child: GlassCard(
        onTap: onTap,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlassCover(
              url: coverUrl,
              width: 180,
              height: 180,
              borderRadius: DesignTokens.radiusLg,
              fit: BoxFit.cover,
              showGlow: true,
              accentColor: theme.colorScheme.primary,
            ),
            Padding(
              padding: const EdgeInsets.all(DesignTokens.spaceMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesignTokens.textTitleMedium.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spaceXxs),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DesignTokens.textBodySmall.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassCollectionCard extends StatelessWidget {
  const _GlassCollectionCard({
    required this.child,
    required this.onTap,
  });

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(DesignTokens.spaceMd),
      child: child,
    );
  }
}

class _GlassTrackRow extends StatelessWidget {
  const _GlassTrackRow({
    required this.track,
    required this.queue,
    required this.context_,
    required this.index,
  });

  final Track track;
  final List<Track> queue;
  final String context_;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceMd,
        vertical: DesignTokens.spaceSm,
      ),
      onTap: () => ref
          .read(playerControllerProvider.notifier)
          .playTrack(
            track,
            queue: queue,
            context: context_,
            index: index,
          ),
      child: Row(
        children: [
          CoverImage(
            url: track.coverUrl,
            size: 44,
            borderRadius: DesignTokens.radiusSm,
          ),
          const SizedBox(width: DesignTokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesignTokens.textBodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: DesignTokens.spaceXxs),
                Text(
                  track.artists,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesignTokens.textBodySmall.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          GlassIconButton(
            icon: Icons.play_arrow_rounded,
            onPressed: () => ref
                .read(playerControllerProvider.notifier)
                .playTrack(
                  track,
                  queue: queue,
                  context: context_,
                  index: index,
                ),
            size: 36,
            iconSize: 20,
            variant: GlassButtonVariant.ghost,
          ),
        ],
      ),
    );
  }
}
