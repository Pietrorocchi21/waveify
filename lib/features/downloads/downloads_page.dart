import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:waveify/core/providers/app_providers.dart';
import 'package:waveify/shared/widgets/common.dart';
import 'package:waveify/models/track.dart';
import 'package:waveify/shared/widgets/track_widgets.dart';
import 'downloads_store.dart';
import 'downloads_controller.dart';

/// The tracks that are available offline.
class DownloadsPage extends ConsumerWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);
    final downloads = ref.watch(downloadsControllerProvider);
    final controller = ref.read(downloadsControllerProvider.notifier);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('downloads.title'),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t('downloads.legal'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (downloads.tracks.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatSize(downloads.totalSize),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTertiary,
                      ),
                    ),
                    TextButton(
                      onPressed: controller.removeAll,
                      child: Text(t('downloads.remove_all')),
                    ),
                  ],
                ),
            ],
          ),
        ),
        Expanded(
          child: downloads.isLoading && downloads.tracks.isEmpty
              ? const LoadingState()
              : downloads.tracks.isEmpty
                  ? EmptyState(
                      icon: Icons.download_for_offline_outlined,
                      title: t('downloads.empty_title'),
                      description: t('downloads.empty_desc'),
                    )
                  : ListView.builder(
                      itemCount: downloads.tracks.length,
                      itemBuilder: (context, index) {
                        final item = downloads.tracks[index];
                        final track = TrackRow(
                          track: _toTrack(item),
                          queue: [
                            for (final d in downloads.tracks) _toTrack(d),
                          ],
                          context_: 'downloads',
                          index: index,
                          trailing: IconButton(
                            tooltip: t('common.remove'),
                            icon: Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: theme.textTertiary,
                            ),
                            onPressed: () => controller.remove(item.trackId),
                          ),
                        );
                        return track;
                      },
                    ),
        ),
      ],
    );
  }

  static Track _toTrack(DownloadedTrack item) {
    return Track(
      id: item.trackId,
      title: item.title,
      artists: item.artists,
      coverUrl: item.coverUrl,
      durationMs: item.durationMs,
      album: item.album.isEmpty ? null : TrackAlbum(title: item.album),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes <= 0) return '0 MB';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value < 10 ? 1 : 0)} ${units[unit]}';
  }
}
