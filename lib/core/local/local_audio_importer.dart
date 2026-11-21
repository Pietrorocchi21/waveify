import 'dart:io';
import 'dart:isolate';
import 'dart:convert';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';

import '../../models/track.dart';
import 'local_library_store.dart';

class AudioImportResult {
  const AudioImportResult(this.tracks, this.errors);
  final List<Track> tracks;
  final Map<String, String> errors;
}

class LocalAudioImporter {
  LocalAudioImporter(this.store);
  final LocalLibraryStore store;
  static const extensions = [
    'mp3',
    'm4a',
    'aac',
    'wav',
    'flac',
    'ogg',
    'opus',
    'aif',
    'aiff',
    'webm',
  ];
  Future<AudioImportResult> importPaths(List<String> paths) async {
    final imported = <Track>[];
    final errors = <String, String>{};
    for (final path in paths.toSet()) {
      try {
        final source = File(path);
        final name = source.uri.pathSegments.last;
        final extension = name.split('.').last.toLowerCase();
        if (!extensions.contains(extension)) {
          throw const FormatException('Unsupported audio file.');
        }
        if (!await source.exists() || await source.length() == 0) {
          throw const FormatException('Audio file is empty or missing.');
        }
        final digest = await sha256.bind(source.openRead()).first;
        final id = 'local-${digest.toString().substring(0, 32)}';
        final directory = await store.mediaDirectory;
        final target = File('${directory.path}/$id.$extension');
        if (!await target.exists()) {
          final temporary = await source.copy('${target.path}.part');
          await temporary.rename(target.path);
        }
        final metadata = await Isolate.run(() {
          try {
            final data = readMetadata(File(path), getImage: true);
            return <String, dynamic>{
              'title': data.title,
              'artist': data.artist,
              'album': data.album,
              'duration': data.duration?.inMilliseconds,
              'lyrics': data.lyrics,
              if (data.pictures.isNotEmpty)
                'picture': data.pictures.first.bytes,
              if (data.pictures.isNotEmpty)
                'pictureMime': data.pictures.first.mimetype,
            };
          } catch (_) {
            return <String, dynamic>{};
          }
        });
        final basename = name.substring(0, name.length - extension.length - 1);
        final parts = basename.split(' - ');
        final artist =
            '${metadata['artist'] ?? (parts.length > 1 ? parts.first : '')}'
                .trim();
        final title =
            '${metadata['title'] ?? (parts.length > 1 ? parts.skip(1).join(' - ') : basename)}'
                .trim();
        var cover = '';
        if (metadata['picture'] != null) {
          final file = File(
            '${directory.path}/$id.${metadata['pictureMime'] == 'image/png' ? 'png' : 'jpg'}',
          );
          await file.writeAsBytes(
            metadata['picture'] as List<int>,
            flush: true,
          );
          cover = file.uri.toString();
        } else {
          for (final candidate in [
            '${source.path.substring(0, source.path.length - extension.length)}jpg',
            '${source.parent.path}/cover.jpg',
            '${source.parent.path}/folder.jpg',
            '${source.parent.path}/cover.png',
          ]) {
            if (await File(candidate).exists()) {
              final file = await File(candidate).copy(
                '${directory.path}/$id-cover.${candidate.split('.').last}',
              );
              cover = file.uri.toString();
              break;
            }
          }
        }
        var lyrics = metadata['lyrics'] as String?;
        final sidecar = File(
          '${source.path.substring(0, source.path.length - extension.length)}lrc',
        );
        if (await sidecar.exists()) lyrics = await sidecar.readAsString();
        final artistId = artist.isEmpty
            ? null
            : 'artist-${sha256.convert(utf8.encode(artist.toLowerCase())).toString().substring(0, 16)}';
        final albumTitle = '${metadata['album'] ?? ''}'.trim();
        final albumId = albumTitle.isEmpty
            ? ''
            : 'album-${sha256.convert(utf8.encode('$artist|$albumTitle')).toString().substring(0, 16)}';
        final track = Track(
          id: id,
          title: title.isEmpty ? basename : title,
          artists: artist,
          artistId: artistId,
          artistList: artist.isEmpty
              ? []
              : [TrackArtist(id: artistId!, name: artist)],
          album: albumTitle.isEmpty
              ? null
              : TrackAlbum(id: albumId, title: albumTitle),
          durationMs: (metadata['duration'] as int?) ?? 0,
          coverUrl: cover,
          sourceUrl: target.uri.toString(),
        );
        await store.update((data) {
          (data['tracks'] as Map)[id] = {
            ...track.toSnapshot(),
            'localLyrics': ?lyrics,
          };
        });
        imported.add(track);
      } catch (error) {
        errors[path] = '$error';
      }
    }
    return AudioImportResult(imported, errors);
  }
}
