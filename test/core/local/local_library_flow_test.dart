import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:waveify/core/local/local_api_client.dart';
import 'package:waveify/core/local/local_audio_importer.dart';
import 'package:waveify/core/local/local_library_store.dart';
import 'package:waveify/core/media/innertube/stream_resolver.dart';
import 'package:waveify/core/network/api_exception.dart';
import 'package:waveify/core/network/waveify_api.dart';
import 'package:waveify/models/track.dart';

/// A real, mono 8 kHz PCM WAV, with a distinct sample for each fixture.
List<int> tinyWav([int sample = 0]) {
  final data = ByteData(60);
  void text(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      data.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  data.setUint32(4, 52, Endian.little);
  text(8, 'WAVEfmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 8000, Endian.little);
  data.setUint32(28, 16000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, 16, Endian.little);
  data.setInt16(44, sample, Endian.little);
  return data.buffer.asUint8List();
}

void main() {
  late Directory temporary;
  late Directory library;
  late LocalLibraryStore store;
  late LocalApiClient client;
  late WaveifyApi api;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('waveify-local-flow-');
    library = Directory('${temporary.path}/library');
    store = LocalLibraryStore(directory: library);
    client = LocalApiClient(store);
    api = WaveifyApi(client);
  });
  tearDown(() async => temporary.delete(recursive: true));

  Future<File> wav(String name, [int sample = 0]) =>
      File('${temporary.path}/$name.wav').writeAsBytes(tinyWav(sample));

  test(
    'imports real audio, deduplicates and persists metadata and sidecar',
    () async {
      final source = await wav('Example Artist - A Song');
      const lyrics = '[00:00.00]A local lyric\n[00:01.00]Second line';
      await File('${temporary.path}/Example Artist - A Song.lrc')
          .writeAsString(lyrics);
      final importer = LocalAudioImporter(store);
      final imported = await importer.importPaths([source.path, source.path]);
      expect(imported.errors, isEmpty);
      expect(imported.tracks, hasLength(1));
      final track = imported.tracks.single;
      expect(track.title, 'A Song');
      expect(track.artists, 'Example Artist');
      expect(track.artistList?.single.name, 'Example Artist');
      expect(track.sourceUrl, startsWith('file:'));
      expect(
        await File.fromUri(Uri.parse(track.sourceUrl)).readAsBytes(),
        tinyWav(),
      );
      expect(
        (await importer.importPaths([source.path])).tracks.single.id,
        track.id,
      );
      expect(await store.read((data) => (data['tracks'] as Map).length), 1);
      await api.likeTrack(track.id, snapshot: track);

      // Remove original input to prove playback relies on the managed copy.
      await source.delete();
      final reopenedClient = LocalApiClient(
        LocalLibraryStore(directory: library),
      );
      final reopened = WaveifyApi(reopenedClient);
      final restored = await reopened.getTrack(track.id);
      expect(restored.title, track.title);
      expect(restored.artists, track.artists);
      expect(restored.artistList, track.artistList);
      expect(restored.sourceUrl, track.sourceUrl);
      expect((await reopened.listLikedTracks()).items.single.$1.id, track.id);
      expect(
        (await reopened.search('EXAMPLE song')).single.track?.id,
        track.id,
      );
      expect(await reopened.search('absent'), isEmpty);
      expect((await reopened.getTrackStream(track.id))['url'], track.sourceUrl);
      final response = await reopenedClient.stream(
        '/v1/tracks/${track.id}/lyrics',
      );
      final events = utf8.decode(
        await response.stream.expand((chunk) => chunk).toList(),
      );
      expect(events, contains('local'));
      expect(events, contains('A local lyric'));
      expect(events, contains('"type":"done"'));
      await reopened.unlikeTrack(track.id);
      expect((await reopened.listLikedTracks()).items, isEmpty);
    },
  );

  test(
    'rejects empty, missing and unsupported imports without adding tracks',
    () async {
      final empty = await File('${temporary.path}/empty.wav').create();
      final unsupported = await File('${temporary.path}/notes.txt')
          .writeAsString('text');
      final missing = '${temporary.path}/missing.wav';
      final result = await LocalAudioImporter(store)
          .importPaths([empty.path, unsupported.path, missing]);
      expect(result.tracks, isEmpty);
      expect(
        result.errors.keys,
        unorderedEquals([empty.path, unsupported.path, missing]),
      );
      expect(await store.read((data) => data['tracks']), isEmpty);
    },
  );

  test('playlist bulk add, revision conflicts, reorder and deletion survive reopen', () async {
    final first = await wav('Artist - First', 1);
    final second = await wav('Artist - Second', 2);
    final imported = await LocalAudioImporter(store)
        .importPaths([first.path, second.path]);
    expect(imported.errors, isEmpty);
    final playlist = await api.createPlaylist(
      title: 'Local queue',
      isPublic: true,
    );
    expect(playlist.ownerId, 'local');
    expect(playlist.isPublic, isFalse);
    expect(await api.addPlaylistTracks(playlist.id, imported.tracks), (
      added: 2,
      rejected: 0,
    ));
    final loaded = await api.getUserPlaylist(playlist.id);
    expect(
      loaded.$2.map((item) => item.track.id),
      imported.tracks.map((track) => track.id),
    );
    final moved = await api.movePlaylistItem(
      playlist.id,
      loaded.$2.last.id,
      loaded.$2.first.id,
      loaded.$1.revision,
    );
    expect(moved.$2.map((item) => item.track.title), ['Second', 'First']);
    expect(moved.$2.map((item) => item.position), [0, 1]);
    await expectLater(
      api.movePlaylistItem(
        playlist.id,
        moved.$2.first.id,
        null,
        loaded.$1.revision,
      ),
      throwsA(
        isA<ApiException>().having((error) => error.status, 'status', 409),
      ),
    );
    final reopened = WaveifyApi(
      LocalApiClient(LocalLibraryStore(directory: library)),
    );
    final saved = await reopened.getUserPlaylist(playlist.id);
    expect(saved.$1.revision, moved.$1.revision);
    expect(saved.$2.map((item) => item.track.title), ['Second', 'First']);
    expect(saved.$2.first.track.sourceUrl, imported.tracks.last.sourceUrl);
    await reopened.removePlaylistItem(playlist.id, saved.$2.first.id);
    expect((await reopened.getUserPlaylist(playlist.id)).$2.single.position, 0);
    await reopened.deletePlaylist(playlist.id);
    expect(await reopened.listPlaylists(), isEmpty);
    await expectLater(
      reopened.getUserPlaylist(playlist.id),
      throwsA(
        isA<ApiException>().having((error) => error.status, 'status', 404),
      ),
    );
  });

  test(
    'resolves actual files and direct URLs and rejects unknown sources',
    () async {
      final source = await wav('Playable');
      final resolver = StreamResolver();
      expect(
        (await resolver.resolveDirectAudioStream(source.uri.toString())).url,
        source.uri.toString(),
      );
      expect(
        (await resolver.resolveTrackStream(
          Track(
            id: 'local-id',
            title: 'Playable',
            sourceUrl: source.uri.toString(),
          ),
        )).mimeType,
        'audio/wav',
      );
      const direct = 'https://audio.example.test/song.flac?token=example';
      expect((await resolver.resolveDirectAudioStream(direct)).url, direct);
      await expectLater(
        resolver.resolveDirectAudioStream('unknown-provider-source'),
        throwsA(
          isA<InnertubeException>().having(
            (error) => error.statusCode,
            'status',
            501,
          ),
        ),
      );
      await expectLater(
        resolver.resolveDirectAudioStream('${temporary.path}/missing.wav'),
        throwsA(
          isA<InnertubeException>().having(
            (error) => error.statusCode,
            'status',
            404,
          ),
        ),
      );
    },
  );
  test(
    'search retains playable metadata and imported artist and album details',
    () async {
      final file = await wav('Artist - Title');
      final track = Track(
        id: 'local-search',
        title: 'Title',
        artists: 'Artist',
        artistList: const [TrackArtist(id: 'artist-local', name: 'Artist')],
        album: const TrackAlbum(id: 'album-local', title: 'My Album'),
        durationMs: 1000,
        sourceUrl: file.uri.toString(),
      );
      await store.update((data) {
        (data['tracks'] as Map)[track.id] = track.toSnapshot();
      });
      final found = (await api.search('Title', type: 'track')).single;
      expect(found.track?.sourceUrl, file.uri.toString());
      expect(found.track?.artists, 'Artist');
      expect(found.track?.durationMs, 1000);
      expect(
        (await api.search('Artist', type: 'artist')).single.name,
        'Artist',
      );
      expect((await api.getArtist('artist-local')).tracks.single.id, track.id);
      expect((await api.getAlbum('album-local')).tracks.single.id, track.id);
      await api.saveCollection('albums', 'album-local');
      expect(
        (await api.listSavedCollections('albums')).single.title,
        'My Album',
      );
    },
  );
}
