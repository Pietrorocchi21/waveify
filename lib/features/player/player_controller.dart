import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/media/innertube/stream_resolver.dart';
import '../../core/music/aggregated_music_repository.dart';
import '../../core/network/waveify_api.dart';
import '../../core/platform/discord_service.dart';
import '../../core/platform/window_service.dart';
import '../../core/providers/app_providers.dart';
import '../../core/storage/app_settings.dart';
import '../../models/track.dart';
import '../downloads/downloads_controller.dart';
import '../remote/remote_controller.dart';
import 'audio_handler.dart';
import 'player_state.dart';

/// The audio handler, created once and shared by the whole app.
final audioHandlerProvider = Provider<WaveifyAudioHandler>((ref) {
  final handler = WaveifyAudioHandler();
  ref.onDispose(handler.dispose);
  return handler;
});

/// The player engine.
///
/// Mirrors `src/features/player/engine/playerEngine.ts`: it owns the queue,
/// the radio/autoplay refill, the playback telemetry and the pitch/speed
/// linkage.
class PlayerController extends Notifier<PlayerState> {
  static const int _maxConsecutiveAutoSkips = 3;

  late final WaveifyAudioHandler _handler;
  late final StreamResolver _resolver;
  late final AggregatedMusicRepository _musicRepository;
  late final _TelemetryTracker _telemetry;

  List<Track> _masterPlaylist = [];
  List<Track> _originalUpcomingQueue = [];
  int _sessionId = 0;
  String? _radioWaveId;
  Timer? _radioAppendTimer;
  Future<void>? _radioFetchInFlight;
  int _consecutiveAutoSkips = 0;
  bool _keepAwake = false;
  DateTime _lastRemotePublish = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastRemoteCommandId;
  final Random _random = Random();

  @override
  PlayerState build() {
    _handler = ref.watch(audioHandlerProvider);
    _resolver = ref.watch(streamResolverProvider);
    _musicRepository = ref.watch(musicRepositoryProvider);
    _telemetry = _TelemetryTracker(ref.read(apiProvider));

    _handler.onTrackEnded = _handleTrackEnded;
    _handler.onSkipNext = () async => skipNext();
    _handler.onSkipPrevious = () async => skipPrevious();

    _handler.playbackState.listen(_onPlaybackState);

    final settings = ref.read(settingsProvider);
    _telemetry.volume = settings.volume;

    // Restore the persisted volume on the player itself.
    Future<void>.microtask(() => _handler.setVolume(settings.volume));

    // The commands of the other device are applied as soon as they arrive.
    ref.listen<RemoteState>(remoteControllerProvider, (previous, next) {
      final commandId = next.remote?.commandId;
      if (commandId == null || commandId == _lastRemoteCommandId) return;
      _lastRemoteCommandId = commandId;
      _applyRemoteCommand(next.remote!.command);
    });

    ref.onDispose(() {
      _radioAppendTimer?.cancel();
      _handler.onTrackEnded = null;
    });

    return PlayerState(
      volume: settings.volume,
      repeat: settings.repeat,
      shuffle: settings.shuffle,
      playbackRate: settings.playbackRate,
      pitchSemitones: settings.pitchSemitones,
      isPitchLinked: settings.isPitchLinked,
      keepSpeedAcrossTracks: settings.keepSpeedAcrossTracks,
      autoplaySimilar: settings.autoplaySimilar,
    );
  }

  // ---------------------------------------------------------------------------
  // Transport
  // ---------------------------------------------------------------------------

