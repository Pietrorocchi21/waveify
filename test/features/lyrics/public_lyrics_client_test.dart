import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waveify/features/lyrics/public_lyrics_client.dart';
import 'package:waveify/models/lyrics.dart';
import 'package:waveify/models/track.dart';

void main() {
  const track = Track(
    id: 'local:1',
    title: 'Example',
    artists: 'Artist',
    durationMs: 180000,
  );

  Map<String, dynamic> record({
    String title = 'Example',
    int duration = 180,
    String? synced,
  }) => {
    'trackName': title,
    'artistName': 'Artist',
    'duration': duration,
    'plainLyrics': 'Synthetic example',
    'syncedLyrics': synced,
  };

  test(
    '404 searches strict matches and prefers synchronized text; caches result',
    () async {
      var requests = 0;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            if (options.path == '/api/get') {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(requestOptions: options, statusCode: 404),
                ),
              );
            } else {
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: [
                    record(title: 'Other', synced: '[00:01]Wrong'),
                    record(duration: 240, synced: '[00:01]Wrong recording'),
                    record(),
                    record(synced: '[00:01]Synthetic example'),
                  ],
                ),
              );
            }
          },
        ),
      );
      final client = PublicLyricsClient(client: dio);
      final result = await client.get(track);
      expect(result?.syncLevel, LyricsSyncLevel.lineLevel);
      expect(await client.get(track), same(result));
      expect(requests, 2);
      client.close();
    },
  );

  test('rejects wrong duration even from exact endpoint', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response(requestOptions: options, data: record(duration: 230)),
          );
        },
      ),
    );
    final client = PublicLyricsClient(client: dio);
    expect(await client.get(track), isNull);
    client.close();
  });

  test('instrumental recordings retain a distinct status', () async {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response(
              requestOptions: options,
              data: {...record(), 'plainLyrics': null, 'instrumental': true},
            ),
          );
        },
      ),
    );
    final client = PublicLyricsClient(client: dio);
    final result = await client.get(track);
    expect(result?.isInstrumental, isTrue);
    expect(result?.content, isEmpty);
    client.close();
  });

  test('active timestamp follows backward seeks and intro', () {
    const parsed = ParsedLyrics(
      syncedLines: [
        SyncedLine(timeMs: 1000, text: 'A'),
        SyncedLine(timeMs: 3000, text: 'B'),
      ],
    );
    expect(parsed.activeLineIndex(0), -1);
    expect(parsed.activeLineIndex(3000), 1);
    expect(parsed.activeLineIndex(1000), 0);
    expect(parsed.offset(500).activeLineIndex(1000), -1);
  });
}
