import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waveify/core/network/api_client.dart';
import 'package:waveify/core/network/api_exception.dart';

/// A [HttpClientAdapter] that answers with a canned response and records what
/// was sent.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({this.status = 200, this.body = const {'ok': true}});

  final int status;
  final Object body;

  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        'date': [DateTime.now().toUtc().toString()],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('ApiClient', () {
    test('completes a GET request', () async {
      final adapter = _FakeAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
        ..httpClientAdapter = adapter;

      final client = ApiClient(dio: dio);

      final response = await client
          .request('/v1/explore/popular', query: {'window': '7d'})
          .timeout(const Duration(seconds: 5));

      expect(response, isA<Map<String, dynamic>>());
      expect(adapter.requests, hasLength(1));
    });

    test('completes two sequential GET requests', () async {
      // Regression: the in-flight de-duplication used to deadlock, because
      // the `whenComplete` callback returned the future it was removing.
      final adapter = _FakeAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
        ..httpClientAdapter = adapter;

      final client = ApiClient(dio: dio);

      await client
          .request('/v1/me')
          .timeout(const Duration(seconds: 5));
      await client
          .request('/v1/me')
          .timeout(const Duration(seconds: 5));

      expect(adapter.requests, hasLength(2));
    });

    test('de-duplicates concurrent GET requests', () async {
      final adapter = _FakeAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
        ..httpClientAdapter = adapter;

      final client = ApiClient(dio: dio);

      await Future.wait([
        client.request('/v1/me').timeout(const Duration(seconds: 5)),
        client.request('/v1/me').timeout(const Duration(seconds: 5)),
      ]);

      expect(adapter.requests, hasLength(1));
    });

    test('adds standard request metadata', () async {
      final adapter = _FakeAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
        ..httpClientAdapter = adapter;

      final client = ApiClient(dio: dio);
      await client.request('/v1/me').timeout(const Duration(seconds: 5));

      final headers = adapter.requests.single.headers;
      expect(headers['x-client-version'], isNotEmpty);
      expect(headers['x-platform'], isNotEmpty);
      expect(headers['x-request-id'], isNotEmpty);
    });

    test('preserves the query string', () async {
      final adapter = _FakeAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
        ..httpClientAdapter = adapter;

      final client = ApiClient(dio: dio);
      await client
          .request('/v1/search', query: {'q': 'daft punk'})
          .timeout(const Duration(seconds: 5));

      final options = adapter.requests.single;
      expect(options.uri.queryParameters['q'], 'daft punk');
    });

    test('sends the body of a POST request', () async {
      final adapter = _FakeAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
        ..httpClientAdapter = adapter;

      final client = ApiClient(dio: dio);
      await client
          .request(
            '/v1/me/playlists',
            method: 'POST',
            body: {'title': 'Favorites'},
          )
          .timeout(const Duration(seconds: 5));

      final options = adapter.requests.single;
      expect(options.method, 'POST');
      expect(options.data, {'title': 'Favorites'});
      expect(options.headers['content-type'], contains('application/json'));
    });

    test('turns a server error into an exception', () async {
      final adapter = _FakeAdapter(status: 500, body: const {'message': 'boom'});
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
        ..httpClientAdapter = adapter;

      final client = ApiClient(dio: dio);

      await expectLater(
        client.request('/v1/me').timeout(const Duration(seconds: 5)),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
