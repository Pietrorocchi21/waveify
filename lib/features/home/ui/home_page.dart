import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_providers.dart';
import '../../../models/history.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/glass.dart';
import '../../../shared/widgets/artwork_stage.dart';
import '../../../shared/widgets/track_widgets.dart';
import '../../player/player_controller.dart';

final dailyMixesProvider = FutureProvider<DailyMixesResponse>(
  (ref) => ref.watch(apiProvider).getDailyMixes(),
);
final popularTracksProvider =
    FutureProvider.family<PopularTracksResponse, String>(
      (ref, window) => ref.watch(apiProvider).getPopularTracks(window: window),
    );
final recentlyPlayedProvider = FutureProvider<PlaybackHistoryResponse>(
  (ref) => ref.watch(apiProvider).getHistory(limit: 12),
);

/// The home contains real mixes/history only; empty feeds don't create shelves.
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
    final greeting = t(
      hour < 5
          ? 'home.goodNight'
          : hour < 12
          ? 'home.goodMorning'
          : hour < 18
          ? 'home.goodAfternoon'
          : 'home.goodEvening',
    );
    final mixes = ref.watch(dailyMixesProvider);
    final popular = ref.watch(popularTracksProvider(_window));
    final recent = ref.watch(recentlyPlayedProvider);
    final playback = ref.watch(
      playerControllerProvider.select(
        (s) => (s.currentTrack, s.queue, s.currentIndex),
      ),
    );
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final inset = wide ? 36.0 : 20.0;
    final controller = ref.read(playerControllerProvider.notifier);
    final tracks = playback.$2.isNotEmpty
        ? playback.$2
        : playback.$1 != null
        ? [playback.$1!]
        : popular.asData?.value.items.map((item) => item.track).toList() ?? [];
    final entries = tracks.isNotEmpty
        ? [
            for (final track in tracks)
              StageArtwork(
                id: track.id,
                title: track.title,
                subtitle: track.artists,
                coverUrl: track.coverUrl,
                actionLabel: t(
                  track.id == playback.$1?.id
                      ? 'player.open_player'
                      : 'common.play',
                ),
                onActivate: () {
                  if (track.id == playback.$1?.id) {
                    context.push('/player');
                  } else {
                    controller.playTrack(
                      track,
                      queue: tracks,
                      index: tracks.indexOf(track),
                      context: 'home:stage',
                    );
                  }
                },
              ),
          ]
        : [
            for (final mix in mixes.asData?.value.items ?? [])
              StageArtwork(
                id: mix.id,
                title: mix.title,
                subtitle: mix.description,
                coverUrl: mix.cover?.url ?? '',
                onActivate: mix.tracks.isEmpty
                    ? null
                    : () => controller.playTrack(
                        mix.tracks.first,
                        queue: mix.tracks,
                        context: 'mix:${mix.id}',
                        contextCover: mix.cover?.url,
                      ),
              ),
          ];
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(inset, 20, inset, 12),
            child: Row(
              children: [
                Text(
                  'waveify',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -1,
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    greeting,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverLayoutBuilder(
          builder: (context, constraints) => SliverToBoxAdapter(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.viewportMainAxisExtent - 76).clamp(
                  0,
                  double.infinity,
                ),
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: entries.isEmpty
                      ? mixes.isLoading || popular.isLoading
                            ? const LoadingState()
                            : EmptyState(
                                icon: Icons.music_note_outlined,
                                title: t('player.choose_track'),
                                action: TextButton.icon(
                                  onPressed: () => context.go('/search'),
                                  icon: const Icon(Icons.search_rounded),
                                  label: Text(t('common.sidebar.search')),
                                ),
                              )
                      : ArtworkStage(
                          key: ValueKey(
                            entries.map((entry) => entry.id).join('|'),
                          ),
                          items: entries,
                          initialIndex: playback.$3 < 0 ? 0 : playback.$3,
                          actionLabel: t('common.play'),
                        ),
                ),
              ),
            ),
          ),
        ),
        mixes.when(
          loading: () => const SliverToBoxAdapter(),
          error: (error, stack) => SliverToBoxAdapter(
            child: ErrorState(
              message: '',
              onRetry: () => ref.invalidate(dailyMixesProvider),
            ),
          ),
          data: (data) => data.items.isEmpty
              ? const SliverToBoxAdapter()
              : SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionTitle(
                        title: t('home.dailyMixes'),
                        subtitle: t('home.dailyMixesSubtitle'),
                      ),
                      SizedBox(
                        height: 220,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.symmetric(horizontal: inset),
                          itemCount: data.items.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: 20),
                          itemBuilder: (context, index) {
                            final mix = data.items[index];
                            return SizedBox(
                              width: 148,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: mix.tracks.isEmpty
                                    ? null
                                    : () => controller.playTrack(
                                        mix.tracks.first,
                                        queue: mix.tracks,
                                        context: 'mix:${mix.id}',
                                        contextCover: mix.cover?.url,
                                      ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    GlassCover(
                                      url: mix.cover?.url ?? '',
                                      size: 148,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      mix.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleSmall,
                                    ),
                                    Text(
                                      mix.description,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        SliverToBoxAdapter(
          child: _SectionTitle(
            title: t('home.whatEveryonesOn'),
            action: SegmentedButton<String>(
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: '24h', label: Text('24h')),
                ButtonSegment(value: '7d', label: Text('7d')),
                ButtonSegment(value: '30d', label: Text('30d')),
                ButtonSegment(value: 'all', label: Text('∞')),
              ],
              selected: {_window},
              onSelectionChanged: (values) =>
                  setState(() => _window = values.first),
            ),
          ),
        ),
        popular.when(
          loading: () => const SliverToBoxAdapter(child: LoadingState()),
          error: (error, stack) => SliverToBoxAdapter(
            child: ErrorState(
              message: '',
              onRetry: () => ref.invalidate(popularTracksProvider(_window)),
            ),
          ),
          data: (data) => data.items.isEmpty
              ? SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.music_note_outlined,
                    title: t('player.choose_track'),
                    action: TextButton.icon(
                      onPressed: () => context.go('/search'),
                      icon: const Icon(Icons.search_rounded),
                      label: Text(t('common.sidebar.search')),
                    ),
                  ),
                )
              : SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: inset),
                  sliver: SliverList.builder(
                    itemCount: data.items.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: TrackRow(
                        track: data.items[index].track,
                        queue: data.items.map((e) => e.track).toList(),
                        context_: 'explore:popular',
                        index: index,
                      ),
                    ),
                  ),
                ),
        ),
        recent.when(
          loading: () => const SliverToBoxAdapter(),
          error: (error, stack) => SliverToBoxAdapter(
            child: ErrorState(
              message: '',
              onRetry: () => ref.invalidate(recentlyPlayedProvider),
            ),
          ),
          data: (data) => data.items.isEmpty
              ? const SliverToBoxAdapter()
              : SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionTitle(title: t('home.jumpBackIn')),
                      SizedBox(
                        height: 210,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.symmetric(horizontal: inset),
                          itemCount: data.items.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: 16),
                          itemBuilder: (context, index) {
                            final track = data.items[index].track;
                            return SizedBox(
                              width: 144,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => ref
                                    .read(playerControllerProvider.notifier)
                                    .playTrack(
                                      track,
                                      context: 'library:recent',
                                    ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    GlassCover(url: track.coverUrl, size: 144),
                                    const SizedBox(height: 12),
                                    Text(
                                      track.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleSmall,
                                    ),
                                    Text(
                                      track.artists,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.subtitle, this.action});
  final String title;
  final String? subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 20,
      runSpacing: 12,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            if (subtitle != null)
              Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        ?action,
      ],
    ),
  );
}
