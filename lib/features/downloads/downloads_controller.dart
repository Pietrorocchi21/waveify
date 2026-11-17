import 'dart:convert';

import 'package:crypto/crypto.dart';

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

  bool isDownloaded(String trackId) => tracks.any((t) => t.trackId == trackId);

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
    unawaited(Future<void>.microtask(load));
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
    if (!track.downloadable) {
      state = state.copyWith(
        error: 'This provider permits streaming only for this recording.',
      );
      return false;
    }
    if (state.isDownloaded(track.id)) return true;
    if (state.isBusy(track.id)) return false;

    state = state.copyWith(
      busyTracks: {...state.busyTracks, track.id},
      clearError: true,
    );

    File? partial;
    File? completed;
    try {
      final resolver = ref.read(streamResolverProvider);
      final stream = await resolver.resolveTrackStream(
        track,
        forDownload: true,
      );

      final directory = await _store.audioDirectory();
      final extension = switch (stream.mimeType) {
        'audio/mp4' => 'm4a',
        'audio/mpeg' => 'mp3',
        'audio/wav' => 'wav',
        'audio/flac' => 'flac',
        'audio/webm' => 'webm',
        'audio/ogg' => 'ogg',
        'audio/aiff' => 'aiff',
        _ => 'audio',
      };
      final file = File('${directory.path}/${_safeName(track.id)}.$extension');
      partial = File('${file.path}.part');
      final uri = Uri.parse(stream.url);
      if (uri.scheme == 'file') {
        await File.fromUri(uri).copy(partial.path);
      } else {
        final dio = Dio();
        try {
          await dio.download(
            stream.url,
            partial.path,
            options: Options(
              headers: stream.headers,
              followRedirects: true,
              receiveTimeout: const Duration(minutes: 5),
            ),
          );
        } finally {
          dio.close(force: true);
        }
      }
      if (await partial.length() == 0) {
        throw const FormatException('The audio source returned an empty file.');
      }
      await partial.rename(file.path);
      completed = file;

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
      if (partial != null && await partial.exists()) await partial.delete();
      if (completed != null && await completed.exists()) {
        await completed.delete();
      }
      state = state.copyWith(
        busyTracks: {...state.busyTracks}..remove(track.id),
        error: '$error',
      );
      return false;
    }
  }

  /// Removes a downloaded track.
  Future<void> remove(String trackId) async {
    state = state.copyWith(busyTracks: {...state.busyTracks, trackId});
    await _store.remove(trackId);
    await load();
    state = state.copyWith(busyTracks: {...state.busyTracks}..remove(trackId));
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
    return sha256.convert(utf8.encode(id)).toString().substring(0, 32);
  }
}

/// The downloads controller provider.
final downloadsControllerProvider =
    NotifierProvider<DownloadsController, DownloadsState>(
      DownloadsController.new,
    );
