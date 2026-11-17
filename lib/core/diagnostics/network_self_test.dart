import 'dart:convert';
import 'dart:io';

import 'package:just_audio/just_audio.dart';

import '../media/audius/audius_catalog.dart';
import '../../features/lyrics/public_lyrics_client.dart';
import '../../features/lyrics/lyrics_parser.dart';
import '../../models/track.dart';

/// Real public-network decode and timestamp checks in the packaged native app.
/// Does not retain songs, print lyrics, or require a user account.
Future<bool> runNetworkSelfTest(String output) async {
  final report = <String, dynamic>{
    'status': 'failed',
    'checks': <String, dynamic>{},
  };
  final checks = report['checks'] as Map<String, dynamic>;
  final catalog = AudiusCatalog();
  final lyrics = PublicLyricsClient();
  final player = AudioPlayer();
  var stage = 'online_search';
  try {
    final results = await catalog.search('chill', type: 'track');
    if (results.isEmpty) throw StateError('No public streaming results.');
    checks[stage] = 'passed';
    stage = 'native_stream_decode';
    final track = results.first.track!;
    final stream = await catalog.resolveStream(track.id);
    final duration = await player
        .setUrl(stream.url, headers: stream.headers)
        .timeout(const Duration(seconds: 40));
    if (duration == null || duration.inSeconds < 5) {
      throw StateError('No streamed duration.');
    }
    await player
        .seek(const Duration(seconds: 2))
        .timeout(const Duration(seconds: 10));
    checks[stage] = 'passed';
    checks['stream_duration_ms'] = duration.inMilliseconds;
    stage = 'public_synced_lyrics';
    final candidate = await lyrics.get(
      const Track(
        id: 'lyrics-network-test',
        title: 'Yellow',
        artists: 'Coldplay',
        durationMs: 267000,
      ),
    );
    if (candidate == null) throw StateError('No timed lyrics returned.');
    final parsed = LyricsParser.parse(
      candidate.content,
      format: candidate.format.raw,
      songDurationMs: 267000,
    );
    if (parsed.syncedLines.length < 5) {
      throw StateError('Lyrics have no timestamps.');
    }
    checks[stage] = 'passed';
    checks['synced_line_count'] = parsed.syncedLines.length;
    final index = parsed.syncedLines.length ~/ 2;
    final position = parsed.syncedLines[index].timeMs;
    if (parsed.activeLineIndex(position) < 0) {
      throw StateError('No active lyric after seeking.');
    }
    checks['lyrics_seek_lookup'] = 'passed';
    report['status'] = 'passed';
  } catch (error) {
    report['failed_stage'] = stage;
    report['error_type'] = '${error.runtimeType}';
  } finally {
    catalog.close();
    lyrics.close();
    await player.dispose();
    final file = File(output);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );
  }
  return report['status'] == 'passed';
}
