import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A device library with serialized, atomic writes. This is real user data,
/// separate from cloud accounts and from the offline download cache.
class LocalLibraryStore {
  LocalLibraryStore({this._directory});
  final Directory? _directory;
  Future<void> _tail = Future.value();
  Future<File> get databaseFile async {
    final root =
        _directory ??
        Directory('${(await getApplicationDocumentsDirectory()).path}/waveify');
    await root.create(recursive: true);
    return File('${root.path}/library.json');
  }

  Future<Directory> get mediaDirectory async {
    final file = await databaseFile;
    return Directory('${file.parent.path}/media')..createSync(recursive: true);
  }

  static Map<String, dynamic> empty() => {
    'version': 1,
    'tracks': <String, dynamic>{},
    'liked': <String, dynamic>{},
    'playlists': <String, dynamic>{},
    'history': <dynamic>[],
    'collections': <String, dynamic>{},
    'user': {
      'id': 'local',
      'username': 'local',
      'displayName': 'Waveify',
      'isPublic': false,
    },
  };
  Future<Map<String, dynamic>> _read() async {
    final file = await databaseFile;
    if (!await file.exists()) return empty();
    final data = jsonDecode(await file.readAsString());
    if (data is! Map || data['version'] != 1) {
      throw const FormatException('Unsupported or damaged local library.');
    }
    return Map<String, dynamic>.from(data);
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<T> read<T>(T Function(Map<String, dynamic>) action) =>
      _serialized(() async => action(await _read()));
  Future<T> update<T>(T Function(Map<String, dynamic>) action) =>
      _serialized(() async {
        final data = await _read();
        final result = action(data);
        final file = await databaseFile;
        final temp = File('${file.path}.tmp');
        await temp.writeAsString(jsonEncode(data), flush: true);
        await temp.rename(file.path);
        return result;
      });
}
