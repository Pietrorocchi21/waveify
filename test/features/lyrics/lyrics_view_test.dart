import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waveify/features/lyrics/lyrics_controller.dart';
import 'package:waveify/features/player/player_controller.dart';
import 'package:waveify/features/player/player_state.dart';
import 'package:waveify/features/player/ui/fullscreen_player_page.dart';
import 'package:waveify/models/lyrics.dart';
import 'package:waveify/models/track.dart';

class LyricsPreview extends LyricsController {
  @override
  LyricsState build() => LyricsState(
    trackId: 'local:test',
    parsed: ParsedLyrics(
      syncedLines: List.generate(
        30,
        (i) => SyncedLine(timeMs: i * 5000, text: 'Synthetic line $i'),
      ),
    ),
  );
}

class SeekPlayer extends PlayerController {
  Duration? lastSeek;
  @override
  PlayerState build() => const PlayerState(
    currentTrack: Track(id: 'local:test', title: 'Synthetic'),
  );
  @override
  Future<void> seek(Duration position) async {
    lastSeek = position;
    state = state.copyWith(position: position);
  }
}

void main() {
  testWidgets(
    'lyric taps seek to their audio timestamp and follow backward seeks',
    (tester) async {
      final player = SeekPlayer();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith(() => player),
            lyricsControllerProvider.overrideWith(LyricsPreview.new),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showLyricsSheet(context),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Synthetic line 1'));
      await tester.pumpAndSettle();
      expect(player.lastSeek, const Duration(seconds: 5));
      await player.seek(const Duration(seconds: 100));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic line 20').hitTestable(), findsOneWidget);
      await player.seek(Duration.zero);
      await tester.pumpAndSettle();
      expect(find.text('Synthetic line 0').hitTestable(), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).last,
      );
      final manualPosition = scroll.position.pixels;
      await player.seek(const Duration(seconds: 100));
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, closeTo(manualPosition, 1));
    },
  );
}
