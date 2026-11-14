import 'package:flutter_test/flutter_test.dart';
import 'package:waveify/features/import/matching/evaluate.dart';
import 'package:waveify/features/import/matching/source_profile.dart';
import 'package:waveify/models/track.dart';

/// The expectations come from the test suite of the Electron client
/// (`src/shared/media/matching/evaluate.test.ts`).
void main() {
  final source = const ImportedTrack(
    id: 'source',
    title: 'Song Name',
    artists: ['Artist'],
    durationMs: 180000,
  );
  final matching = const Track(
    id: 'track',
    title: 'Song Name',
    artistList: [TrackArtist(id: 'artist', name: 'Artist')],
    durationMs: 181000,
  );

  Track track(String id, String title, String artist, int durationMs) {
    return Track(
      id: id,
      title: title,
      artistList: [TrackArtist(id: 'a_$id', name: artist)],
      durationMs: durationMs,
    );
  }

  ImportedTrack sourceTrack(String title, String artist, int durationMs) {
    return ImportedTrack(
      id: 'src',
      title: title,
      artists: [artist],
      durationMs: durationMs,
    );
  }

  void expectMatch(MatchDecision result, String id, int minScore) {
    expect(result.isAccepted, isTrue);
    expect(result.track!.id, id);
    expect(result.score, isNotNull);
    expect(result.score!, greaterThanOrEqualTo(minScore));
  }

  group('evaluateImportedTrack', () {
    test('accepts a strong title, artist and duration match', () {
      final result = evaluateImportedTrack(source, [matching]);
      expect(result.isAccepted, isTrue);
      expect(result.track!.id, 'track');
    });

    test('rejects a high title but wrong artist and duration', () {
      final wrong = matching.copyWith(
        artistList: const [TrackArtist(id: 'other', name: 'Someone Else')],
        durationMs: 240000,
      );
      expect(evaluateImportedTrack(source, [wrong]).isAccepted, isFalse);
    });

    test('rejects the ambiguous candidates instead of guessing', () {
      final remix = track('track1', 'Song Name (Remix)', 'Artist', 180000);
      final live = track('track2', 'Song Name (Live)', 'Artist', 180000);
      expect(evaluateImportedTrack(source, [remix, live]).isAccepted, isFalse);
    });

    test('explains a rejected duration mismatch', () {
      final result = evaluateImportedTrack(
        source,
        [matching.copyWith(durationMs: 240000)],
      );
      expect(result.isAccepted, isFalse);
      expect(result.reason, MatchRejectionReason.durationMismatch);
    });

    test('returns a low confidence when there are no candidates', () {
      final result = evaluateImportedTrack(source, const []);
      expect(result.isAccepted, isFalse);
      expect(result.reason, MatchRejectionReason.lowConfidenceMatch);
    });

    test('matches a cyrillic title and artist with a bounded score', () {
      final result = evaluateImportedTrack(
        sourceTrack('Скажи мне кто ты', 'xxxmanera', 132162),
        [
          track('t1', 'Скажи мне кто ты', 'xxxmanera', 132000),
          track('t2', 'Другой трек', 'xxxmanera', 180000),
        ],
      );
      expect(result.isAccepted, isTrue);
      expect(result.score, 100);
      expect(result.track!.id, 't1');
    });

    test('matches the tracks ignoring the parentheses', () {
      final featSource =
          sourceTrack('Say So (feat. Nicki Minaj)', 'Doja Cat', 206000);
      final result = evaluateImportedTrack(
        featSource,
        [track('t2', 'Say So', 'Doja Cat', 206000)],
      );
      expect(result.isAccepted, isTrue);
      expect(result.score, 100);
      expect(result.track!.id, 't2');

      final cleanSource = sourceTrack('Say So', 'Doja Cat', 206000);
      final featCandidate =
          track('t3', 'Say So (feat. Doja Cat)', 'Doja Cat', 206000);
      final second = evaluateImportedTrack(cleanSource, [featCandidate]);
      expect(second.isAccepted, isTrue);
      expect(second.score, 100);
      expect(second.track!.id, 't3');
    });

    test('matches the transliterated artist names', () {
      final result = evaluateImportedTrack(
        sourceTrack('Адская колыбельная', 'Poshlaya Molly', 178000),
        [track('t4', 'Адская колыбельная', 'Пошлая Молли', 179000)],
      );
      expectMatch(result, 't4', 0);
    });

    test('matches the hyphenated version tags', () {
      final result = evaluateImportedTrack(
        sourceTrack(
          "(I Can't Get No) Satisfaction - Mono",
          'The Rolling Stones',
          223000,
        ),
        [
          track(
            't5',
            "(I Can't Get No) Satisfaction (Mono)",
            'The Rolling Stones',
            224000,
          ),
        ],
      );
      expectMatch(result, 't5', 0);
    });
  });
}
