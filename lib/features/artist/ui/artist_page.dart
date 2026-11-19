import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_providers.dart';
import '../../../models/catalog.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/artwork_stage.dart';
import '../../../shared/widgets/track_widgets.dart';
import '../../player/player_controller.dart';

/// Loads an artist page.
final artistProvider = FutureProvider.family<ArtistDetails, String>((
  ref,
  id,
) async {
  return ref.read(catalogProvider).getArtist(id);
});

/// The artist page: biography, top tracks, albums and singles.
class ArtistPage extends ConsumerWidget {
  const ArtistPage({super.key, required this.artistId});

  final String artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);
    final artist = ref.watch(artistProvider(artistId));

    return Scaffold(
      appBar: AppBar(
        title: Text(artist.valueOrNull?.name ?? t('artist.tracks')),
      ),
      body: artist.when(
        loading: () => const LoadingState(),
        error: (err, _) => ErrorState(
          message: '$err',
          onRetry: () => ref.invalidate(artistProvider(artistId)),
        ),
        data: (data) => ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CoverImage(
                    url: data.cover?.url ?? '',
                    size: 120,
                    borderRadius: 12,
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              data.name,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (data.verified) ...[
                              const SizedBox(width: 6),
                              Icon(
                                Icons.verified_rounded,
                                size: 18,
                                color: theme.colorScheme.primary,
                              ),
                            ],
                          ],
                        ),
                        if (data.monthlyListeners != null &&
                            data.monthlyListeners!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            data.monthlyListeners!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.textTertiary,
                            ),
                          ),
                        ],
                        if (data.bio != null && data.bio!.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            data.bio!,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: data.tracks.isEmpty
                                  ? null
                                  : () => ref
                                        .read(playerControllerProvider.notifier)
                                        .playTrack(
                                          data.tracks.first,
                                          queue: data.tracks,
                                          context: 'artist:${data.id}',
                                        ),
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                size: 18,
                              ),
                              label: Text(t('artist.play')),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => context.push(
                                '/leaderboard'
                                '?id=${Uri.encodeQueryComponent(data.id)}'
                                '&name=${Uri.encodeQueryComponent(data.name)}',
                              ),
                              icon: const Icon(
                                Icons.emoji_events_outlined,
                                size: 18,
                              ),
                              label: Text(t('leaderboard.title')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (data.tracks.isNotEmpty) ...[
              SectionHeader(title: t('artist.popular_songs')),
              for (var i = 0; i < data.tracks.length; i++)
                TrackRow(
                  track: data.tracks[i],
                  queue: data.tracks,
                  context_: 'artist:${data.id}',
                  index: i,
                  showCover: false,
                ),
            ],
            if (data.albums.isNotEmpty) ...[
              SectionHeader(title: t('artist.albums')),
              ArtworkStage(
                key: ValueKey(data.id),
                captionOnArtwork: true,
                actionLabel: t('artist.open_album'),
                actionIcon: Icons.album_outlined,
                items: [
                  for (final release in data.albums)
                    StageArtwork(
                      id: release.id,
                      title: release.title,
                      subtitle: release.year?.toString() ?? '',
                      coverUrl: release.cover?.url ?? '',
                      onActivate: () => context.push(
                        Uri(
                          path: '/collection',
                          queryParameters: {'type': 'album', 'id': release.id},
                        ).toString(),
                      ),
                    ),
                ],
              ),
            ],
            if (data.singles.isNotEmpty) ...[
              SectionHeader(title: t('artist.singles')),
              _ReleaseRow(releases: data.singles, artistId: data.id),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReleaseRow extends StatelessWidget {
  const _ReleaseRow({required this.releases, required this.artistId});

  final List<ArtistAlbum> releases;
  final String artistId;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 232,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: releases.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (context, index) {
          final release = releases[index];
          return CollectionCard(
            title: release.title,
            subtitle: release.year?.toString() ?? '',
            coverUrl: release.cover?.url ?? '',
            onTap: () => context.push(
              '/collection?type=album'
              '&id=${Uri.encodeQueryComponent(release.id)}',
            ),
          );
        },
      ),
    );
  }
}