  /// Plays a track, optionally replacing the queue.
  Future<void> playTrack(
    Track track, {
    List<Track>? queue,
    String? context,
    String? contextCover,
    int? index,
    bool preserveQueue = false,
  }) async {
    final nextQueue = _normalizeQueue(queue ?? [track], track);
    final nextIndex = index ??
        max(0, nextQueue.indexWhere((t) => t.id == track.id));

    _sessionId += 1;
    _radioWaveId = _newRadioWaveId();

    final isSelectingFromCurrentQueue = preserveQueue ||
        (index != null &&
            state.queue.isNotEmpty &&
            state.queue.length == nextQueue.length &&
            state.queue[index].id == track.id);

    var finalQueue = nextQueue;
    var finalIndex = nextIndex;

    if (!isSelectingFromCurrentQueue) {
      _masterPlaylist = [...nextQueue];
      if (state.shuffle && nextQueue.length > 1) {
        final played = nextQueue.sublist(0, nextIndex);
        final selected = nextQueue[nextIndex];
        final upcoming = nextQueue.sublist(nextIndex + 1);
        _originalUpcomingQueue = [...upcoming];
        finalQueue = [...played, selected, ..._shuffle(upcoming)];
        finalIndex = nextIndex;
      } else {
        _originalUpcomingQueue = [];
      }
    }

    if (context != null) {
      state = state.copyWith(playbackContext: context);
    }
    if (contextCover != null) {
      state = state.copyWith(playbackContextCover: contextCover);
    }

    final selected =
        finalIndex >= 0 && finalIndex < finalQueue.length ? finalQueue[finalIndex] : track;

    state = state.copyWith(
      queue: finalQueue,
      currentIndex: finalIndex,
      currentTrack: selected,
      position: Duration.zero,
      duration: Duration(milliseconds: selected.durationMs),
      status: PlayerStatus.loading,
      clearError: true,
    );

    await _loadAndPlay(selected);

    _maybeExtendQueue(_sessionId, state.currentTrack!.id, finalIndex, finalQueue.length);
  }

  /// Plays the whole list in random order.
  Future<void> playShuffled(
    List<Track> tracks, {
    String? context,
    String? contextCover,
    int? startIndex,
  }) async {
    if (tracks.isEmpty) return;

    final seedIndex = (startIndex != null && startIndex >= 0 && startIndex < tracks.length)
        ? startIndex
        : _random.nextInt(tracks.length);
    final seed = tracks[seedIndex];
    final remaining = [
      ...tracks.sublist(0, seedIndex),
      ...tracks.sublist(seedIndex + 1),
    ];
    final finalQueue = [seed, ..._shuffle(remaining)];

    _masterPlaylist = [...tracks];
    _originalUpcomingQueue = [...remaining];

    _sessionId += 1;
    _radioWaveId = _newRadioWaveId();

    state = state.copyWith(
      shuffle: true,
      queue: finalQueue,
      currentIndex: 0,
      currentTrack: seed,
      position: Duration.zero,
      duration: Duration(milliseconds: seed.durationMs),
      status: PlayerStatus.loading,
      clearError: true,
    );
    if (context != null) state = state.copyWith(playbackContext: context);
    if (contextCover != null) {
      state = state.copyWith(playbackContextCover: contextCover);
    }

    await _loadAndPlay(seed);
    _maybeExtendQueue(_sessionId, seed.id, 0, finalQueue.length);
  }

  /// Starts a radio station seeded by a track.
  Future<void> startRadioStation(Track track) async {
    _sessionId += 1;
    _radioWaveId = _newRadioWaveId();
    final waveId = _radioWaveId;

    if (state.repeat == PlaybackRepeatMode.all) {
      state = state.copyWith(repeat: PlaybackRepeatMode.off);
    }

    state = state.copyWith(
      playbackContext: 'radio:${track.id}',
      playbackContextCover: track.coverUrl,
      queue: [track],
      currentIndex: 0,
      currentTrack: track,
      position: Duration.zero,
      duration: Duration(milliseconds: track.durationMs),
      status: PlayerStatus.loading,
      clearError: true,
    );

    await _loadAndPlay(track);

    try {
      final response = await ref.read(catalogProvider).getRadio(
            track.id,
            k: 20,
            waveId: waveId,
          );
      final additions = response.items
          .where((t) => t.id != track.id)
          .toList(growable: false);
      if (additions.isEmpty) return;

      var updatedQueue = [track, ...additions];
      if (state.shuffle) {
        _originalUpcomingQueue = [...additions];
        updatedQueue = [track, ..._shuffle(additions)];
      }
      state = state.copyWith(queue: updatedQueue);
    } catch (_) {
      // A failed refill simply leaves the station with a single track.
    }
  }

