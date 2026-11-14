import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/storage/app_settings.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/glass.dart';
import '../../customization/customization_controller.dart';
import '../player_controller.dart';
import '../player_state.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key, this.onOpen});

  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);
    final (currentTrack, status) = ref.watch(
      playerControllerProvider.select((s) => (s.currentTrack, s.status)),
    );
    final controller = ref.read(playerControllerProvider.notifier);
    final track = currentTrack;

    if (track == null) {
      return const SizedBox.shrink();
    }

    final isPlaying = status == PlayerStatus.playing;
    final progress = ref.watch(
      playerControllerProvider.select((s) => s.progress),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Progress bar
        Container(
          height: 3,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(1.5),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: progress.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spaceMd, vertical: DesignTokens.spaceSm),
          child: Row(
            children: [
              // Cover art - larger and more prominent
              Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                child: InkWell(
                  onTap: onOpen,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
                  child: GlassCover(
                    url: track.coverUrl,
                    size: 56,
                    borderRadius: DesignTokens.radiusSm,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: DesignTokens.spaceMd),
              // Track info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artists,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              // Controls - using glass icon buttons
              GlassIconButton(
                icon: Icons.skip_previous_rounded,
                onPressed: controller.skipPrevious,
                tooltip: t('player.previous'),
                size: 36,
                iconSize: 20,
                variant: GlassButtonVariant.ghost,
              ),
              const SizedBox(width: DesignTokens.spaceXs),
              GlassIconButton(
                icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                onPressed: controller.togglePlayPause,
                tooltip: isPlaying ? t('common.pause') : t('common.play'),
                size: 44,
                iconSize: 22,
                variant: GlassButtonVariant.primary,
              ),
              const SizedBox(width: DesignTokens.spaceXs),
              GlassIconButton(
                icon: Icons.skip_next_rounded,
                onPressed: controller.skipNext,
                tooltip: t('player.next'),
                size: 36,
                iconSize: 20,
                variant: GlassButtonVariant.ghost,
              ),
              const SizedBox(width: DesignTokens.spaceXs),
              GlassIconButton(
                icon: Icons.queue_music_rounded,
                onPressed: () => showQueueSheet(context, ref),
                tooltip: t('player.queue'),
                size: 36,
                iconSize: 20,
                variant: GlassButtonVariant.ghost,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

void showQueueSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _QueueSheet(),
  );
}

class _QueueSheet extends ConsumerWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);
    final (queue, currentIndex) = ref.watch(
      playerControllerProvider.select((s) => (s.queue, s.currentIndex)),
    );
    final controller = ref.read(playerControllerProvider.notifier);

    return GlassSheet(
      padding: EdgeInsets.zero,
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      borderRadius: DesignTokens.radiusXxl,
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(DesignTokens.spaceXxl, 16, DesignTokens.spaceLg, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    t('player.queue'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                GlassButton(
                  onPressed: controller.clearQueue,
                  variant: GlassButtonVariant.ghost,
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.spaceMd,
                    vertical: DesignTokens.spaceSm,
                  ),
                  child: Text(t('player.clear_queue')),
                ),
              ],
            ),
          ),
          Expanded(
            child: queue.isEmpty
                ? EmptyState(
                    icon: Icons.queue_music_rounded,
                    title: t('player.queue_empty'),
                  )
                : ReorderableListView.builder(
                    itemCount: queue.length,
                    onReorder: (oldIndex, newIndex) {
                      final target = newIndex > oldIndex
                          ? newIndex - 1
                          : newIndex;
                      controller.reorderQueue(oldIndex, target);
                    },
                    proxyDecorator: (child, index, animation) => Material(
                      color: theme.colorScheme.surfaceContainerHighest,
                      elevation: 6,
                      borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                      child: child,
                    ),
                    itemBuilder: (context, index) {
                      final track = queue[index];
                      final isCurrent = index == currentIndex;
                      return GlassCard(
                        key: ValueKey('_'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: DesignTokens.spaceMd,
                          vertical: DesignTokens.spaceSm,
                        ),
                        selected: isCurrent,
                        accentColor: theme.colorScheme.primary,
                        onTap: () {
                          controller.playTrack(
                            track,
                            queue: queue,
                            index: index,
                            preserveQueue: true,
                          );
                        },
                        child: Row(
                          children: [
                            CoverImage(
                              url: track.coverUrl,
                              size: 40,
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
                                    style: TextStyle(
                                      color: isCurrent ? theme.colorScheme.primary : null,
                                      fontWeight: isCurrent
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    track.artists,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ReorderableDragStartListener(
                              index: index,
                              child: Icon(
                                Icons.drag_handle_rounded,
                                size: 20,
                                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
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

class RepeatButton extends ConsumerWidget {
  const RepeatButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);
    final repeat = ref.watch(playerControllerProvider.select((s) => s.repeat));
    final controller = ref.read(playerControllerProvider.notifier);

    final (icon, tooltip) = switch (repeat) {
      PlaybackRepeatMode.off => (Icons.repeat_rounded, t('player.repeat_off')),
      PlaybackRepeatMode.all => (Icons.repeat_on_rounded, t('player.repeat_all')),
      PlaybackRepeatMode.one => (Icons.repeat_one_on_rounded, t('player.repeat_one')),
    };

    return GlassIconButton(
      icon: icon,
      onPressed: () {
        final next = switch (repeat) {
          PlaybackRepeatMode.off => PlaybackRepeatMode.all,
          PlaybackRepeatMode.all => PlaybackRepeatMode.one,
          PlaybackRepeatMode.one => PlaybackRepeatMode.off,
        };
        controller.setRepeat(next);
      },
      tooltip: tooltip,
      size: 36,
      iconSize: 20,
      variant: repeat == PlaybackRepeatMode.off
          ? GlassButtonVariant.ghost
          : GlassButtonVariant.secondary,
    );
  }
}

class ShuffleButton extends ConsumerWidget {
  const ShuffleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);
    final shuffle = ref.watch(
      playerControllerProvider.select((s) => s.shuffle),
    );
    final controller = ref.read(playerControllerProvider.notifier);

    return GlassIconButton(
      icon: Icons.shuffle_rounded,
      onPressed: () => controller.setShuffle(!shuffle),
      tooltip: shuffle ? t('player.shuffle_on') : t('player.shuffle_off'),
      size: 36,
      iconSize: 20,
      variant: shuffle ? GlassButtonVariant.secondary : GlassButtonVariant.ghost,
    );
  }
}
