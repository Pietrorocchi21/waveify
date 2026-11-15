import 'package:waveify/core/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/storage/app_settings.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/track_widgets.dart';
import '../../../shared/widgets/glass.dart';
import '../player_controller.dart';
import '../player_state.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key, this.onOpen, this.fullControls = false});

  final VoidCallback? onOpen;
  final bool fullControls;

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

    final state = ref.watch(playerControllerProvider);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final isPlaying = status == PlayerStatus.playing;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Tooltip(
              message: t('player.playing_from'),
              child: InkWell(
                onTap: onOpen,
                borderRadius: BorderRadius.circular(12),
                child: GlassCover(
                  url: track.coverUrl,
                  size: wide ? 48 : 44,
                  borderRadius: 12,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextButton(
                onPressed: onOpen,
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: EdgeInsets.zero,
                  foregroundColor: theme.colorScheme.onSurface,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      state.error != null ? state.error! : track.artists,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            if (wide) const ShuffleButton(),
            if (wide || fullControls) ...[
              GlassIconButton(
                icon: Icons.skip_previous_rounded,
                onPressed: controller.skipPrevious,
                tooltip: t('player.previous'),
              ),
            ],
            if (state.isBusy)
              const SizedBox(
                width: 48,
                height: 48,
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              GlassIconButton(
                icon: isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                onPressed: controller.togglePlayPause,
                tooltip: isPlaying ? t('common.pause') : t('common.play'),
                variant: GlassButtonVariant.primary,
                iconSize: 28,
              ),
            GlassIconButton(
              icon: Icons.skip_next_rounded,
              onPressed: controller.skipNext,
              tooltip: t('player.next'),
            ),
            if (wide) ...[
              const RepeatButton(),
              const SizedBox(width: 12),
              const Icon(Icons.volume_up_outlined, size: 18),
              SizedBox(
                width: 96,
                child: Slider(
                  value: state.volume.clamp(0, 1),
                  label: '${(state.volume * 100).round()}%',
                  onChanged: controller.setVolume,
                ),
              ),
            ],
            if (wide || MediaQuery.sizeOf(context).width >= 380)
              GlassIconButton(
                icon: Icons.queue_music_rounded,
                onPressed: () => showQueueSheet(context, ref),
                tooltip: t('player.queue'),
              ),
          ],
        ),
        SizedBox(
          height: 18,
          child: Row(
            children: [
              if (wide)
                Text(
                  formatDuration(state.position.inMilliseconds),
                  style: theme.textTheme.labelSmall,
                ),
              Expanded(
                child: Slider(
                  value: state.progress,
                  label: formatDuration(state.position.inMilliseconds),
                  onChanged: state.duration > Duration.zero
                      ? (value) => controller.seek(
                          Duration(
                            milliseconds:
                                (state.duration.inMilliseconds * value).round(),
                          ),
                        )
                      : null,
                ),
              ),
              if (wide)
                Text(
                  formatDuration(state.duration.inMilliseconds),
                  style: theme.textTheme.labelSmall,
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
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.spaceXxl,
              16,
              DesignTokens.spaceLg,
              8,
            ),
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
                    onReorderItem: controller.reorderQueue,
                    proxyDecorator: (child, index, animation) => Material(
                      color: theme.colorScheme.surfaceContainerHighest,
                      elevation: 6,
                      borderRadius: BorderRadius.circular(
                        DesignTokens.radiusMd,
                      ),
                      child: child,
                    ),
                    itemBuilder: (context, index) {
                      final track = queue[index];
                      final isCurrent = index == currentIndex;
                      return GlassCard(
                        key: ValueKey('${track.id}-$index'),
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
                                      color: isCurrent
                                          ? theme.colorScheme.primary
                                          : null,
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
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.5),
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
    final t = ref.watch(translatorProvider);
    final repeat = ref.watch(playerControllerProvider.select((s) => s.repeat));
    final controller = ref.read(playerControllerProvider.notifier);

    final (icon, tooltip) = switch (repeat) {
      PlaybackRepeatMode.off => (Icons.repeat_rounded, t('player.repeat_off')),
      PlaybackRepeatMode.all => (
        Icons.repeat_on_rounded,
        t('player.repeat_all'),
      ),
      PlaybackRepeatMode.one => (
        Icons.repeat_one_on_rounded,
        t('player.repeat_one'),
      ),
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
      variant: shuffle
          ? GlassButtonVariant.secondary
          : GlassButtonVariant.ghost,
    );
  }
}
