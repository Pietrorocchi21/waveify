import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waveify/core/network/api_client.dart';
import 'package:waveify/core/network/api_exception.dart';

void main() {
  late HttpServer server;
  late Dio dio;
  late ApiClient client;
  late List<String?> authorizations;
  late String token;
  late int refreshCount;

  setUp(() async {
    authorizations = [];
    token = 'expired';
    refreshCount = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final authorization = request.headers.value('authorization');
      authorizations.add(authorization);
      request.response.headers.contentType = ContentType.json;
      if (authorization == 'Bearer fresh') {
        request.response.write('{"ok":true}');
      } else {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.write('{"message":"Token expired"}');
      }
      await request.response.close();
    });
    dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}'));
    client = ApiClient(
      dio: dio,
      tokenProvider: () async => token,
      onRefreshSession: () async {
        refreshCount++;
        token = 'fresh';
        return true;
      },
    );
  });

  tearDown(() async {
    dio.close(force: true);
    await server.close(force: true);
  });

  test('a 401 refreshes the session and retries with the new token', () async {
    expect(await client.request('/v1/tracks'), {'ok': true});
    expect(refreshCount, 1);
    expect(authorizations, ['Bearer expired', 'Bearer fresh']);
  });

  test('disabled refresh returns unauthorized without retrying', () async {
    await expectLater(
      client.request('/v1/tracks', allowRefresh: false),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
    );
    expect(refreshCount, 0);
    expect(authorizations, ['Bearer expired']);
  });

  test('authentication endpoints do not recursively refresh', () async {
    await expectLater(
      client.request('/v1/auth/login', method: 'POST'),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
    );
    expect(refreshCount, 0);
    expect(authorizations, ['Bearer expired']);
  });
}
