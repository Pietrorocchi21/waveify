import 'package:flutter_test/flutter_test.dart';
import 'package:waveify/core/music/aggregated_music_repository.dart';
import 'package:waveify/core/music/music_source.dart';

class _FakeSource extends MusicSource {
  _FakeSource({
    required this.id,
    required this.kind,
    required this.results,
  });

  @override
  final String id;
  @override
  final MusicProviderKind kind;
  final List<MusicSearchResult> results;

  @override
  bool get isEnabled => true;

  @override
  Future<List<MusicSearchResult>> search(String query, {int limit = 20}) async {
    if (query.trim().isEmpty) return const [];
    return results.take(limit).toList(growable: false);
  }

  @override
  Future<MusicSearchResult?> resolveTrack(String trackId) async {
    for (final item in results) {
      if (item.id == trackId) return item;
    }
    return null;
  }

  @override
  Future<String?> resolveStreamUrl(MusicSearchResult item) async => item.streamUrl;
}

void main() {
  group('AggregatedMusicRepository', () {
    test('deduplicates same track across providers and prefers the stronger result', () async {
      final repo = AggregatedMusicRepository(
        sources: [
          _FakeSource(
            id: 'youtube',
            kind: MusicProviderKind.youtubeMusic,
            results: [
              const MusicSearchResult(
                id: 'track-1',
                title: 'Midnight City',
                artists: 'M83',
                providerId: 'youtube',
                sourceKind: MusicProviderKind.youtubeMusic,
                durationMs: 240000,
                score: 70,
                quality: 70,
              ),
            ],
          ),
          _FakeSource(
            id: 'backend',
            kind: MusicProviderKind.waveify,
            results: [
              const MusicSearchResult(
                id: 'track-1',
                title: 'Midnight City',
                artists: 'M83',
                providerId: 'backend',
                sourceKind: MusicProviderKind.waveify,
                durationMs: 240000,
                score: 92,
                quality: 90,
              ),
            ],
          ),
        ],
      );

      final found = await repo.search('midnight city', limit: 10);
      expect(found, hasLength(1));
      expect(found.single.providerId, 'backend');
      expect(found.single.score, 92);
    });

    test('falls back to the next source when the first one cannot resolve the stream', () async {
      final repo = AggregatedMusicRepository(
        sources: [
          _FakeSource(
            id: 'youtube',
            kind: MusicProviderKind.youtubeMusic,
            results: const [
              MusicSearchResult(
                id: 'track-2',
                title: 'Test',
                artists: 'Artist',
                providerId: 'youtube',
                sourceKind: MusicProviderKind.youtubeMusic,
                durationMs: 180000,
                streamUrl: null,
              ),
            ],
          ),
          _FakeSource(
            id: 'soundcloud',
            kind: MusicProviderKind.soundCloud,
            results: const [
              MusicSearchResult(
                id: 'track-2',
                title: 'Test',
                artists: 'Artist',
                providerId: 'soundcloud',
                sourceKind: MusicProviderKind.soundCloud,
                durationMs: 180000,
                streamUrl: 'https://example.com/stream.mp3',
              ),
            ],
          ),
        ],
      );

      final resolved = await repo.resolveStreamUrl(
        const MusicSearchResult(
          id: 'track-2',
          title: 'Test',
          artists: 'Artist',
          providerId: 'youtube',
          sourceKind: MusicProviderKind.youtubeMusic,
          durationMs: 180000,
          streamUrl: null,
        ),
      );

      expect(resolved, 'https://example.com/stream.mp3');
    });
  });
}
