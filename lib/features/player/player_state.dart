import '../../models/track.dart';
import '../../core/storage/app_settings.dart';

/// Transport status of the player.
enum PlayerStatus { idle, loading, playing, paused, error }

/// The complete player state.
class PlayerState {
  const PlayerState({
    this.status = PlayerStatus.idle,
    this.currentTrack,
    this.queue = const [],
    this.currentIndex = -1,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 1,
    this.repeat = PlaybackRepeatMode.off,
    this.shuffle = false,
    this.playbackRate = 1,
    this.pitchSemitones = 0,
    this.isPitchLinked = true,
    this.keepSpeedAcrossTracks = false,
    this.autoplaySimilar = true,
    this.playbackContext,
    this.playbackContextCover,
    this.error,
  });

  final PlayerStatus status;
  final Track? currentTrack;
  final List<Track> queue;
  final int currentIndex;
  final Duration position;
  final Duration duration;
  final double volume;
  final PlaybackRepeatMode repeat;
  final bool shuffle;
  final double playbackRate;
  final double pitchSemitones;
  final bool isPitchLinked;
  final bool keepSpeedAcrossTracks;
  final bool autoplaySimilar;
  final String? playbackContext;
  final String? playbackContextCover;
  final String? error;

  bool get isPlaying => status == PlayerStatus.playing;
  bool get isBusy => status == PlayerStatus.loading;
  bool get hasTrack => currentTrack != null;

  /// True when the current context is a radio station.
  bool get isRadioContext =>
      playbackContext != null && playbackContext!.startsWith('radio:');

  double get progress {
    final total = duration.inMilliseconds;
    if (total <= 0) return 0;
    return (position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  PlayerState copyWith({
    PlayerStatus? status,
    Track? currentTrack,
    bool clearCurrentTrack = false,
    List<Track>? queue,
    int? currentIndex,
    Duration? position,
    Duration? duration,
    double? volume,
    PlaybackRepeatMode? repeat,
    bool? shuffle,
    double? playbackRate,
    double? pitchSemitones,
    bool? isPitchLinked,
    bool? keepSpeedAcrossTracks,
    bool? autoplaySimilar,
    String? playbackContext,
    bool clearPlaybackContext = false,
    String? playbackContextCover,
    bool clearPlaybackContextCover = false,
    String? error,
    bool clearError = false,
  }) {
    return PlayerState(
      status: status ?? this.status,
      currentTrack:
          clearCurrentTrack ? null : (currentTrack ?? this.currentTrack),
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      volume: volume ?? this.volume,
      repeat: repeat ?? this.repeat,
      shuffle: shuffle ?? this.shuffle,
      playbackRate: playbackRate ?? this.playbackRate,
      pitchSemitones: pitchSemitones ?? this.pitchSemitones,
      isPitchLinked: isPitchLinked ?? this.isPitchLinked,
      keepSpeedAcrossTracks: keepSpeedAcrossTracks ?? this.keepSpeedAcrossTracks,
      autoplaySimilar: autoplaySimilar ?? this.autoplaySimilar,
      playbackContext: clearPlaybackContext
          ? null
          : (playbackContext ?? this.playbackContext),
      playbackContextCover: clearPlaybackContextCover
          ? null
          : (playbackContextCover ?? this.playbackContextCover),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

