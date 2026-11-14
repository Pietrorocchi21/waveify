import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../models/lyrics.dart';
import '../../models/track.dart';
import '../player/player_controller.dart';
import '../player/player_state.dart';
import 'lyrics_parser.dart';
import 'lyrics_stream.dart';

/// Lyrics state for the currently playing track.
class LyricsState {
  const LyricsState({
    this.trackId,
    this.isLoading = false,
    this.error,
    this.candidate,
    this.parsed,
    this.providers = const [],
    this.offsetMs = 0,
  });

  final String? trackId;
  final bool isLoading;
  final String? error;
  final LyricsCandidate? candidate;
  final ParsedLyrics? parsed;
  final List<LyricsProviderOption> providers;
  final int offsetMs;

  LyricsState copyWith({
    String? trackId,
    bool clearTrackId = false,
    bool? isLoading,
    String? error,
    bool clearError = false,
    LyricsCandidate? candidate,
    ParsedLyrics? parsed,
    List<LyricsProviderOption>? providers,
    int? offsetMs,
  }) {
    return LyricsState(
      trackId: clearTrackId ? null : (trackId ?? this.trackId),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      candidate: candidate ?? this.candidate,
      parsed: parsed ?? this.parsed,
      providers: providers ?? this.providers,
      offsetMs: offsetMs ?? this.offsetMs,
    );
  }
}

/// Loads and exposes the lyrics of the current track.
class LyricsController extends Notifier<LyricsState> {
  CancelToken? _cancel;
  int _loadToken = 0;

  @override
  LyricsState build() {
    final offset = ref.read(settingsProvider).lyricsOffsetMs;

    // The lyrics follow the playing track: they are loaded as soon as a
    // track starts and dropped when the player goes idle.
    ref.listen<PlayerState>(playerControllerProvider, (previous, next) {
      final track = next.currentTrack;
      if (track == null) {
        if (previous?.currentTrack != null) reset();
        return;
      }
      if (previous?.currentTrack?.id == track.id) return;
      Future<void>.microtask(() => load(track));
    });

    return LyricsState(offsetMs: offset);
  }

  /// Loads the lyrics for a track, replacing any previous stream.
  Future<void> load(Track track) async {
    if (state.trackId == track.id && state.parsed != null) return;

    _cancel?.cancel('superseded');
    final cancel = CancelToken();
    _cancel = cancel;
    final token = ++_loadToken;

    state = state.copyWith(
      trackId: track.id,
      isLoading: true,
      clearError: true,
      candidate: null,
      parsed: null,
      providers: const [],
    );

    final stream = LyricsStream(client: ref.read(apiClientProvider));

    LyricsCandidate? best;
    final providers = <LyricsProviderOption>[];

    try {
      await for (final event in stream.events(
        trackId: track.id,
        title: track.title,
        artist: track.artists,
        durationMs: track.durationMs,
        cancelToken: cancel,
      )) {
        if (token != _loadToken) return;

        switch (event) {
          case LyricsProviderFoundEvent(:final candidate):
            if (best == null || _isBetter(candidate, best)) {
              best = candidate;
              state = state.copyWith(
                candidate: candidate,
                parsed: LyricsParser.parse(
                  candidate.content,
                  format: candidate.format.raw,
                  songDurationMs: track.durationMs,
                ).offset(state.offsetMs),
              );
            }
            providers.removeWhere((p) => p.provider == candidate.provider);
            providers.add(
              LyricsProviderOption(
                provider: candidate.provider,
                syncLevel: candidate.syncLevel,
                quality: candidate.quality.total,
                candidate: candidate,
              ),
            );
            state = state.copyWith(providers: [...providers]);
          case LyricsDoneEvent():
            state = state.copyWith(isLoading: false);
            return;
          case LyricsProviderErrorEvent():
          case LyricsProviderNotFoundEvent():
          case LyricsMetadataEvent():
            break;
        }
      }
      state = state.copyWith(isLoading: false);
    } catch (err) {
      if (token != _loadToken) return;
      state = state.copyWith(isLoading: false, error: '$err');
    }
  }

  /// Switches to a different provider's lyrics.
  void selectProvider(LyricsProviderOption option) {
    final candidate = option.candidate;
    if (candidate == null) return;
    state = state.copyWith(
      candidate: candidate,
      parsed: LyricsParser.parse(
        candidate.content,
        format: candidate.format.raw,
      ).offset(state.offsetMs),
    );
  }

  /// Applies a manual timing offset.
  Future<void> setOffset(int offsetMs) async {
    state = state.copyWith(offsetMs: offsetMs);
    final parsed = state.parsed;
    if (parsed != null) {
      state = state.copyWith(parsed: parsed.offset(offsetMs));
    }
    await ref.read(settingsProvider.notifier).setLyricsOffset(offsetMs);
  }

  /// Clears the current lyrics.
  void reset() {
    _cancel?.cancel('reset');
    _loadToken++;
    state = LyricsState(offsetMs: state.offsetMs);
  }

  static bool _isBetter(LyricsCandidate a, LyricsCandidate b) {
    if (a.topPriority && !b.topPriority) return true;
    if (a.quality.total != b.quality.total) {
      return a.quality.total > b.quality.total;
    }
    return _syncRank(a.syncLevel) > _syncRank(b.syncLevel);
  }

  static int _syncRank(LyricsSyncLevel level) {
    switch (level) {
      case LyricsSyncLevel.syllableLevel:
        return 4;
      case LyricsSyncLevel.wordLevel:
        return 3;
      case LyricsSyncLevel.lineLevel:
        return 2;
      case LyricsSyncLevel.plain:
        return 1;
    }
  }
}

/// The lyrics controller provider.
final lyricsControllerProvider =
    NotifierProvider<LyricsController, LyricsState>(LyricsController.new);
