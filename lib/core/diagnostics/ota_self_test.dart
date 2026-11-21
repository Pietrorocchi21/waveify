import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../local/local_api_client.dart';
import '../local/local_library_store.dart';
import '../network/waveify_api.dart';
import '../platform/updater_service.dart';
import '../../models/track.dart';

/// Seed real device data and run the production update helper on a disposable
/// CI installation. These diagnostic flags are never used by normal startup.
Future<bool> startOtaSelfTest({
  required String installerPath,
  required String hash,
  required String targetExecutable,
  required String reportPath,
  required String startupPath,
}) async {
  final id = 'waveify-ota-test-${const Uuid().v4()}';
  final store = LocalLibraryStore();
  final api = WaveifyApi(LocalApiClient(store));
  final track = Track(
    id: id,
    title: 'OTA preservation test',
    artists: 'Waveify',
  );
  await api.likeTrack(track.id, snapshot: track);
  final playlist = await api.createPlaylist(title: id);
  await api.addPlaylistTrack(playlist.id, track.id, snapshot: track);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('waveify_ota_self_test', id);
  final expected = File('$reportPath.expected.json');
  await expected.writeAsString(
    jsonEncode({'trackId': id, 'playlistId': playlist.id}),
  );
  final installer = File(installerPath);
  final helper = await UpdaterService.instance.writeInstallerHelper(
    installer,
    UpdateManifest(
      UpdaterService.appVersion,
      Uri.parse(
        'https://github.com/Pietrorocchi21/waveify/releases/download/test/Waveify-windows.exe',
      ),
      hash,
      await installer.length(),
      'Native update test',
    ),
    executable: targetExecutable,
    parentPid: pid,
    restartArguments: [
      '--ota-verify-state=$reportPath',
      '--startup-report=$startupPath',
    ],
  );
  await UpdaterService.instance.launchInstallerHelper(helper);
  return true;
}

Future<void> verifyOtaSelfTest(String reportPath) async {
  final expected = File('$reportPath.expected.json');
  final data =
      jsonDecode(await expected.readAsString()) as Map<String, dynamic>;
  final store = LocalLibraryStore();
  final id = data['trackId'] as String, playlist = data['playlistId'] as String;
  final prefs = await SharedPreferences.getInstance();
  final retained = await store.read(
    (state) =>
        (state['tracks'] as Map).containsKey(id) &&
        (state['liked'] as Map).containsKey(id) &&
        (state['playlists'] as Map).containsKey(playlist),
  );
  final passed = retained && prefs.getString('waveify_ota_self_test') == id;
  await store.update((state) {
    (state['tracks'] as Map).remove(id);
    (state['liked'] as Map).remove(id);
    (state['playlists'] as Map).remove(playlist);
  });
  await prefs.remove('waveify_ota_self_test');
  await expected.delete();
  await File(reportPath).writeAsString(
    jsonEncode({
      'status': passed ? 'passed' : 'failed',
      'version': UpdaterService.appVersion,
      'library_preserved': retained,
      'settings_preserved': passed,
    }),
    flush: true,
  );
}
