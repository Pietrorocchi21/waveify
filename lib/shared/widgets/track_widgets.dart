import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../features/downloads/downloads_controller.dart';
import '../../features/library/library_controller.dart';
import '../../features/player/player_controller.dart';
import '../../models/track.dart';
import 'common.dart';

/// Formats a duration in milliseconds as `m:ss` (or `h:mm:ss`).
String formatDuration(int milliseconds) {
  if (milliseconds <= 0) return '0:00';
  final total = milliseconds ~/ 1000;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// A row in a track list.
class TrackRow extends ConsumerWidget {
  const TrackRow({
    super.key,
    required this.track,
    this.queue,
    this.context_,
    this.index,
    this.showCover = true,
    this.dense = false,
    this.trailing,
    this.onTap,
  });

  final Track track;
  final List<Track>? queue;
  final String? context_;
  final int? index;
  final bool showCover;
  final bool dense;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);
    // Only the current track id is watched: the position ticks several
    // times per second and would rebuild every row of the list.
    final currentTrackId =
        ref.watch(playerControllerProvider.select((s) => s.currentTrack?.id));
    final isCurrent = currentTrackId == track.id;
    // The library is watched, not just read, so the like state updates as
    // soon as it changes.
    final library = ref.watch(libraryControllerProvider);
    final isLiked = library.likedTracks.any((t) => t.id == track.id);

    return InkWell(
      onTap: onTap ??
          () => ref.read(playerControllerProvider.notifier).playTrack(
                track,
                queue: queue ?? [track],
                context: context_,
              ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: dense ? 4 : 6,
        ),
        child: Row(
          children: [
            if (showCover)
              CoverImage(
                url: track.coverUrl,
                size: dense ? 36 : 44,
                borderRadius: 6,
              )
            else if (index != null)
              SizedBox(
                width: 32,
                child: Text(
                  '${index! + 1}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTertiary,
                  ),
                ),
              ),
            if (showCover && index != null) const SizedBox(width: 12),
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
                      fontWeight:
                          isCurrent ? FontWeight.w700 : FontWeight.w500,
                      color: isCurrent ? theme.colorScheme.primary : null,
                    ),
                  ),
                  if (track.artists.isNotEmpty)
                    Text(
                      track.artists,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
            if (!dense && track.durationMs > 0)
              Text(
                formatDuration(track.durationMs),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTertiary,
                ),
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: isLiked
                  ? t('library.remove_from_liked')
                  : t('library.add_to_liked'),
              onPressed: () => ref
                  .read(libraryControllerProvider.notifier)
                  .toggleLike(track),
              icon: Icon(
                isLiked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: 18,
                color: isLiked ? theme.colorScheme.primary : theme.textTertiary,
              ),
            ),
            ?trailing,
            TrackMenuButton(track: track),
          ],
        ),
      ),
    );
  }
}

/// The overflow menu for a track.
class TrackMenuButton extends ConsumerWidget {
  const TrackMenuButton({super.key, required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translatorProvider);
    final player = ref.read(playerControllerProvider.notifier);

    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert_rounded,
        size: 18,
        color: Theme.of(context).textTertiary,
      ),
      tooltip: t('common.more_options'),
      onSelected: (value) async {
        switch (value) {
          case 'queue':
            player.addToQueue(track);
          case 'next':
            player.playNext(track);
          case 'play':
            await player.playTrack(track);
          case 'radio':
            await player.startRadioStation(track);
          case 'playlist':
            if (context.mounted) {
              await showAddToPlaylistSheet(context, ref, track);
            }
          case 'download':
            await ref
                .read(downloadsControllerProvider.notifier)
                .download(track);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'play',
          child: Text(t('common.play_now')),
        ),
        PopupMenuItem(
          value: 'next',
          child: Text(t('common.play_next')),
        ),
        PopupMenuItem(
          value: 'queue',
          child: Text(t('common.add_to_queue')),
        ),
        PopupMenuItem(
          value: 'radio',
          child: Text(t('player.autoplay_radio')),
        ),
        PopupMenuItem(
          value: 'playlist',
          child: Text(t('common.add_to_playlist')),
        ),
        PopupMenuItem(
          value: 'download',
          child: Text(t('common.download_offline')),
        ),
      ],
    );
  }
}

/// Lets the user pick one of their playlists to add a track to.
Future<void> showAddToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final library = ref.read(libraryControllerProvider.notifier);
  await library.loadPlaylists();

  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _AddToPlaylistSheet(track: track),
  );
}

class _AddToPlaylistSheet extends ConsumerStatefulWidget {
  const _AddToPlaylistSheet({required this.track});

  final Track track;

  @override
  ConsumerState<_AddToPlaylistSheet> createState() =>
      _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends ConsumerState<_AddToPlaylistSheet> {
  final Set<String> _busy = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);
    final library = ref.watch(libraryControllerProvider);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.textTertiary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              t('common.add_to_playlist'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Flexible(
            child: library.playlists.isEmpty
                ? EmptyState(
                    icon: Icons.queue_music_rounded,
                    title: t('library.no_playlists_title'),
                    description: t('library.no_playlists_desc'),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: library.playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = library.playlists[index];
                      final busy = _busy.contains(playlist.id);
                      return ListTile(
                        leading: const Icon(Icons.queue_music_rounded),
                        title: Text(playlist.title),
                        trailing: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : null,
                        onTap: busy
                            ? null
                            : () async {
                                setState(() => _busy.add(playlist.id));
                                final added = await ref
                                    .read(libraryControllerProvider.notifier)
                                    .addTrackToPlaylist(playlist.id, widget.track);
                                if (!mounted) return;
                                setState(() => _busy.remove(playlist.id));
                                if (added && context.mounted) {
                                  showAppSnackBar(
                                    context,
                                    t('common.added_to_playlist'),
                                  );
                                }
                              },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// A horizontal card used for albums, playlists and mixes.
class CollectionCard extends ConsumerWidget {
  const CollectionCard({
    super.key,
    required this.title,
    required this.coverUrl,
    this.subtitle,
    this.onTap,
    this.width = 160,
  });

  final String title;
  final String coverUrl;
  final String? subtitle;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              CoverImage(
                url: coverUrl,
                width: width,
                height: width,
                borderRadius: 10,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTertiary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
