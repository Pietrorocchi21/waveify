import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waveify/core/media/audius/audius_catalog.dart';
import 'package:waveify/core/media/innertube/stream_resolver.dart';
import 'package:waveify/models/track.dart';

class Adapter implements HttpClientAdapter {
  Adapter(this.reply);
  final ResponseBody Function(RequestOptions) reply;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async => reply(options);
  @override
  void close({bool force = false}) {}
}
ResponseBody response(Object data) => ResponseBody.fromString(jsonEncode({'data': data}), 200,
  headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
Map<String, dynamic> song(String id, {bool gated = false}) => {
  'id': id, 'title': 'A real recording', 'duration': 123,
  'is_streamable': true, 'is_stream_gated': gated, 'is_downloadable': false,
  'user': {'id': 'artist', 'name': 'Independent artist'},
  'artwork': {'480x480': 'https://art.example/cover.jpg'},
};

void main() {
  test('online search filters gated tracks and preserves playback/download metadata', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.audius.co'));
    dio.httpClientAdapter = Adapter((request) {
      expect(request.headers['User-Agent'], AudiusCatalog.userAgent);
      expect(request.queryParameters['app_name'], 'WAVEIFY');
      return response([song('allowed'), song('locked', gated: true)]);
    });
    final catalog = AudiusCatalog(client: dio);
    final items = await catalog.search('recording');
    expect(items, hasLength(1));
    final track = items.single.track!;
    expect(track.id, 'audius:allowed');
    expect(track.sourceUrl, contains('/v1/tracks/allowed/stream'));
    expect(track.durationMs, 123000);
    expect(track.downloadable, isFalse);
    expect(Track.fromJson(track.toSnapshot()).downloadable, isFalse);
    expect(track.copyWith(title: 'Renamed').downloadable, isFalse);
    catalog.close();
  });

  test('stream resolves fresh metadata and requests only a byte range', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.audius.co'));
    var ranges = 0;
    dio.httpClientAdapter = Adapter((request) {
      if (request.uri.path.endsWith('/stream')) {
        expect(request.headers['Range'], 'bytes=0-0');
        ranges++;
        return ResponseBody.fromBytes([0], 206, headers: {Headers.contentTypeHeader: ['audio/mpeg']});
      }
      return response(song('allowed'));
    });
    final catalog = AudiusCatalog(client: dio);
    final resolver = StreamResolver(audius: catalog);
    final resolved = await resolver.resolveTrackStream(const Track(id: 'audius:allowed', title: 'Title'));
    expect(resolved.mimeType, 'audio/mpeg');
    expect(resolved.durationMs, 123000);
    expect(resolved.headers['User-Agent'], AudiusCatalog.userAgent);
    expect(ranges, 1);
    catalog.close();
  });

  test('unavailable or newly gated media is rejected before reading any audio', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.audius.co'));
    dio.httpClientAdapter = Adapter((request) {
      expect(request.uri.path, '/v1/tracks/locked');
      return response(song('locked', gated: true));
    });
    final catalog = AudiusCatalog(client: dio);
    await expectLater(catalog.resolveStream('audius:locked'), throwsA(isA<InnertubeException>()));
    catalog.close();
  });
}
