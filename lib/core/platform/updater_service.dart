import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

enum UpdateState {
  idle,
  checking,
  available,
  upToDate,
  downloading,
  downloaded,
  installing,
  error,
  unsupported,
}

class UpdateInfo {
  const UpdateInfo({required this.state, this.version, this.notes, this.error});
  final UpdateState state;
  final String? version;
  final String? notes;
  final String? error;
  bool get hasUpdate => state == UpdateState.available;
}

class UpdateManifest {
  const UpdateManifest(
    this.version,
    this.url,
    this.sha256,
    this.size,
    this.notes,
  );
  final String version;
  final Uri url;
  final String sha256;
  final int size;
  final String notes;

  static UpdateManifest parse(Object? value) {
    if (value is! Map ||
        value['schemaVersion'] != 1 ||
        value['platform'] != 'windows-x64' ||
        value['version'] is! String ||
        value['url'] is! String ||
        value['sha256'] is! String ||
        value['size'] is! int ||
        value['notes'] is! String) {
      throw const FormatException('Invalid update manifest');
    }
    final version = value['version'] as String;
    compareVersions(version, version);
    final url = Uri.parse(value['url'] as String);
    if (!trustedReleaseUrl(url) ||
        !url.path.endsWith('.exe') ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(value['sha256'] as String) ||
        (value['size'] as int) <= 0 ||
        (value['size'] as int) > 2147483648) {
      throw const FormatException('Invalid update asset');
    }
    return UpdateManifest(
      version,
      url,
      (value['sha256'] as String).toLowerCase(),
      value['size'] as int,
      value['notes'] as String,
    );
  }
}

bool trustedReleaseUrl(Uri url) =>
    url.scheme == 'https' &&
    url.host.toLowerCase() == 'github.com' &&
    url.userInfo.isEmpty &&
    !url.hasPort &&
    !url.hasQuery &&
    !url.hasFragment &&
    url.pathSegments.length == 6 &&
    url.pathSegments.every(
      (part) => part.isNotEmpty && part != "." && part != "..",
    ) &&
    url.pathSegments[0].toLowerCase() == 'pietrorocchi21' &&
    url.pathSegments[1].toLowerCase() == 'waveify' &&
    url.pathSegments[2] == 'releases' &&
    (url.pathSegments[3] == 'download' ||
        (url.pathSegments[3] == 'latest' && url.pathSegments[4] == 'download'));

int compareVersions(String a, String b) {
  List<int> parse(String value) {
    if (!RegExp(r'^\d+\.\d+\.\d+\+\d+$').hasMatch(value)) {
      throw const FormatException('Expected major.minor.patch+build version');
    }
    return value.split(RegExp(r'[.+]')).map(int.parse).toList();
  }

  final left = parse(a), right = parse(b);
  for (var i = 0; i < left.length; i++) {
    final result = left[i].compareTo(right[i]);
    if (result != 0) return result;
  }
  return 0;
}

