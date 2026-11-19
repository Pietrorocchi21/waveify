import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../models/track.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/track_widgets.dart';
import '../../player/player_controller.dart';

/// A catalog album or playlist, discriminated by its `type` field.
class CatalogCollection {
  const CatalogCollection({
    required this.type,
    required this.id,
    required this.title,
    this.subtitle = '',
    this.description,
    this.coverUrl = '',
    this.tracks = const [],
    this.durationMs = 0,
  });

  final String type;
  final String id;
  final String title;
  final String subtitle;
  final String? description;
  final String coverUrl;
  final List<Track> tracks;
  final int durationMs;
}

/// Loads a catalog album or playlist.
final catalogCollectionProvider =
    FutureProvider.family<CatalogCollection, String>((ref, id) async {
      final catalog = ref.read(catalogProvider);

      // The endpoint differs per collection type; try the album first and fall
      // back to the playlist endpoint.
      try {
        final album = await catalog.getAlbum(id);
        return CatalogCollection(
          type: 'album',
          id: album.id,
          title: album.title,
          subtitle: album.artists.map((a) => a.name).join(', '),
          coverUrl: album.cover?.url ?? '',
          tracks: album.tracks,
          durationMs: album.durationMs,
        );
      } catch (_) {
        final playlist = await catalog.getPlaylist(id);
        return CatalogCollection(
          type: 'playlist',
          id: playlist.id,
          title: playlist.title,
          subtitle: playlist.author ?? '',
          description: playlist.description,
          coverUrl: playlist.cover?.url ?? '',
          tracks: playlist.tracks,
          durationMs: playlist.durationMs,
        );
      }
    });

/// The detail view of a catalog album or playlist.
class CollectionPage extends ConsumerWidget {
  const CollectionPage({super.key, required this.collectionId});

  final String collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);
    final collection = ref.watch(catalogCollectionProvider(collectionId));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(collection.valueOrNull?.title ?? t('collection.playlist')),
      ),
      body: collection.when(
        loading: () => const LoadingState(),
        error: (err, _) => ErrorState(
          message: '$err',
          onRetry: () =>
              ref.invalidate(catalogCollectionProvider(collectionId)),
        ),
        data: (data) => ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CoverImage(url: data.coverUrl, size: 140, borderRadius: 12),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (data.subtitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            data.subtitle,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.textTertiary,
                            ),
                          ),
                        ],
                        if (data.description != null &&
                            data.description!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            data.description!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            FilledButton.icon(
                              onPressed: data.tracks.isEmpty
                                  ? null
                                  : () => ref
                                        .read(playerControllerProvider.notifier)
                                        .playTrack(
                                          data.tracks.first,
                                          queue: data.tracks,
                                          context: '${data.type}:${data.id}',
                                        ),
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                size: 18,
                              ),
                              label: Text(t('common.play_all')),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              onPressed: data.tracks.isEmpty
                                  ? null
                                  : () => ref
                                        .read(playerControllerProvider.notifier)
                                        .playShuffled(
                                          data.tracks,
                                          context: '${data.type}:${data.id}',
                                        ),
                              icon: const Icon(Icons.shuffle_rounded, size: 18),
                              label: Text(t('common.shuffle')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (data.tracks.isEmpty)
              EmptyState(
                icon: Icons.album_outlined,
                title: t('collection.not_found'),
              )
            else
              for (var i = 0; i < data.tracks.length; i++)
                TrackRow(
                  track: data.tracks[i],
                  queue: data.tracks,
                  context_: '${data.type}:${data.id}',
                  index: i,
                  showCover: false,
                ),
          ],
        ),
      ),
    );
  }
}