  Future<void> _loadAndPlay(Track track, {Duration? initialPosition}) async {
    _telemetry.startTrack(track, state.playbackContext);

    try {
      final stream = await _resolveStream(track);
      final mediaItem = MediaItem(
        id: track.id,
        title: track.title,
        artist: track.artists,
        album: track.album?.title,
        duration: Duration(milliseconds: track.durationMs),
        artUri: track.coverUrl.isEmpty ? null : Uri.tryParse(track.coverUrl),
        extras: {'trackId': track.id},
      );

      final speed = state.keepSpeedAcrossTracks ? state.playbackRate : 1.0;
      final pitch = state.keepSpeedAcrossTracks ? state.pitchSemitones : 0.0;

      await _handler.loadAndPlay(
        url: stream.url,
        mediaItem: mediaItem,
        initialPosition: initialPosition,
        speed: speed,
        pitch: _semitoneMultiplier(pitch),
      );
    } catch (err) {
      await _handlePlaybackError(track.id, '$err');
    }
  }

  Future<ResolvedAudioStream> _resolveStream(Track track) async {
    // A downloaded track is played from the local file.
    final local =
        await ref.read(downloadsControllerProvider.notifier).localFile(track.id);
    if (local != null && local.exists) {
      return ResolvedAudioStream.local(
        local.filePath,
        durationMs: local.durationMs,
      );
    }

    // Prefer the aggregated repository: it resolves the best source first and
    // can fall back across remote providers without tying the player to one
    // catalog implementation.
    final searchResults = await _musicRepository.search(track.title, limit: 20);
    for (final item in searchResults) {
      if (item.id == track.id ||
          (item.title.toLowerCase() == track.title.toLowerCase() &&
              item.artists.toLowerCase() == track.artists.toLowerCase())) {
        final streamUrl = await _musicRepository.resolveStreamUrl(item);
        if (streamUrl != null && streamUrl.isNotEmpty) {
          return ResolvedAudioStream(
            url: streamUrl,
            mimeType: 'audio/mpeg',
            durationMs: item.durationMs,
          );
        }
      }
    }

    // A track id that is already a YouTube video id resolves directly.
    final videoId = StreamResolver.toVideoId(track.id);
    if (videoId != null) {
      return _resolver.resolveDirectAudioStream(track.id);
    }

    final resolvedFallback = await _musicRepository.resolveBestCandidate(track.id);
    if (resolvedFallback != null) {
      final streamUrl = await _musicRepository.resolveStreamUrl(resolvedFallback);
      if (streamUrl != null && streamUrl.isNotEmpty) {
        return ResolvedAudioStream(
          url: streamUrl,
          mimeType: 'audio/mpeg',
          durationMs: resolvedFallback.durationMs,
        );
      }
    }

    throw InnertubeException(
      'No playable stream for "${track.title}".',
      404,
    );
  }

  /// The current position of the playback.
  Duration get position => state.position;

  /// The current output volume.
  double get volume => state.volume;

  Future<void> pause() async {
    if (state.status == PlayerStatus.idle) return;
    _telemetry.onPausedOrStopped();
    state = state.copyWith(status: PlayerStatus.paused);
    await _handler.pause();
  }

  Future<void> resume() async {
    if (state.currentTrack == null) return;
    state = state.copyWith(status: PlayerStatus.playing, clearError: true);
    await _handler.play();
  }

  Future<void> togglePlayPause() async {
    if (state.status == PlayerStatus.playing ||
        state.status == PlayerStatus.loading) {
      await pause();
    } else {
      await resume();
    }
  }

  Future<void> skipNext({bool isAutoEnd = false}) async {
    final nextIndex = _computeNextIndex(isAutoEnd: isAutoEnd);

    if (nextIndex == null && state.isRadioContext && state.currentTrack != null) {
      final lengthBefore = state.queue.length;
      final waitSession = _sessionId;
      state = state.copyWith(status: PlayerStatus.loading);
      await _appendSimilarTracksForSeed(waitSession, state.currentTrack!.id);
      if (waitSession != _sessionId) return;
      if (state.queue.length > lengthBefore) {
        await skipNext(isAutoEnd: isAutoEnd);
        return;
      }
    }

    if (nextIndex == null) {
      await _handler.pause();
      state = state.copyWith(
        status: PlayerStatus.idle,
        position: Duration.zero,
        duration: Duration.zero,
        clearCurrentTrack: true,
        currentIndex: -1,
      );
      return;
    }

    _sessionId += 1;
    if (nextIndex >= state.queue.length) return;
    final nextTrack = state.queue[nextIndex];

    state = state.copyWith(
      currentTrack: nextTrack,
      currentIndex: nextIndex,
      position: Duration.zero,
      duration: Duration(milliseconds: nextTrack.durationMs),
      status: PlayerStatus.loading,
      clearError: true,
    );

    await _loadAndPlay(nextTrack);
    _maybeExtendQueue(_sessionId, nextTrack.id, nextIndex, state.queue.length);
  }

