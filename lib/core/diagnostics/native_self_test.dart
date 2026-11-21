import '../../features/gallery/gallery_catalog.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';
import 'package:media_kit/media_kit.dart' as media;

import '../local/local_library_store.dart';
import '../cloud/cloud_config.dart';
import '../local/local_audio_importer.dart';
import '../local/local_api_client.dart';
import '../network/waveify_api.dart';

/// Runs in the actual packaged Windows process, exercising its native decoder
/// and its real device-library files. No account, network or user media needed.
Future<bool> runNativeSelfTest(String output, {String? videoPath}) async {
  final report = <String, dynamic>{
    'status': 'failed',
    'platform': Platform.operatingSystem,
    'cloud_configured': CloudConfig.isConfigured,
    'checks': <String, dynamic>{},
  };
  final checks = report['checks'] as Map<String, dynamic>;
  final directory = await Directory.systemTemp.createTemp('waveify-self-test-');
  AudioPlayer? player;
  try {
    const rate = 16000;
    final bytes = ByteData(44 + rate * 2);
    void ascii(int offset, String text) {
      for (var i = 0; i < text.length; i++) {
        bytes.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    bytes.setUint32(4, bytes.lengthInBytes - 8, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little);
    bytes.setUint32(24, rate, Endian.little);
    bytes.setUint32(28, rate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    bytes.setUint32(40, rate * 2, Endian.little);
    for (var i = 0; i < rate; i++) {
      bytes.setInt16(
        44 + i * 2,
        (math.sin(i / rate * 440 * 2 * math.pi) * 2000).round(),
        Endian.little,
      );
    }
    final input = File('${directory.path}/Waveify - Native decoder.wav');
    await input.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    final store = LocalLibraryStore(
      directory: Directory('${directory.path}/library'),
    );
    final imported = await LocalAudioImporter(store).importPaths([input.path]);
    if (imported.tracks.length != 1 || imported.errors.isNotEmpty) {
      throw StateError('Audio import failed: ${imported.errors}');
    }
    final track = imported.tracks.single;
    checks['audio_import'] = 'passed';
    final api = WaveifyApi(LocalApiClient(store));
    await api.likeTrack(track.id, snapshot: track);
    final playlist = await api.createPlaylist(title: 'Native self-test');
    await api.addPlaylistTrack(playlist.id, track.id, snapshot: track);
    final reopened = WaveifyApi(
      LocalApiClient(
        LocalLibraryStore(directory: Directory('${directory.path}/library')),
      ),
    );
    final saved = await reopened.getUserPlaylist(playlist.id);
    if (saved.$2.length != 1 ||
        (await reopened.listLikedTracks()).items.length != 1) {
      throw StateError('Persistence verification failed.');
    }
    checks['library_persistence'] = 'passed';
    player = AudioPlayer();
    final duration = await player
        .setFilePath(Uri.parse(track.sourceUrl).toFilePath())
        .timeout(const Duration(seconds: 25));
    if (duration == null || duration.inMilliseconds < 900) {
      throw StateError(
        'Native WAV decoder did not load the expected duration.',
      );
    }
    await player.setVolume(0.5);
    await player.setSpeed(1.1);
    await player.seek(const Duration(milliseconds: 250));
    checks['native_audio_decode'] = 'passed';
    checks['duration_ms'] = duration.inMilliseconds;
    checks['native_transport'] = 'passed';
    if (videoPath != null) {
      var rejected = false;
      try {
        await player
            .setFilePath('${directory.path}/missing-source.mp4')
            .timeout(const Duration(seconds: 5));
      } on PlayerException {
        rejected = true;
      }
      if (!rejected) {
        throw StateError('Native player accepted a missing source.');
      }
      final recovered = await player
          .setFilePath(input.path)
          .timeout(const Duration(seconds: 10));
      if (recovered == null || recovered.inMilliseconds < 900) {
        throw StateError('Native player did not recover after a failed open.');
      }
      checks['native_audio_open_recovery'] = 'passed';
      final video = media.Player(
        configuration: const media.PlayerConfiguration(vo: 'null'),
      );
      try {
        await video.setVolume(0);
        await video.setVideoTrack(media.VideoTrack.auto());
        await video
            .open(media.Media(File(videoPath).uri.toString()), play: false)
            .timeout(const Duration(seconds: 10));
        await video.setAudioTrack(media.AudioTrack.no());
        final advancing = video.stream.position.firstWhere(
          (position) => position >= const Duration(milliseconds: 200),
        );
        await video.play();
        await advancing.timeout(const Duration(seconds: 8));
        if ((video.state.width ?? 0) < 1 || (video.state.height ?? 0) < 1) {
          throw StateError('Native decoder did not report a video frame.');
        }
        checks['native_muted_video'] = 'passed';
      } finally {
        await video.dispose().timeout(const Duration(seconds: 5));
      }
    }
    final demo = await loadDemoAlbum(demoAlbums.first);
    final demoDuration = await player
        .setAudioSource(
          AudioSource.uri(Uri.parse(demo.tracks.single.sourceUrl)),
        )
        .timeout(const Duration(seconds: 10));
    if (demoDuration == null || demoDuration.inMilliseconds < 5900) {
      throw StateError(
        'Native player could not decode the bundled gallery sample.',
      );
    }
    checks['gallery_demo_decode'] = 'passed';
    report['status'] = 'passed';
  } catch (error, stack) {
    report['error'] = '$error';
    report['stack'] = '$stack';
  } finally {
    try {
      await player?.dispose().timeout(const Duration(seconds: 8));
    } catch (error) {
      report['dispose_error'] = '$error';
    }
    try {
      await directory.delete(recursive: true);
    } catch (_) {}
    final file = File(output);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );
  }
  return report['status'] == 'passed';
}
