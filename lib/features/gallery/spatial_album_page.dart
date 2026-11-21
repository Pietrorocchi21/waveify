import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/track_widgets.dart';
import '../collection/ui/collection_page.dart';
import '../library/library_controller.dart';
import '../player/player_controller.dart';
import 'gallery_art.dart';
import 'gallery_catalog.dart';

final demoAlbumProvider = FutureProvider.autoDispose
    .family<CatalogCollection, GalleryAlbum>(
      (ref, album) => loadDemoAlbum(album),
    );

class SpatialAlbumPage extends ConsumerWidget {
  const SpatialAlbumPage({
    super.key,
    required this.album,
    required this.heroTag,
  });

  final GalleryAlbum album;
  final Object heroTag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = album.isDemo
        ? demoAlbumProvider(album)
        : catalogCollectionProvider(album.id);
    final detail = ref.watch(provider);
    return _body(
      context,
      ref,
      detail.valueOrNull,
      detail.error,
      () => ref.invalidate(provider),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    CatalogCollection? detail,
    Object? error,
    VoidCallback retry,
  ) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);
    final player = ref.read(playerControllerProvider.notifier);
    final state = ref.watch(
      playerControllerProvider.select(
        (s) => (s.playbackContext, s.isPlaying, s.currentTrack?.id),
      ),
    );
    final collectionContext =
        '${album.isDemo ? 'gallery-demo' : 'album'}:${album.id}';
    final isCurrent = state.$1 == collectionContext && state.$3 != null;
    final saved =
        !album.isDemo &&
        ref.watch(
          libraryControllerProvider.select(
            (s) => s.savedAlbums.any((item) => item.id == album.id),
          ),
        );
    final tracks = detail?.tracks ?? const [];
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF12121A) : const Color(0xFFF7F3FA);
    final size = (MediaQuery.sizeOf(context).width * .38).clamp(110.0, 265.0);
    final artist = detail?.subtitle.isNotEmpty == true
        ? detail!.subtitle
        : album.artist;
    final year = detail?.year ?? album.year;
    final metadata = [
      if (artist.isNotEmpty) artist,
      if (year != null) '$year',
    ].join(' · ');
    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: const BackButton(),
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            sliver: SliverToBoxAdapter(
              child: Wrap(
                spacing: 28,
                runSpacing: 18,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Hero(
                    tag: heroTag,
                    child: GalleryArt(
                      album: album,
                      size: size,
                      coverOverride: detail?.coverUrl.isNotEmpty == true
                          ? detail!.coverUrl
                          : null,
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 470),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          detail?.title ?? album.title,
                          style: theme.textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(metadata, style: theme.textTheme.titleMedium),
                        if (detail != null && detail.durationMs > 0)
                          Text(
                            formatDuration(detail.durationMs),
                            style: theme.textTheme.bodyMedium,
                          ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: tracks.isEmpty
                                  ? null
                                  : () {
                                      if (isCurrent) {
                                        player.togglePlayPause();
                                      } else {
                                        player.playTrack(
                                          tracks.first,
                                          queue: tracks,
                                          context: collectionContext,
                                        );
                                      }
                                    },
                              icon: Icon(
                                isCurrent && state.$2
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                              label: Text(
                                t(
                                  isCurrent && state.$2
                                      ? 'common.pause'
                                      : 'common.play',
                                ),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: tracks.isEmpty
                                  ? null
                                  : () => player.playShuffled(
                                      tracks,
                                      context: collectionContext,
                                    ),
                              icon: const Icon(Icons.shuffle_rounded),
                              label: Text(t('common.shuffle')),
                            ),
                            if (!album.isDemo)
                              IconButton.outlined(
                                icon: Icon(
                                  saved
                                      ? Icons.bookmark_rounded
                                      : Icons.bookmark_border_rounded,
                                ),
                                tooltip: t(
                                  saved
                                      ? 'common.remove_from_library'
                                      : 'common.add_to_library',
                                ),
                                onPressed: () {
                                  final library = ref.read(
                                    libraryControllerProvider.notifier,
                                  );
                                  if (saved) {
                                    library.removeCollection(
                                      'albums',
                                      album.id,
                                    );
                                  } else {
                                    library.saveCollection('albums', album.id);
                                  }
                                },
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (error != null)
            SliverToBoxAdapter(
              child: ErrorState(message: '$error', onRetry: retry),
            )
          else if (detail == null)
            const SliverToBoxAdapter(child: LoadingState())
          else if (tracks.isEmpty)
            SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.album_outlined,
                title: t('collection.not_found'),
              ),
            )
          else
            SliverList.builder(
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                if (!album.isDemo) {
                  return TrackRow(
                    track: track,
                    index: index,
                    showCover: false,
                    queue: tracks,
                    context_: collectionContext,
                  );
                }
                return ListTile(
                  selected: state.$3 == track.id,
                  leading: Icon(
                    state.$3 == track.id && state.$2
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  title: Text(track.title),
                  trailing: Text(formatDuration(track.durationMs)),
                  onTap: () => isCurrent
                      ? player.togglePlayPause()
                      : player.playTrack(track, context: collectionContext),
                );
              },
            ),
        ],
      ),
    );
  }
}
