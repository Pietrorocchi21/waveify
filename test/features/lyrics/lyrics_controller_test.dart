import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waveify/core/network/api_client.dart';
import 'package:waveify/core/storage/app_settings.dart';
import 'package:waveify/features/lyrics/lyrics_controller.dart';
import 'package:waveify/features/lyrics/lyrics_stream.dart';
import 'package:waveify/features/lyrics/public_lyrics_client.dart';
import 'package:waveify/features/player/player_controller.dart';
import 'package:waveify/features/player/player_state.dart';
import 'package:waveify/models/lyrics.dart';
import 'package:waveify/models/track.dart';

class IdlePlayer extends PlayerController {
  @override
  PlayerState build() => const PlayerState();
}

class FailedStream extends LyricsStream {
  FailedStream() : super(client: ApiClient());
  @override
  Stream<LyricsStreamEvent> events({
    required String trackId,
    String? title,
    String? artist,
    int? durationMs,
    CancelToken? cancelToken,
  }) => Stream.error(StateError('Backend unavailable'));
}

class FakePublic extends PublicLyricsClient {
  final pending = <String, Completer<LyricsCandidate?>>{};
  @override
  Future<LyricsCandidate?> get(Track track, {CancelToken? cancelToken}) =>
      (pending[track.id] = Completer<LyricsCandidate?>()).future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const candidate = LyricsCandidate(
    provider: 'test',
    format: LyricsFormat.lrc,
    content: '[00:01]Synthetic line',
    syncLevel: LyricsSyncLevel.lineLevel,
  );
  const first = Track(id: 'a', title: 'A');
  const second = Track(id: 'b', title: 'B');

  test(
    'backend error falls back; offsets reparse without accumulating',
    () async {
      SharedPreferences.setMockInitialValues({});
      final fallback = FakePublic();
      final container = ProviderContainer(
        overrides: [
          playerControllerProvider.overrideWith(IdlePlayer.new),
          lyricsControllerProvider.overrideWith(
            () => LyricsController(
              streamFactory: FailedStream.new,
              publicClient: fallback,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(lyricsControllerProvider.notifier);
      final load = controller.load(first);
      await Future<void>.delayed(Duration.zero);
      expect(fallback.pending, contains('a'));
      fallback.pending['a']!.complete(candidate);
      await load;
      expect(container.read(lyricsControllerProvider).error, isNull);
      await controller.setOffset(-2000);
      await controller.setOffset(500);
      expect(
        container
            .read(lyricsControllerProvider)
            .parsed!
            .syncedLines
            .single
            .timeMs,
        1500,
      );
      expect((await AppSettings.load()).lyricsOffsetMs, 500);
    },
  );

  test(
    'late fallback from previous track cannot replace current lyrics',
    () async {
      final fallback = FakePublic();
      final container = ProviderContainer(
        overrides: [
          playerControllerProvider.overrideWith(IdlePlayer.new),
          lyricsControllerProvider.overrideWith(
            () => LyricsController(
              streamFactory: FailedStream.new,
              publicClient: fallback,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(lyricsControllerProvider.notifier);
      final a = controller.load(first);
      await Future<void>.delayed(Duration.zero);
      final b = controller.load(second);
      await Future<void>.delayed(Duration.zero);
      fallback.pending['b']!.complete(candidate);
      await b;
      fallback.pending['a']!.complete(null);
      await a;
      expect(container.read(lyricsControllerProvider).trackId, 'b');
      expect(container.read(lyricsControllerProvider).candidate, candidate);
      expect(container.read(lyricsControllerProvider).isLoading, isFalse);
    },
  );
}