  Future<void> skipPrevious() async {
    if (state.queue.isEmpty) return;

    if (state.position.inMilliseconds > 3000) {
      await seek(Duration.zero);
      return;
    }

    final prevIndex = state.currentIndex > 0
        ? state.currentIndex - 1
        : (state.repeat == PlaybackRepeatMode.all && !state.isRadioContext
            ? state.queue.length - 1
            : 0);

    _sessionId += 1;
    if (prevIndex < 0 || prevIndex >= state.queue.length) return;
    final prevTrack = state.queue[prevIndex];

    state = state.copyWith(
      currentTrack: prevTrack,
      currentIndex: prevIndex,
      position: Duration.zero,
      duration: Duration(milliseconds: prevTrack.durationMs),
      status: PlayerStatus.loading,
      clearError: true,
    );

    await _loadAndPlay(prevTrack);
  }

  Future<void> seek(Duration position) async {
    final duration = state.duration;
    final clamped = position < Duration.zero
        ? Duration.zero
        : (duration > Duration.zero && position > duration ? duration : position);
    state = state.copyWith(position: clamped);
    await _handler.seek(clamped);
  }

  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0.0, 1.0);
    state = state.copyWith(volume: clamped);
    await _handler.setVolume(clamped);
    await ref.read(settingsProvider.notifier).setVolume(clamped);
  }

  /// Sets the playback rate, keeping pitch linked when configured.
  Future<void> setPlaybackRate(double rate) async {
    final clamped = double.parse(rate.clamp(0.5, 2.0).toStringAsFixed(2));
    if (state.isPitchLinked) {
      final semitones = double.parse(
        (12 * (log(clamped) / ln2)).toStringAsFixed(1),
      );
      state = state.copyWith(
        playbackRate: clamped,
        pitchSemitones: semitones,
      );
    } else {
      state = state.copyWith(playbackRate: clamped);
    }
    await _handler.setSpeed(clamped);
    await _handler.setPitchSemitones(state.pitchSemitones);
    await ref
        .read(settingsProvider.notifier)
        .setPlaybackRate(state.playbackRate);
  }

  /// Sets the pitch offset in semitones, keeping speed linked when configured.
  Future<void> setPitchSemitones(double semitones) async {
    final clamped = double.parse(semitones.clamp(-12.0, 12.0).toStringAsFixed(1));
    if (state.isPitchLinked) {
      final rate = double.parse(
        _semitoneMultiplier(clamped).clamp(0.5, 2.0).toStringAsFixed(2),
      );
      state = state.copyWith(pitchSemitones: clamped, playbackRate: rate);
      await _handler.setSpeed(rate);
    } else {
      state = state.copyWith(pitchSemitones: clamped);
    }
    await _handler.setPitchSemitones(state.pitchSemitones);
    await ref
        .read(settingsProvider.notifier)
        .setPitchSemitones(state.pitchSemitones);
  }

  Future<void> setIsPitchLinked(bool linked) async {
    state = state.copyWith(isPitchLinked: linked);
    if (linked) {
      final semitones = double.parse(
        (12 * (log(state.playbackRate) / ln2)).toStringAsFixed(1),
      );
      state = state.copyWith(pitchSemitones: semitones);
    }
    await ref.read(settingsProvider.notifier).setIsPitchLinked(linked);
  }

  Future<void> setRepeat(PlaybackRepeatMode mode) async {
    state = state.copyWith(repeat: mode);
    await ref.read(settingsProvider.notifier).setRepeat(mode);
  }

  Future<void> setShuffle(bool enabled) async {
    if (state.shuffle == enabled) return;
    state = state.copyWith(shuffle: enabled);
    await ref.read(settingsProvider.notifier).setShuffle(enabled);

    if (state.queue.isEmpty || state.currentIndex < 0) return;

    final played = state.queue.sublist(0, state.currentIndex);
    final current = state.queue[state.currentIndex];
    final upcoming = state.queue.sublist(state.currentIndex + 1);

    if (enabled) {
      _originalUpcomingQueue = [...upcoming];
      state = state.copyWith(queue: [...played, current, ..._shuffle(upcoming)]);
    } else {
      final reference =
          _masterPlaylist.isNotEmpty ? _masterPlaylist : _originalUpcomingQueue;
      state = state.copyWith(
        queue: [...played, current, ..._restoreOriginalOrder(upcoming, reference)],
      );
      _originalUpcomingQueue = [];
    }
  }

  Future<void> setAutoplaySimilar(bool value) async {
    state = state.copyWith(autoplaySimilar: value);
    await ref.read(settingsProvider.notifier).setAutoplaySimilar(value);
  }

  void addToQueue(Track track) {
    state = state.copyWith(queue: [...state.queue, track]);
    if (_masterPlaylist.isNotEmpty) _masterPlaylist.add(track);
    if (state.shuffle) _originalUpcomingQueue.add(track);
  }

  void playNext(Track track) {
    if (state.queue.isEmpty) {
      unawaited(playTrack(track, queue: [track]));
      return;
    }
    final index = state.currentIndex;
    final updated = [
      ...state.queue.sublist(0, index + 1),
      track,
      ...state.queue.sublist(index + 1),
    ];
    state = state.copyWith(queue: updated);
    if (state.shuffle) _originalUpcomingQueue.insert(0, track);
  }

  void clearQueue() {
    state = state.copyWith(queue: const [], currentIndex: -1);
    _masterPlaylist = [];
    _originalUpcomingQueue = [];
  }

  void reorderQueue(int fromIndex, int toIndex) {
    final queue = [...state.queue];
    if (fromIndex < 0 ||
        fromIndex >= queue.length ||
        toIndex < 0 ||
        toIndex >= queue.length ||
        fromIndex == toIndex) {
      return;
    }
    final moved = queue.removeAt(fromIndex);
    queue.insert(toIndex, moved);

    var newIndex = state.currentIndex;
    if (state.currentIndex == fromIndex) {
      newIndex = toIndex;
    } else if (state.currentIndex > fromIndex && toIndex >= state.currentIndex) {
      newIndex -= 1;
    } else if (state.currentIndex < fromIndex && toIndex <= state.currentIndex) {
      newIndex += 1;
    }

    state = state.copyWith(queue: queue, currentIndex: newIndex);
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _onPlaybackState(PlaybackState playbackState) {
    // The position and the duration come from the player, not from the
    // track metadata: they are the ground truth of what is being played.
    final position = playbackState.updatePosition;
    final duration = _handler.mediaItem.value?.duration;
    state = state.copyWith(
      position: position,
      duration: duration ?? state.duration,
    );

    _telemetry.onTick(playbackState.playing);
    _syncDiscordPresence();
    _publishRemoteState();

    // The screen is kept awake while the music plays.
    final keepAwake = playbackState.playing ||
        playbackState.processingState == AudioProcessingState.loading ||
        playbackState.processingState == AudioProcessingState.buffering;
    if (keepAwake != _keepAwake) {
      _keepAwake = keepAwake;
      unawaited(WindowService.instance.setKeepAwake(keepAwake));
    }

    if (playbackState.processingState == AudioProcessingState.ready ||
        playbackState.processingState == AudioProcessingState.buffering) {
      if (state.status == PlayerStatus.loading) {
        state = state.copyWith(status: PlayerStatus.playing);
      }
    }
    if (playbackState.processingState == AudioProcessingState.error) {
      state = state.copyWith(
        status: PlayerStatus.error,
        error: playbackState.errorMessage,
      );
    }
  }

  /// Publishes the state of the player to the other device.
  ///
  /// The publication is throttled: the state changes several times per
  /// second while the position moves.
  void _publishRemoteState() {
    final remote = ref.read(remoteControllerProvider);
    if (!remote.isAuthenticated) return;

    final now = DateTime.now();
    if (now.difference(_lastRemotePublish) < const Duration(seconds: 4)) {
      return;
    }
    _lastRemotePublish = now;

    final track = state.currentTrack;
    unawaited(
      ref.read(remoteControllerProvider.notifier).publish(
            trackId: track?.id,
            trackTitle: track?.title,
            trackArtist: track?.artists,
            isPlaying: state.status == PlayerStatus.playing,
            positionSeconds: state.position.inMilliseconds / 1000,
          ),
    );
  }

  /// Applies the command received from the other device.
  void _applyRemoteCommand(RemoteCommand command) {
    if (command == RemoteCommand.none) return;

    switch (command) {
      case RemoteCommand.play:
        unawaited(resume());
      case RemoteCommand.pause:
        unawaited(pause());
      case RemoteCommand.next:
        unawaited(skipNext());
      case RemoteCommand.previous:
        unawaited(skipPrevious());
      case RemoteCommand.none:
        break;
    }
  }

  /// Keeps the Discord Rich Presence in sync with the player.
  void _syncDiscordPresence() {
    final settings = ref.read(settingsProvider);
    final service = DiscordService.instance;

    if (!settings.discordEnabled) {
      if (service.isEnabled) unawaited(service.setEnabled(false));
      return;
    }

    if (!service.isEnabled) {
      unawaited(service.setEnabled(true));
    }

    final track = state.currentTrack;
    if (track == null) {
      unawaited(
        service.update(details: null, state: null),
      );
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final position = state.position.inMilliseconds ~/ 1000;
    final duration = state.duration.inMilliseconds ~/ 1000;

    service.setOptions(
      showArtwork: settings.discordShowArtwork,
      showArtistImage: settings.discordShowArtistImage,
      showTime: settings.discordShowTime,
    );

    unawaited(
      service.update(
        details: track.title,
        state: track.artists,
        largeImageKey: DiscordService.toDiscordImageUrl(track.coverUrl),
        largeImageText: track.album?.title ?? track.title,
        startTimestamp: duration > 0 ? now - position : null,
        endTimestamp: duration > 0 ? now - position + duration : null,
      ),
    );
  }

  Future<void> _handleTrackEnded() async {
    _telemetry.onTrackCompleted(state.repeat == PlaybackRepeatMode.one);
    if (state.repeat == PlaybackRepeatMode.one) {
      await _handler.seek(Duration.zero);
      await _handler.play();
      return;
    }
    await skipNext(isAutoEnd: true);
  }

  Future<void> _handlePlaybackError(String trackId, String message) async {
    if (state.currentTrack?.id != trackId) return;

    _consecutiveAutoSkips += 1;
    if (_consecutiveAutoSkips > _maxConsecutiveAutoSkips) {
      _consecutiveAutoSkips = 0;
      await _handler.pause();
      state = state.copyWith(
        status: PlayerStatus.idle,
        position: Duration.zero,
        duration: Duration.zero,
        clearCurrentTrack: true,
        currentIndex: -1,
      );
      return;
    }

    state = state.copyWith(status: PlayerStatus.error, error: message);
    await skipNext();
  }

  int? _computeNextIndex({bool isAutoEnd = false}) {
    final size = state.queue.length;
    if (size == 0 || state.currentIndex < 0) return null;
    if (isAutoEnd && state.repeat == PlaybackRepeatMode.one) return state.currentIndex;
    if (state.currentIndex + 1 < size) return state.currentIndex + 1;
    if (state.isRadioContext) return null;
    if (state.repeat == PlaybackRepeatMode.all || state.repeat == PlaybackRepeatMode.one) return 0;
    return null;
  }

  void _maybeExtendQueue(
    int session,
    String seedTrackId,
    int index,
    int queueLength,
  ) {
    final radio = state.isRadioContext;
    final due = radio ? (queueLength - index <= 2) : index == queueLength - 1;
    if (!due) return;

    _radioAppendTimer?.cancel();
    _radioAppendTimer = Timer(
      const Duration(milliseconds: 400),
      () => _appendSimilarTracksForSeed(session, seedTrackId),
    );
  }

  Future<void> _appendSimilarTracksForSeed(
    int session,
    String seedTrackId,
  ) async {
    if (_radioFetchInFlight != null) return _radioFetchInFlight;

    final run = _fetchAndAppendSimilarTracks(session, seedTrackId);
    _radioFetchInFlight = run;
    try {
      await run;
    } finally {
      if (identical(_radioFetchInFlight, run)) _radioFetchInFlight = null;
    }
  }

  Future<void> _fetchAndAppendSimilarTracks(
    int session,
    String seedTrackId,
  ) async {
    final radio = state.isRadioContext;
    if (!radio && !state.autoplaySimilar) return;
    final startContext = state.playbackContext;

    final historyIds = state.queue.map((t) => t.id).toList();
    _radioWaveId ??= _newRadioWaveId();

    List<Track> items;
    try {
      final response = await ref.read(catalogProvider).getRadio(
            seedTrackId,
            history: historyIds.length > 20
                ? historyIds.sublist(historyIds.length - 20)
                : historyIds,
            k: 20,
            waveId: _radioWaveId,
          );
      items = response.items;
    } catch (_) {
      return;
    }

    if (radio ? state.playbackContext != startContext : session != _sessionId) {
      return;
    }
    if (!radio && !state.autoplaySimilar) return;

    final queuedIds = state.queue.map((t) => t.id).toSet();
    final additions = items.where((t) => !queuedIds.contains(t.id)).toList();
    if (additions.isEmpty) return;

    state = state.copyWith(queue: [...state.queue, ...additions]);
  }

  List<Track> _normalizeQueue(List<Track> queue, Track selected) {
    if (queue.isEmpty) return [selected];
    return queue
        .map(
          (item) => item.copyWith(
            coverUrl: item.coverUrl.isEmpty ? selected.coverUrl : item.coverUrl,
          ),
        )
        .toList(growable: false);
  }

  List<Track> _shuffle(List<Track> input) {
    final result = [...input];
    for (var i = result.length - 1; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final tmp = result[i];
      result[i] = result[j];
      result[j] = tmp;
    }
    return result;
  }

  List<Track> _restoreOriginalOrder(List<Track> upcoming, List<Track> reference) {
    if (reference.isEmpty) return upcoming;
    final positions = <String, int>{};
    for (var i = 0; i < reference.length; i++) {
      positions.putIfAbsent(reference[i].id, () => i);
    }
    return [...upcoming]..sort((a, b) {
        final pa = positions[a.id] ?? 1 << 62;
        final pb = positions[b.id] ?? 1 << 62;
        return pa.compareTo(pb);
      });
  }

  static String _newRadioWaveId() {
    final random = Random().nextInt(1 << 32).toRadixString(36);
    return 'wave-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-$random';
  }

  static double _semitoneMultiplier(double semitones) {
    if (semitones == 0) return 1;
    return pow(2, semitones / 12).toDouble();
  }
}

/// Tracks a playing track and reports playback events to the backend.
///
/// Mirrors `PlaybackTelemetryTracker` in `playerEngine.ts`.
class _TelemetryTracker {
  _TelemetryTracker(this._api);

  final WaveifyApi _api;

  String? _activeTrackId;
  Track? _activeTrack;
  String _playbackSessionId = '';
  String _listeningSessionId = '';
  int _lastActivityMs = 0;
  int _trackDurationMs = 0;
  int _playedDurationMs = 0;
  int? _lastTickMs;
  bool _completed = false;
  int _loopCount = 0;
  bool _hasSeekBackward = false;
  String? _context;

  static const int _sessionTimeoutMs = 30 * 60 * 1000;
  double volume = 1;

  void startTrack(Track track, String? context) {
    flush();

    _playbackSessionId = _newId('ps');
    _activeTrackId = track.id;
    _activeTrack = track;
    _trackDurationMs = track.durationMs;
    _playedDurationMs = 0;
    _lastTickMs = null;
    _completed = false;
    _loopCount = 0;
    _hasSeekBackward = false;
    _context = context;
    _getOrCreateListeningSession();
  }

  void onPlaying() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastTickMs = now;
    _lastActivityMs = now;
  }

  void onPausedOrStopped() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastActivityMs = now;
    if (_lastTickMs != null) {
      final delta = now - _lastTickMs!;
      if (delta > 0 && delta < 10000) _playedDurationMs += delta;
      _lastTickMs = null;
    }
  }

  void onTick(bool isPlaying) {
    if (_activeTrackId == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastActivityMs = now;
    if (isPlaying) {
      if (_lastTickMs != null) {
        final delta = now - _lastTickMs!;
        if (delta > 0 && delta < 5000) _playedDurationMs += delta;
      }
      _lastTickMs = now;
    } else {
      _lastTickMs = null;
    }
  }

  void recordSeekBackward() {
    _hasSeekBackward = true;
    _lastActivityMs = DateTime.now().millisecondsSinceEpoch;
  }

  void onTrackCompleted(bool isRepeatOne) {
    if (_activeTrackId == null) return;
    onPausedOrStopped();
    _completed = true;
    if (isRepeatOne) _loopCount += 1;
  }

  void flush() {
    if (_activeTrackId == null) return;
    onPausedOrStopped();

    final duration = _trackDurationMs > 0 ? _trackDurationMs : _playedDurationMs;
    final rawRate =
        duration > 0 ? _playedDurationMs / duration : (_completed ? 1.0 : 0.0);
    final completionRate = rawRate.clamp(0.0, 1.0);
    final skipped = !_completed && _playedDurationMs < 30000;

    if (_playedDurationMs >= 3000 || _completed) {
      final snapshot = _activeTrack;
      final artists = snapshot?.artistList?.isNotEmpty == true
          ? snapshot!.artistList!
              .map((a) => {'id': a.id.isEmpty ? 'unknown' : a.id, 'name': a.name})
              .toList()
          : [
              {
                'id': snapshot?.artistId ?? 'unknown',
                'name': (snapshot?.artists.isNotEmpty == true
                    ? snapshot!.artists.split(',').first.trim()
                    : 'Unknown Artist'),
              },
            ];

      final playbackContext = _context;
      unawaited(_api.recordPlaybackEvent({
        'playbackSessionId': _playbackSessionId,
        'listeningSessionId': _getOrCreateListeningSession(),
        'trackId': _activeTrackId,
        if (snapshot != null)
          'trackSnapshot': {
            'id': snapshot.id,
            'title': snapshot.title.isEmpty ? 'Unknown Track' : snapshot.title,
            'artists': artists,
            if (snapshot.album != null)
              'album': {
                'id': snapshot.album!.id,
                'title': snapshot.album!.title,
              },
            if (snapshot.coverUrl.isNotEmpty)
              'cover': {'url': snapshot.coverUrl, 'width': 512, 'height': 512},
            'durationMs': snapshot.durationMs,
          },
        'playedDurationMs': _playedDurationMs,
        if (_trackDurationMs > 0) 'trackDurationMs': _trackDurationMs,
        'completionRate': double.parse(completionRate.toStringAsFixed(4)),
        'completed': _completed,
        'skipped': skipped,
        'loopCount': _loopCount,
        'hasSeekBackward': _hasSeekBackward,
        if (playbackContext != null) 'context': _parseContext(playbackContext),
      }).catchError((Object _) {}));
    }

    _activeTrackId = null;
    _activeTrack = null;
    _playbackSessionId = '';
    _lastTickMs = null;
    _playedDurationMs = 0;
    _completed = false;
    _loopCount = 0;
    _hasSeekBackward = false;
  }

  String _getOrCreateListeningSession() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_listeningSessionId.isEmpty ||
        now - _lastActivityMs > _sessionTimeoutMs) {
      _listeningSessionId = _newId('ls');
    }
    _lastActivityMs = now;
    return _listeningSessionId;
  }

  static Map<String, dynamic> _parseContext(String context) {
    if (context.contains(':')) {
      final parts = context.split(':');
      return {'type': parts.first, 'id': parts.sublist(1).join(':')};
    }
    return {'type': context};
  }

  static String _newId(String prefix) {
    final random = Random().nextInt(0x7fffffff).toRadixString(36);
    return '${prefix}_${DateTime.now().millisecondsSinceEpoch}_$random';
  }
}

/// The player controller provider.
final playerControllerProvider =
    NotifierProvider<PlayerController, PlayerState>(PlayerController.new);

