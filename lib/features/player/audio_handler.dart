import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

/// Wraps the `just_audio` player and exposes it to the OS media controls.
///
/// The handler owns the low-level audio plumbing (loading, transport, speed
/// and pitch) while the higher-level queue logic lives in the player
/// controller, which drives this class through the callbacks below.
class WaveifyAudioHandler extends BaseAudioHandler {
  /// The seek step used by the fast-forward / rewind actions.
  static const Duration seekStep = Duration(seconds: 10);

  WaveifyAudioHandler({AudioPlayer? player})
    : _player = player ?? AudioPlayer() {
    _player.playbackEventStream.listen(
      _broadcastState,
      onError: (Object error, StackTrace stackTrace) {
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.error,
            errorMessage: '$error',
          ),
        );
      },
    );

    _player.positionStream.listen((position) {
      final state = playbackState.value;
      playbackState.add(state.copyWith(updatePosition: position));
    });

    _player.durationStream.listen((duration) {
      final item = mediaItem.value;
      if (item == null || duration == null) return;
      if (item.duration != duration) {
        mediaItem.add(item.copyWith(duration: duration));
      }
    });
  }

  final AudioPlayer _player;
  double _volume = 1;

  /// Called when the current track finishes playing.
  void Function()? onTrackEnded;

  /// Called when the OS asks for the next / previous track.
  Future<void> Function()? onSkipNext;
  Future<void> Function()? onSkipPrevious;

  AudioPlayer get player => _player;

  Duration get position => _player.position;

  Duration get duration => _player.duration ?? Duration.zero;

  bool get isPlaying => _player.playing;

  /// Loads a stream URL and starts playback.
  ///
  /// The URL is signed and short-lived, so it is re-resolved by the caller
  /// whenever [onStreamExpired] fires.
  Future<void> loadAndPlay({
    required String url,
    required MediaItem mediaItem,
    Duration? initialPosition,
    double speed = 1,
    double pitch = 1,
    Map<String, String>? headers,
  }) async {
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.loading,
      ),
    );

    this.mediaItem.add(mediaItem);

    try {
      await _player.setAudioSource(
        AudioSource.uri(Uri.parse(url), headers: headers, tag: mediaItem),
      );
    } catch (err) {
      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.error,
          errorMessage: '$err',
        ),
      );
      rethrow;
    }

    await _player.setSpeed(speed);
    await _player.setPitch(pitch);
    await _player.setVolume(_volume);

    if (initialPosition != null && initialPosition > Duration.zero) {
      await _player.seek(initialPosition);
    }

    await play();
  }

  @override
  Future<void> play() async {
    if (_player.playing) return;
    playbackState.add(
      playbackState.value.copyWith(
        playing: true,
        processingState: AudioProcessingState.ready,
      ),
    );
    unawaited(
      _player.play().catchError((Object error, StackTrace stack) {
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.error,
            errorMessage: '$error',
          ),
        );
      }),
    );
  }

  @override
  Future<void> pause() async {
    if (!_player.playing) return;
    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.ready,
      ),
    );
    await _player.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    playbackState.add(playbackState.value.copyWith(updatePosition: position));
  }

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  /// Sets the output volume (0..1).
  Future<void> setVolume(double volume) async {
    _volume = volume;
    await _player.setVolume(volume);
  }

  /// Sets the pitch shift in semitones.
  ///
  /// `just_audio` implements this natively (SoundTouch on Android, CoreAudio
  /// on Apple platforms). It is a no-op on the desktop players.
  Future<void> setPitchSemitones(double semitones) async {
    final multiplier = _semitonesToMultiplier(semitones);
    await _player.setPitch(multiplier);
  }

  /// Converts a semitone offset into a playback-rate multiplier.
  static double _semitonesToMultiplier(double semitones) {
    if (semitones == 0) return 1;
    return math.pow(2, semitones / 12).toDouble();
  }

  @override
  Future<void> skipToNext() async {
    await onSkipNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    await onSkipPrevious?.call();
  }

  /// Releases the underlying player.
  Future<void> dispose() async {
    onTrackEnded = null;
    onSkipNext = null;
    onSkipPrevious = null;
    await _player.dispose();
  }

  @override
  Future<void> fastForward() => _seekRelative(seekStep);

  @override
  Future<void> rewind() => _seekRelative(-seekStep);

  Future<void> _seekRelative(Duration offset) async {
    final target = position + offset;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (duration > Duration.zero && target > duration ? duration : target);
    await seek(clamped);
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    final processingState = switch (_player.processingState) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    };

    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 3],
        processingState: processingState,
        playing: playing,
        updatePosition: _player.position,
      ),
    );

    if (event.processingState == ProcessingState.completed) {
      onTrackEnded?.call();
    }
  }
}
