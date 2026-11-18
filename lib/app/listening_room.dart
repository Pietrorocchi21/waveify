import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers/app_providers.dart';
import '../features/library/library_controller.dart';
import '../features/player/player_controller.dart';
import '../features/player/player_state.dart';
import '../features/player/ui/mini_player.dart';
import '../shared/widgets/glass.dart';
import '../shared/widgets/track_widgets.dart';

class ListeningRoomQueue extends ConsumerWidget {
  const ListeningRoomQueue({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (queue, active) = ref.watch(
      playerControllerProvider.select((s) => (s.queue, s.currentIndex)),
    );
    if (queue.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);
    return GlassPanel(
      borderRadius: 24,
      borderOpacity: .18,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t('player.queue'),
                  style: theme.textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: t('player.queue'),
                onPressed: () => showQueueSheet(context, ref),
                icon: const Icon(Icons.queue_music_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: queue.length,
              itemBuilder: (context, index) {
                final track = queue[index];
                final selected = index == active;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    selected: selected,
                    selectedTileColor: theme.colorScheme.primary.withValues(
                      alpha: .15,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: GlassCover(
                      url: track.coverUrl,
                      size: 42,
                      borderRadius: 8,
                    ),
                    title: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      track.artists,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      track.durationMs > 0
                          ? formatDuration(track.durationMs)
                          : '—',
                      style: theme.textTheme.labelSmall,
                    ),
                    onTap: () => ref
                        .read(playerControllerProvider.notifier)
                        .playTrack(
                          track,
                          queue: queue,
                          index: index,
                          preserveQueue: true,
                        ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ListeningRoomDock extends ConsumerWidget {
  const ListeningRoomDock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerControllerProvider);
    final track = state.currentTrack;
    if (track == null) return const SizedBox.shrink();
    final t = ref.watch(translatorProvider);
    final theme = Theme.of(context);
    final transport = ref.read(playerControllerProvider.notifier);
    final liked = ref.watch(
      libraryControllerProvider.select(
        (s) => s.likedTracks.any((item) => item.id == track.id),
      ),
    );
    final playing = state.status == PlayerStatus.playing;
    final duration = state.duration.inMilliseconds;
    final position = state.position.inMilliseconds.clamp(
      0,
      duration > 0 ? duration : 0,
    );
    return GlassPanel(
      borderRadius: 52,
      borderOpacity: .26,
      opacity: .17,
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => context.push('/player'),
              child: Row(
                children: [
                  GlassCover(url: track.coverUrl, size: 58, borderRadius: 12),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          state.error ?? track.artists,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const ShuffleButton(),
                    IconButton(
                      tooltip: t('player.previous'),
                      icon: const Icon(Icons.skip_previous_rounded),
                      onPressed: transport.skipPrevious,
                    ),
                    if (state.isBusy)
                      const SizedBox.square(
                        dimension: 44,
                        child: Padding(
                          padding: EdgeInsets.all(11),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      IconButton.filledTonal(
                        tooltip: t(playing ? 'common.pause' : 'common.play'),
                        onPressed: transport.togglePlayPause,
                        icon: Icon(
                          playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                      ),
                    IconButton(
                      tooltip: t('player.next'),
                      icon: const Icon(Icons.skip_next_rounded),
                      onPressed: transport.skipNext,
                    ),
                    const RepeatButton(),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      formatDuration(position),
                      style: theme.textTheme.labelSmall,
                    ),
                    Expanded(
                      child: SizedBox(
                        height: 26,
                        child: Slider(
                          value: position.toDouble(),
                          max: duration > 0 ? duration.toDouble() : 1,
                          label: formatDuration(position),
                          onChanged: duration > 0
                              ? (value) => transport.seek(
                                  Duration(milliseconds: value.round()),
                                )
                              : null,
                        ),
                      ),
                    ),
                    Text(
                      formatDuration(duration),
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Row(
                children: [
                  IconButton(
                    tooltip: t(liked ? 'common.unlike' : 'common.like'),
                    isSelected: liked,
                    selectedIcon: const Icon(Icons.favorite_rounded),
                    icon: const Icon(Icons.favorite_border_rounded),
                    onPressed: () => ref
                        .read(libraryControllerProvider.notifier)
                        .toggleLike(track),
                  ),
                  const Icon(Icons.volume_up_outlined, size: 19),
                  Expanded(
                    child: Slider(
                      value: state.volume.clamp(0.0, 1.0),
                      label: '${(state.volume * 100).round()}%',
                      onChanged: transport.setVolume,
                    ),
                  ),
                  IconButton(
                    tooltip: t('player.queue'),
                    icon: const Icon(Icons.queue_music_rounded),
                    onPressed: () => showQueueSheet(context, ref),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
