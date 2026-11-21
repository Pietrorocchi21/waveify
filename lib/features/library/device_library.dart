import 'dart:io';

import '../../core/cloud/cloud_config.dart';
import '../../core/cloud/supabase_api_client.dart';
import '../../core/media/innertube/stream_resolver.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local/local_audio_importer.dart';
import '../../core/providers/app_providers.dart';
import '../../models/track.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/track_widgets.dart';
import '../home/ui/home_page.dart';
import 'library_controller.dart';

final deviceTracksProvider = FutureProvider<List<Track>>(
  (ref) => ref
      .watch(localLibraryStoreProvider)
      .read(
        (data) => (data['tracks'] as Map).values
            .map((raw) => Track.fromJson(Map<String, dynamic>.from(raw as Map)))
            .toList(),
      ),
);

class ImportAudioButton extends ConsumerStatefulWidget {
  const ImportAudioButton({super.key});
  @override
  ConsumerState<ImportAudioButton> createState() => _ImportAudioButtonState();
}

class _ImportAudioButtonState extends ConsumerState<ImportAudioButton> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translatorProvider);
    return OutlinedButton.icon(
      onPressed: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              try {
                final files = await FilePicker.pickFiles(
                  allowMultiple: true,
                  type: FileType.custom,
                  allowedExtensions: LocalAudioImporter.extensions,
                );
                if (files == null) return;
                final result =
                    await LocalAudioImporter(
                      ref.read(localLibraryStoreProvider),
                    ).importPaths(
                      files.files
                          .map((file) => file.path)
                          .whereType<String>()
                          .toList(),
                    );
                ref.invalidate(deviceTracksProvider);
                ref.invalidate(dailyMixesProvider);
                ref.invalidate(popularTracksProvider);
                ref.invalidate(recentlyPlayedProvider);
                if (context.mounted) {
                  showAppSnackBar(
                    context,
                    result.errors.isEmpty
                        ? t('library.files_imported', {
                            'count': '${result.tracks.length}',
                          })
                        : '${t('library.files_imported', {'count': '${result.tracks.length}'})}\n${result.errors.values.join('\n')}',
                    isError: result.errors.isNotEmpty,
                  );
                }
                await ref
                    .read(libraryControllerProvider.notifier)
                    .loadLikedTracks(refresh: true);
              } catch (error) {
                if (context.mounted) {
                  showAppSnackBar(context, '$error', isError: true);
                }
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
      icon: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.audio_file_outlined, size: 18),
      label: Text(t('library.import_audio')),
    );
  }
}

class DeviceTracksTab extends ConsumerWidget {
  const DeviceTracksTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translatorProvider);
    return ref
        .watch(deviceTracksProvider)
        .when(
          loading: () => const LoadingState(),
          error: (error, stack) => ErrorState(
            message: '$error',
            onRetry: () => ref.invalidate(deviceTracksProvider),
          ),
          data: (tracks) => tracks.isEmpty
              ? EmptyState(
                  icon: Icons.audio_file_outlined,
                  title: t('library.local_empty'),
                  description: t('library.local_hint'),
                  action: const ImportAudioButton(),
                )
              : ListView.builder(
                  itemCount: tracks.length,
                  padding: const EdgeInsets.only(bottom: 24),
                  itemBuilder: (context, index) => TrackRow(
                    track: tracks[index],
                    queue: tracks,
                    context_: 'library:device',
                    trailing: CloudConfig.isConfigured
                        ? CloudUploadButton(track: tracks[index])
                        : null,
                    index: index,
                  ),
                ),
        );
  }
}

final cloudTracksProvider = FutureProvider<List<Track>>(
  (ref) async => (await ref.watch(apiProvider).search('', type: 'track'))
      .map((item) => item.track)
      .whereType<Track>()
      .toList(),
);

class CloudTracksTab extends ConsumerWidget {
  const CloudTracksTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(cloudTracksProvider)
      .when(
        loading: () => const LoadingState(),
        error: (error, stack) => ErrorState(
          message: '$error',
          onRetry: () => ref.invalidate(cloudTracksProvider),
        ),
        data: (tracks) => tracks.isEmpty
            ? EmptyState(
                icon: Icons.cloud_outlined,
                title: ref.watch(translatorProvider)('library.cloud_empty'),
              )
            : ListView.builder(
                itemCount: tracks.length,
                itemBuilder: (context, index) => TrackRow(
                  track: tracks[index],
                  queue: tracks,
                  context_: 'library:cloud',
                ),
              ),
      );
}

class CloudUploadButton extends ConsumerStatefulWidget {
  const CloudUploadButton({super.key, required this.track});
  final Track track;
  @override
  ConsumerState<CloudUploadButton> createState() => _CloudUploadButtonState();
}

class _CloudUploadButtonState extends ConsumerState<CloudUploadButton> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translatorProvider);
    return IconButton(
      tooltip: t('library.upload_cloud'),
      icon: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.cloud_upload_outlined, size: 20),
      onPressed: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              try {
                final api = ref.read(apiClientProvider);
                if (api is! SupabaseApiClient) {
                  throw StateError('Sign in to Supabase to upload audio.');
                }
                final file = File.fromUri(Uri.parse(widget.track.sourceUrl));
                final url = await api.uploadTrack(
                  await file.readAsBytes(),
                  filename: file.uri.pathSegments.last,
                  contentType: StreamResolver.mimeFor(file.path),
                );
                final snapshot = widget.track
                    .copyWith(sourceUrl: url, coverUrl: '')
                    .toSnapshot();
                final localLyrics = await ref
                    .read(localLibraryStoreProvider)
                    .read(
                      (data) =>
                          (data['tracks']
                              as Map)[widget.track.id]?['localLyrics'],
                    );
                await api.store.update((data) {
                  (data['tracks'] as Map)[widget.track.id] = {
                    ...snapshot,
                    'localLyrics': ?localLyrics,
                  };
                });
                ref.invalidate(cloudTracksProvider);
                ref.invalidate(popularTracksProvider);
                if (context.mounted) {
                  showAppSnackBar(context, t('library.uploaded_cloud'));
                }
              } catch (error) {
                if (context.mounted) {
                  showAppSnackBar(context, '$error', isError: true);
                }
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
    );
  }
}
