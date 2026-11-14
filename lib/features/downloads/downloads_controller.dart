import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../models/track.dart';
import 'downloads_store.dart';

/// The state of the offline downloads.
class DownloadsState {
  const DownloadsState({
    this.tracks = const [],
    this.busyTracks = const {},
    this.isLoading = false,
    this.error,
  });

  final List<DownloadedTrack> tracks;
  final Set<String> busyTracks;
  final bool isLoading;
  final String? error;

  bool isDownloaded(String trackId) =>
      tracks.any((t) => t.trackId == trackId);

  bool isBusy(String trackId) => busyTracks.contains(trackId);

  int get totalSize => tracks.fold(0, (sum, t) => sum + t.sizeBytes);

  DownloadsState copyWith({
    List<DownloadedTrack>? tracks,
    Set<String>? busyTracks,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return DownloadsState(
      tracks: tracks ?? this.tracks,
      busyTracks: busyTracks ?? this.busyTracks,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// The store of the offline downloads.
final downloadsStoreProvider = Provider<DownloadsStore>((ref) {
  return DownloadsStore();
});

/// Downloads the tracks so they can be played without a connection.
class DownloadsController extends Notifier<DownloadsState> {
  @override
  DownloadsState build() {
    unawaited(load());
    return const DownloadsState();
  }

  DownloadsStore get _store => ref.read(downloadsStoreProvider);

  /// Reloads the list of the downloaded tracks.
  Future<void> load() async {
    state = state.copyWith(isLoading: true);
    final tracks = await _store.load();
    state = state.copyWith(tracks: tracks, isLoading: false);
  }

  /// Downloads a track for offline playback.
  ///
  /// The audio is fetched from the same signed stream used for playback, and
  /// it is written in the application documents directory.
  Future<bool> download(Track track) async {
    if (state.isDownloaded(track.id)) return true;

    state = state.copyWith(
      busyTracks: {...state.busyTracks, track.id},
      clearError: true,
    );

    try {
      final resolver = ref.read(streamResolverProvider);
      final stream = await resolver.resolveDirectAudioStream(track.id);

      final directory = await _store.audioDirectory();
      final extension = stream.mimeType.contains('mp4') ? 'm4a' : 'opus';
      final file = File('${directory.path}/${_safeName(track.id)}.$extension');

      final dio = Dio();
      await dio.download(
        stream.url,
        file.path,
        options: Options(
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 5),
        ),
        onReceiveProgress: (received, total) {},
      );

      final size = await file.length();
      await _store.upsert(
        DownloadedTrack(
          trackId: track.id,
          title: track.title,
          artists: track.artists,
          album: track.album?.title ?? '',
          coverUrl: track.coverUrl,
          filePath: file.path,
          sizeBytes: size,
          durationMs: track.durationMs,
          downloadedAt: DateTime.now(),
        ),
      );

      await load();
      state = state.copyWith(
        busyTracks: {...state.busyTracks}..remove(track.id),
      );
      return true;
    } catch (error) {
      state = state.copyWith(
        busyTracks: {...state.busyTracks}..remove(track.id),
        error: '$error',
      );
      return false;
    }
  }

  /// Removes a downloaded track.
  Future<void> remove(String trackId) async {
    state = state.copyWith(
      busyTracks: {...state.busyTracks, trackId},
    );
    await _store.remove(trackId);
    await load();
    state = state.copyWith(
      busyTracks: {...state.busyTracks}..remove(trackId),
    );
  }

  /// The local file of a downloaded track, if it is available.
  Future<DownloadedTrack?> localFile(String trackId) async {
    return _store.find(trackId);
  }

  /// Removes every downloaded file.
  Future<void> removeAll() async {
    final tracks = await _store.load();
    for (final track in tracks) {
      await _store.remove(track.trackId);
    }
    await load();
  }

  static String _safeName(String id) {
    return id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  }
}

/// The downloads controller provider.
final downloadsControllerProvider =
    NotifierProvider<DownloadsController, DownloadsState>(
  DownloadsController.new,
);
