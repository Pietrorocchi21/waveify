import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:waveify/features/player/audio_handler.dart';

class FakeAudioPlayer extends Fake implements AudioPlayer {
  final events = StreamController<PlaybackEvent>.broadcast();
  final positions = StreamController<Duration>.broadcast();
  final durations = StreamController<Duration?>.broadcast();
  final playback = Completer<void>();
  int playCalls = 0;
  @override
  bool playing = false;
  @override
  Duration position = Duration.zero;
  @override
  Duration? duration = const Duration(seconds: 60);
  @override
  double volume = 1;
  @override
  double pitch = 1;

  @override
  Stream<PlaybackEvent> get playbackEventStream => events.stream;
  @override
  Stream<Duration> get positionStream => positions.stream;
  @override
  Stream<Duration?> get durationStream => durations.stream;
  @override
  Future<void> play() {
    playCalls++;
    playing = true;
    return playback.future;
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    this.position = position ?? Duration.zero;
  }

  @override
  Future<void> setVolume(double volume) async {
    this.volume = volume;
  }

  @override
  Future<void> setPitch(double pitch) async {
    this.pitch = pitch;
  }

  @override
  Future<void> dispose() async {
    if (!playback.isCompleted) playback.complete();
    await events.close();
    await positions.close();
    await durations.close();
  }
}

void main() {
  late FakeAudioPlayer player;
  late WaveifyAudioHandler handler;

  setUp(() {
    player = FakeAudioPlayer();
    handler = WaveifyAudioHandler(player: player);
  });
  tearDown(() => handler.dispose());

  test('play returns while the audio is still playing', () async {
    await handler.play().timeout(const Duration(seconds: 1));
    expect(player.playback.isCompleted, isFalse);
    expect(handler.playbackState.value.playing, isTrue);
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.ready,
    );
    await handler.play();
    expect(player.playCalls, 1);
  });

  test('starting playback clears an earlier stream error', () async {
    final failed = handler.playbackState.firstWhere(
      (state) => state.processingState == AudioProcessingState.error,
    );
    player.events.addError(StateError('expired stream'));
    await failed;
    await handler.play();
    expect(handler.playbackState.value.playing, isTrue);
    expect(handler.playbackState.value.errorMessage, isNull);
  });

  test('asynchronous playback failure reaches the media state', () async {
    await handler.play();
    final failedState = handler.playbackState.firstWhere(
      (state) => state.processingState == AudioProcessingState.error,
    );
    player.playback.completeError(StateError('stream expired'));
    expect((await failedState).errorMessage, contains('stream expired'));
  });

  test(
    'relative seeking clamps to the beginning and end of the track',
    () async {
      player.position = const Duration(seconds: 3);
      await handler.rewind();
      expect(player.position, Duration.zero);
      player.position = const Duration(seconds: 58);
      await handler.fastForward();
      expect(player.position, const Duration(seconds: 60));
      expect(handler.playbackState.value.updatePosition, player.position);
    },
  );

  test('volume and semitone pitch are forwarded to the player', () async {
    await handler.setVolume(0.35);
    await handler.setPitchSemitones(12);
    expect(player.volume, 0.35);
    expect(player.pitch, closeTo(2, 1e-10));
  });

  test('duration updates keep the current media metadata', () async {
    handler.mediaItem.add(const MediaItem(id: 'track', title: 'Song'));
    final updatedItem = handler.mediaItem.firstWhere(
      (item) => item?.duration == const Duration(seconds: 80),
    );
    player.durations.add(const Duration(seconds: 80));
    final item = await updatedItem;
    expect(item?.id, 'track');
    expect(item?.title, 'Song');
  });
}
