import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waveify/core/platform/updater_service.dart';

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.respond);
  final ResponseBody Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond(options);
  @override
  void close({bool force = false}) {}
}

void main() {
  final bytes = utf8.encode('fake installer content for integrity tests');
  Map<String, Object> manifest() => {
    'schemaVersion': 1,
    'version': '1.1.0+2',
    'platform': 'windows-x64',
    'url': 'https://github.com/Pietrorocchi21/waveify/releases/download/v1.1.0%2B2/Waveify.exe',
    'sha256': sha256.convert(bytes).toString(),
    'size': bytes.length,
    'notes': 'Release notes',
  };
  late Directory cache;
  setUp(() async {
    cache = await Directory.systemTemp.createTemp('waveify-updater-test');
  });
  tearDown(() async {
    await cache.delete(recursive: true);
  });

  UpdaterService service({
    List<int>? asset,
    Map<String, Object>? metadata,
    Future<void> Function(File, UpdateManifest)? install,
  }) {
    final dio = Dio();
    dio.httpClientAdapter = FakeAdapter((request) {
      if (request.uri.path.endsWith('update.json')) {
        return ResponseBody.fromString(jsonEncode(metadata ?? manifest()), 200);
      }
      return ResponseBody.fromBytes(asset ?? bytes, 200);
    });
    return UpdaterService(
      dio: dio,
      platform: 'windows',
      currentVersion: '1.0.0+1',
      cacheDirectory: () async => cache,
      installHook: install,
    );
  }

  test('checks, streams and verifies before allowing installation', () async {
    var installed = false;
    final updater = service(
      install: (file, metadata) async {
        expect(await file.readAsBytes(), bytes);
        expect(metadata.version, '1.1.0+2');
        installed = true;
      },
    );
    final states = <UpdateState>[];
    updater.addListener(() => states.add(updater.state));
    expect((await updater.check()).state, UpdateState.available);
    expect(await updater.download(), isTrue);
    expect(updater.state, UpdateState.downloaded);
    expect(updater.progress, 1);
    expect(await updater.install(), isTrue);
    expect(installed, isTrue);
    expect(
      states,
      containsAllInOrder([
        UpdateState.checking,
        UpdateState.available,
        UpdateState.downloading,
        UpdateState.downloaded,
        UpdateState.installing,
      ]),
    );
  });

  test(
    'rejects corrupted and oversized assets without retaining partial data',
    () async {
      for (final asset in [
        List.filled(bytes.length, 0),
        [...bytes, 0],
      ]) {
        final updater = service(asset: asset);
        await updater.check();
        expect(await updater.download(), isFalse);
        expect(updater.state, UpdateState.error);
        expect(
          await Directory('${cache.path}/updates').list().toList(),
          isEmpty,
        );
      }
    },
  );

  test('rehashes verified cached installer before installation', () async {
    var installed = false;
    final updater = service(
      install: (_, _) async {
        installed = true;
      },
    );
    await updater.check();
    await updater.download();
    final file = await Directory('${cache.path}/updates').list().first as File;
    await file.writeAsBytes(List.filled(bytes.length, 0));
    expect(await updater.install(), isFalse);
    expect(installed, isFalse);
    expect(updater.state, UpdateState.error);
  });

  test(
    'preserves a verified installer and reuses it after another check',
    () async {
      final updater = service();
      await updater.check();
      expect(await updater.download(), isTrue);
      final cached = service(asset: [0]);
      await cached.check();
      expect(await cached.download(), isTrue);
      expect(cached.state, UpdateState.downloaded);
    },
  );

  test(
    'rejects malformed versions, metadata and untrusted source assets',
    () async {
      for (final replacement in <Map<String, Object>>[
        {'version': '1.2'},
        {'sha256': 'abc'},
        {'size': -1},
        {'platform': 'linux-x64'},
        {'schemaVersion': 2},
        {
          'url': 'http://github.com/Pietrorocchi21/waveify/releases/download/v1/app.exe',
        },
        {'url': 'https://github.com/evil/waveify/releases/download/v1/app.exe'},
        {
          'url': 'https://github.com/Pietrorocchi21/waveify/releases/download/v1/app.exe?redirect=evil',
        },
      ]) {
        final updater = service(metadata: {...manifest(), ...replacement});
        expect((await updater.check()).state, UpdateState.error);
        expect(await updater.download(), isFalse);
      }
    },
  );

  test(
    'compares numeric versions and build numbers without downgrading',
    () async {
      expect(compareVersions('1.10.0+1', '1.9.0+10'), greaterThan(0));
      expect(compareVersions('1.0.0+10', '1.0.0+9'), greaterThan(0));
      final updater = service(metadata: {...manifest(), 'version': '1.0.0+1'});
      expect((await updater.check()).state, UpdateState.upToDate);
    },
  );

  test('production helper waits, validates, installs in place and restarts with arguments', () async {
    final file = File('${cache.path}/installer.exe');
    await file.writeAsBytes(bytes);
    final updater = service();
    final script = await updater.writeInstallerHelper(
      file,
      UpdateManifest.parse(manifest()),
      executable: '/test/My App/waveify.exe',
      parentPid: 12345,
      restartArguments: [
        '--startup-report=/test/report file.json',
        'quote"test',
      ],
    );
    final source = await script.readAsString();
    expect((await script.readAsBytes()).take(3), [0xef, 0xbb, 0xbf]);
    expect(source, contains('Wait-Process -Id 12345'));
    expect(source, contains(sha256.convert(bytes).toString()));
    expect(source, contains('/DIR="/test/My App"'));
    expect(
      source,
      contains('Start-Process -FilePath \'/test/My App/waveify.exe\''),
    );
    expect(source, contains('"--startup-report=/test/report file.json"'));
    expect(source, contains(r'"quote\"test"'));
    await file.writeAsBytes([0]);
    await expectLater(
      updater.writeInstallerHelper(file, UpdateManifest.parse(manifest())),
      throwsFormatException,
    );
  });

  test('unsupported platforms are never reported up to date', () async {
    final updater = UpdaterService(platform: 'linux');
    expect((await updater.check()).state, UpdateState.unsupported);
    expect(await updater.install(), isFalse);
  });

  test('rejects insecure redirects and excessive manifest data', () async {
    for (final response in [
      ResponseBody.fromString(
        '',
        302,
        headers: {
          'location': ['http://example.com/evil'],
        },
      ),
      ResponseBody.fromString('x' * 65537, 200),
    ]) {
      final dio = Dio()..httpClientAdapter = FakeAdapter((_) => response);
      final updater = UpdaterService(dio: dio, platform: 'windows');
      expect((await updater.check()).state, UpdateState.error);
    }
  });
}