/// Windows updates use the release installer, retaining the existing install
/// directory and user profile. Android delegates installation to Google Play.
class UpdaterService extends ChangeNotifier {
  // Public injection hooks keep transport and installation independently testable.
  UpdaterService({
    Dio? dio,
    String? platform,
    this.currentVersion = appVersion,
    Future<Directory> Function()? cacheDirectory,
    this.installHook,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 20),
               receiveTimeout: const Duration(seconds: 60),
             ),
           ),
       _platform = platform ?? (kIsWeb ? 'web' : Platform.operatingSystem),
       _cacheDirectory = cacheDirectory ?? getApplicationCacheDirectory;

  static final instance = UpdaterService();
  static const appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.0+1',
  );
  static const manifestUrl = String.fromEnvironment(
    'UPDATE_MANIFEST_URL',
    defaultValue: 'https://github.com/Pietrorocchi21/waveify/releases/latest/download/update.json',
  );
  final Dio _dio;
  final String _platform;
  final Future<Directory> Function() _cacheDirectory;
  final Future<void> Function(File, UpdateManifest)? installHook;
  final String currentVersion;
  UpdateState state = UpdateState.idle;
  UpdateManifest? _manifest;
  File? _installer;
  String? error;
  double progress = 0;
  String? get version => _manifest?.version;
  String? get notes => _manifest?.notes;
  bool get isAndroid => _platform == 'android';
  bool get isDesktop => ['windows', 'linux', 'macos'].contains(_platform);
  bool get busy => [
    UpdateState.checking,
    UpdateState.downloading,
    UpdateState.installing,
  ].contains(state);
  Timer? _automaticCheck;
  bool _initialized = false;
  void initialize() {
    if (_initialized || _platform != 'windows') return;
    _initialized = true;
    _automaticCheck = Timer(const Duration(seconds: 8), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final last = prefs.getInt('waveify_update_last_check_ms') ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - last < const Duration(hours: 12).inMilliseconds || busy) {
          return;
        }
        await prefs.setInt('waveify_update_last_check_ms', now);
        await check();
      } catch (_) {
        /* A background check must never prevent app startup. */
      }
    });
  }

  @override
  void dispose() {
    _automaticCheck?.cancel();
    _dio.close(force: true);
    super.dispose();
  }

  void _set(UpdateState next) {
    state = next;
    notifyListeners();
  }

  UpdateInfo get _info =>
      UpdateInfo(state: state, version: version, notes: notes, error: error);

  Future<UpdateInfo> check() async {
    if (busy) return _info;
    error = null;
    _set(UpdateState.checking);
    try {
      if (isAndroid) {
        final info = await InAppUpdate.checkForUpdate();
        _set(
          info.updateAvailability == UpdateAvailability.updateAvailable
              ? UpdateState.available
              : UpdateState.upToDate,
        );
      } else if (_platform != 'windows') {
        _set(UpdateState.unsupported);
      } else {
        final uri = Uri.parse(manifestUrl);
        if (!trustedReleaseUrl(uri)) {
          throw const FormatException('Untrusted update manifest URL');
        }
        final response = await _getStream(uri);
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > 65536) {
            throw const FormatException('Update manifest too large');
          }
          bytes.addAll(chunk);
        }
        final body = utf8.decode(bytes);
        final manifest = UpdateManifest.parse(jsonDecode(body));
        _manifest = manifest;
        _installer = null;
        _set(
          compareVersions(manifest.version, currentVersion) > 0
              ? UpdateState.available
              : UpdateState.upToDate,
        );
      }
    } catch (e) {
      error = '$e';
      _set(UpdateState.error);
    }
    return _info;
  }

  Future<ResponseBody> _getStream(Uri uri) async {
    for (var redirects = 0; redirects < 6; redirects++) {
      final response = await _dio.get<ResponseBody>(
        uri.toString(),
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: false,
          validateStatus: (status) =>
              status == 200 ||
              (status != null && status >= 300 && status < 400),
        ),
      );
      final body = response.data!;
      if (response.statusCode == 200) return body;
      final location = response.headers.value('location');
      await body.stream.listen(null).cancel();
      if (location == null) {
        throw const FormatException('Missing redirect destination');
      }
      uri = uri.resolve(location);
      if (uri.scheme != 'https' ||
          uri.userInfo.isNotEmpty ||
          uri.hasPort ||
          ![
            'github.com',
            'release-assets.githubusercontent.com',
            'objects.githubusercontent.com',
          ].contains(uri.host.toLowerCase())) {
        throw const FormatException('Untrusted update redirect');
      }
    }
    throw const FormatException('Too many update redirects');
  }

  Future<bool> download() async {
    if (busy ||
        _manifest == null ||
        _platform != 'windows' ||
        compareVersions(_manifest!.version, currentVersion) <= 0) {
      return false;
    }
    final manifest = _manifest!;
    File? partial;
    IOSink? sink;
    error = null;
    progress = 0;
    _set(UpdateState.downloading);
    try {
      final directory = Directory(
        '${(await _cacheDirectory()).path}${Platform.pathSeparator}updates',
      );
      await directory.create(recursive: true);
      final destination = File(
        '${directory.path}${Platform.pathSeparator}Waveify-${manifest.version}.exe',
      );
      if (await destination.exists() && await _verify(destination, manifest)) {
        _installer = destination;
        progress = 1;
        _set(UpdateState.downloaded);
        return true;
      }
      partial = File('${destination.path}.part');
      sink = partial.openWrite();
      final response = await _getStream(manifest.url);
      final contentLength = int.tryParse(
        response.headers['content-length']?.first ?? '',
      );
      if (contentLength != null && contentLength != manifest.size) {
        throw const FormatException('Installer size mismatch');
      }
      var bytes = 0;
      await for (final chunk in response.stream) {
        bytes += chunk.length;
        if (bytes > manifest.size) {
          throw const FormatException('Installer exceeds expected size');
        }
        sink.add(chunk);
        await sink.flush();
        progress = bytes / manifest.size;
        notifyListeners();
      }
      await sink.close();
      sink = null;
      if (!await _verify(partial, manifest)) {
        throw const FormatException('Installer integrity check failed');
      }
      if (await destination.exists()) await destination.delete();
      _installer = await partial.rename(destination.path);
      _set(UpdateState.downloaded);
      return true;
    } catch (e) {
      await sink?.close();
      if (partial != null && await partial.exists()) await partial.delete();
      error = '$e';
      _set(UpdateState.error);
      return false;
    }
  }

  Future<bool> _verify(File file, UpdateManifest manifest) async =>
      await file.length() == manifest.size &&
      (await sha256.bind(file.openRead()).first).toString() == manifest.sha256;

  Future<bool> install() async {
    if (busy) return false;
    error = null;
    try {
      if (isAndroid) {
        _set(UpdateState.installing);
        await InAppUpdate.performImmediateUpdate();
        _set(UpdateState.idle);
        return true;
      }
      final installer = _installer, manifest = _manifest;
      if (_platform != 'windows' || installer == null || manifest == null) {
        return false;
      }
      _set(UpdateState.installing);
      if (!await _verify(installer, manifest)) {
        throw const FormatException('Installer integrity check failed');
      }
      await (installHook ?? _launchInstaller)(installer, manifest);
      return true;
    } catch (e) {
      error = '$e';
      _set(UpdateState.error);
      return false;
    }
  }

  /// Creates the exact production helper without launching it or exiting.
  /// Native package tests use this hook to exercise install/restart in isolation.
  Future<File> writeInstallerHelper(
    File installer,
    UpdateManifest manifest, {
    String? executable,
    int? parentPid,
    List<String> restartArguments = const [],
  }) async {
    if (!await _verify(installer, manifest)) {
      throw const FormatException('Installer integrity check failed');
    }
    executable ??= Platform.resolvedExecutable;
    parentPid ??= pid;
    final script = File(
      '${installer.parent.path}${Platform.pathSeparator}install-update.ps1',
    );
    String quote(String value) => "'${value.replaceAll("'", "''")}'";
    String windowsArgument(String argument) {
      final escaped = argument.replaceAllMapped(
        RegExp(r'(\\*)"'),
        (match) => '${match[1]}${match[1]}\\"',
      );
      final trailing = RegExp(r'\\+$').firstMatch(escaped)?.group(0) ?? '';
      return '"$escaped$trailing"';
    }

    final restart =
        'Start-Process -FilePath ${quote(executable)}'
        '${restartArguments.isEmpty ? '' : ' -ArgumentList ${quote(restartArguments.map(windowsArgument).join(' '))}'}';
    await script.writeAsString('''﻿
\$ErrorActionPreference = 'Stop'
try {
  Wait-Process -Id $parentPid -ErrorAction SilentlyContinue
  \$installer = ${quote(installer.path)}
  if ((Get-FileHash -LiteralPath \$installer -Algorithm SHA256).Hash.ToLowerInvariant() -ne ${quote(manifest.sha256)}) { throw 'Installer hash mismatch' }
  \$arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/CLOSEAPPLICATIONS', ${quote('/LOG="${installer.parent.path}${Platform.pathSeparator}install.log"')}, ${quote('/DIR="${File(executable).parent.path}"')})
  \$result = Start-Process -FilePath \$installer -ArgumentList \$arguments -Wait -PassThru
  if (\$result.ExitCode -ne 0) { throw "Installer failed: \$(\$result.ExitCode)" }
  $restart
} catch {
  \$_ | Out-File -LiteralPath ${quote('${installer.parent.path}${Platform.pathSeparator}install-error.txt')}
  $restart
}
''', flush: true);
    return script;
  }

  Future<void> _launchInstaller(File installer, UpdateManifest manifest) async {
    final script = await writeInstallerHelper(installer, manifest);
    await Process.start('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-WindowStyle',
      'Hidden',
      '-File',
      script.path,
    ], mode: ProcessStartMode.detached);
    exit(0);
  }

  Future<void> openReleasePage() async {
    await launchUrl(
      Uri.parse('https://github.com/Pietrorocchi21/waveify/releases'),
      mode: LaunchMode.externalApplication,
    );
  }
}
