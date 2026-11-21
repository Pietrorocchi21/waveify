import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../models/playlist.dart';
import '../../../models/track.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/track_picker_sheet.dart';
import '../../../shared/widgets/track_widgets.dart';
import '../../player/player_controller.dart';
import '../library_controller.dart';

/// A playlist together with its items.
class PlaylistDetail {
  const PlaylistDetail(this.playlist, this.items);

  final UserPlaylist playlist;
  final List<UserPlaylistItem> items;
}

/// Loads one of the user's playlists.
final playlistDetailProvider = FutureProvider.family<PlaylistDetail, String>((
  ref,
  id,
) async {
  final (playlist, items) = await ref.read(apiProvider).getUserPlaylist(id);
  return PlaylistDetail(playlist, items);
});

/// The header of a playlist: title, description and the playback actions.
class _PlaylistHeader extends ConsumerWidget {
  const _PlaylistHeader({
    required this.data,
    required this.tracks,
    required this.onAddTracks,
  });

  final PlaylistDetail data;
  final List<Track> tracks;
  final VoidCallback onAddTracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.playlist.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (data.playlist.description != null &&
              data.playlist.description!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              data.playlist.description!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTertiary,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: tracks.isEmpty
                    ? null
                    : () => ref
                          .read(playerControllerProvider.notifier)
                          .playTrack(
                            tracks.first,
                            queue: tracks,
                            context: 'playlist:${data.playlist.id}',
                          ),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text(t('playlist.play_all')),
              ),
              OutlinedButton.icon(
                onPressed: tracks.isEmpty
                    ? null
                    : () => ref
                          .read(playerControllerProvider.notifier)
                          .playShuffled(
                            tracks,
                            context: 'playlist:${data.playlist.id}',
                          ),
                icon: const Icon(Icons.shuffle_rounded, size: 18),
                label: Text(t('common.shuffle')),
              ),
              OutlinedButton.icon(
                onPressed: onAddTracks,
                icon: const Icon(Icons.playlist_add_rounded, size: 18),
                label: Text(t('playlist.add_tracks')),
              ),
              Text(
                '${tracks.length} ${t('player.tracks')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The detail view of a user playlist.
class PlaylistDetailPage extends ConsumerWidget {
  const PlaylistDetailPage({super.key, required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);
    final detail = ref.watch(playlistDetailProvider(playlistId));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          detail.valueOrNull?.playlist.title ?? t('playlist.playlist'),
        ),
        actions: [
          if (detail.valueOrNull != null)
            PopupMenuButton<String>(
              onSelected: (value) async {
                switch (value) {
                  case 'rename':
                    await _rename(context, ref, detail.value!.playlist);
                  case 'delete':
                    await _delete(context, ref, detail.value!.playlist);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'rename', child: Text(t('common.rename'))),
                PopupMenuItem(value: 'delete', child: Text(t('common.delete'))),
              ],
            ),
        ],
      ),
      body: detail.when(
        loading: () => const LoadingState(),
        error: (err, _) => ErrorState(
          message: '$err',
          onRetry: () => ref.invalidate(playlistDetailProvider(playlistId)),
        ),
        data: (data) {
          final tracks = data.items.map((e) => e.track).toList(growable: false);
          return ReorderableListView.builder(
            padding: const EdgeInsets.only(bottom: 32),
            onReorderItem: (oldIndex, newIndex) =>
                _reorder(context, ref, data, oldIndex, newIndex),
            itemCount: tracks.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _PlaylistHeader(
                  data: data,
                  tracks: tracks,
                  onAddTracks: () => _addTracks(context, ref, data),
                );
              }
              final itemIndex = index - 1;
              final item = data.items[itemIndex];
              return ReorderableDelayedDragStartListener(
                key: ValueKey('item_${item.id}'),
                index: index,
                child: TrackRow(
                  track: item.track,
                  queue: tracks,
                  context_: 'playlist:${data.playlist.id}',
                  index: itemIndex,
                  showCover: false,
                  trailing: IconButton(
                    tooltip: t('common.remove_from_playlist'),
                    icon: Icon(
                      Icons.remove_circle_outline_rounded,
                      size: 18,
                      color: theme.textTertiary,
                    ),
                    onPressed: () => _removeItem(context, ref, data, item),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _addTracks(
    BuildContext context,
    WidgetRef ref,
    PlaylistDetail data,
  ) async {
    final picked = await showTrackPickerSheet(context);
    if (picked.isEmpty) return;

    final added = await ref
        .read(libraryControllerProvider.notifier)
        .addTrackToPlaylist(data.playlist.id, picked.first);

    if (!context.mounted) return;
    if (added) {
      ref.invalidate(playlistDetailProvider(playlistId));
      showAppSnackBar(context, 'common.added_to_playlist');
    }
  }

  /// Moves a track inside the playlist.
  ///
  /// The backend takes the id of the item that has to come *before* the moved
  /// one, together with the revision of the playlist.
  Future<void> _reorder(
    BuildContext context,
    WidgetRef ref,
    PlaylistDetail data,
    int oldIndex,
    int newIndex,
  ) async {
    final items = data.items;
    if (oldIndex <= 0 || oldIndex > items.length) return;
    // The first row of the list is the header.
    final from = oldIndex - 1;
    final to = newIndex - 1;
    if (to < 0 || to >= items.length || to == from) return;

    final moved = items[from];
    final remaining = [...items]..removeAt(from);
    final before = to < remaining.length ? remaining[to].id : null;

    try {
      await ref
          .read(apiProvider)
          .movePlaylistItem(
            data.playlist.id,
            moved.id,
            before,
            data.playlist.revision,
          );
      ref.invalidate(playlistDetailProvider(playlistId));
    } catch (err) {
      if (context.mounted) showAppSnackBar(context, '$err', isError: true);
    }
  }

  Future<void> _removeItem(
    BuildContext context,
    WidgetRef ref,
    PlaylistDetail data,
    UserPlaylistItem item,
  ) async {
    final removed = await ref
        .read(libraryControllerProvider.notifier)
        .removeTrackFromPlaylist(data.playlist.id, item.id);

    if (!context.mounted) return;
    if (removed) {
      ref.invalidate(playlistDetailProvider(playlistId));
      showAppSnackBar(context, 'common.removed_from_playlist');
    }
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    UserPlaylist playlist,
  ) async {
    final controller = TextEditingController(text: playlist.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('common.rename'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'common.playlist_name'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('common.cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('common.confirm'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (title == null || title.trim().isEmpty) return;
    final renamed = await ref
        .read(libraryControllerProvider.notifier)
        .renamePlaylist(playlist.id, title.trim());
    if (renamed && context.mounted) {
      ref.invalidate(playlistDetailProvider(playlistId));
      showAppSnackBar(context, 'common.renamed');
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    UserPlaylist playlist,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('common.delete'),
        content: Text('common.delete_playlist_desc'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('common.cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('common.delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref
        .read(libraryControllerProvider.notifier)
        .deletePlaylist(playlist.id);
    if (context.mounted) Navigator.of(context).pop();
  }
}
