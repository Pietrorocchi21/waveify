import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A track that is available offline.
class DownloadedTrack {
  const DownloadedTrack({
    required this.trackId,
    required this.title,
    this.artists = '',
    this.album = '',
    this.coverUrl = '',
    required this.filePath,
    this.sizeBytes = 0,
    this.durationMs = 0,
    required this.downloadedAt,
  });

  factory DownloadedTrack.fromJson(Map<String, dynamic> json) {
    return DownloadedTrack(
      trackId: '${json['trackId'] ?? ''}',
      title: '${json['title'] ?? ''}',
      artists: '${json['artists'] ?? ''}',
      album: '${json['album'] ?? ''}',
      coverUrl: '${json['coverUrl'] ?? ''}',
      filePath: '${json['filePath'] ?? ''}',
      sizeBytes: (json['sizeBytes'] as num?)?.round() ?? 0,
      durationMs: (json['durationMs'] as num?)?.round() ?? 0,
      downloadedAt: DateTime.tryParse('${json['downloadedAt'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final String trackId;
  final String title;
  final String artists;
  final String album;
  final String coverUrl;
  final String filePath;
  final int sizeBytes;
  final int durationMs;
  final DateTime downloadedAt;

  Map<String, dynamic> toJson() => {
        'trackId': trackId,
        'title': title,
        'artists': artists,
        'album': album,
        'coverUrl': coverUrl,
        'filePath': filePath,
        'sizeBytes': sizeBytes,
        'durationMs': durationMs,
        'downloadedAt': downloadedAt.toIso8601String(),
      };

  bool get exists => File(filePath).existsSync();
}

/// Keeps the list of the tracks that are available offline.
///
/// The manifest is a JSON file in the application documents directory, so it
/// works the same on every platform without a native database.
class DownloadsStore {
  DownloadsStore({Directory? directory}) : _override = directory;

  static const String _manifestName = 'downloads.json';
  static const String _audioFolder = 'offline';

  final Directory? _override;

  Directory? _documents;

  Future<Directory> _documentsDirectory() async {
    final cached = _documents;
    if (cached != null) return cached;
    final directory = _override ?? await getApplicationDocumentsDirectory();
    _documents = directory;
    return directory;
  }

  /// The folder where the audio files are stored.
  Future<Directory> audioDirectory() async {
    final documents = await _documentsDirectory();
    final directory = Directory('${documents.path}/$_audioFolder');
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<File> _manifestFile() async {
    final documents = await _documentsDirectory();
    return File('${documents.path}/$_manifestName');
  }

  /// The tracks that are available offline.
  Future<List<DownloadedTrack>> load() async {
    try {
      final file = await _manifestFile();
      if (!file.existsSync()) return const [];
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final tracks = decoded
          .whereType<Map>()
          .map((e) => DownloadedTrack.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      // The files can be removed outside the app: they are dropped.
      return tracks.where((t) => t.exists).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _save(List<DownloadedTrack> tracks) async {
    try {
      final file = await _manifestFile();
      await file.writeAsString(
        jsonEncode([for (final track in tracks) track.toJson()]),
      );
    } catch (_) {
      // A manifest that cannot be written is not fatal.
    }
  }

  /// Adds or replaces a downloaded track.
  Future<void> upsert(DownloadedTrack track) async {
    final tracks = [...await load()];
    tracks.removeWhere((t) => t.trackId == track.trackId);
    tracks.insert(0, track);
    await _save(tracks);
  }

  /// Removes a downloaded track and its file.
  Future<void> remove(String trackId) async {
    final tracks = [...await load()];
    final target = tracks.where((t) => t.trackId == trackId).firstOrNull;
    tracks.removeWhere((t) => t.trackId == trackId);
    await _save(tracks);
    if (target != null) {
      try {
        final file = File(target.filePath);
        if (file.existsSync()) await file.delete();
      } catch (_) {}
    }
  }

  /// The local file of a downloaded track, if any.
  Future<DownloadedTrack?> find(String trackId) async {
    final tracks = await load();
    for (final track in tracks) {
      if (track.trackId == trackId) return track;
    }
    return null;
  }

  /// The total size of the downloaded files.
  Future<int> totalSize() async {
    final tracks = await load();
    return tracks.fold<int>(0, (sum, t) => sum + t.sizeBytes);
  }
}
