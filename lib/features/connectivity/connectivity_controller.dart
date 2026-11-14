import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';

/// The result of a single diagnostic probe.
class ConnectivityCheck {
  const ConnectivityCheck({
    required this.id,
    required this.status,
    this.detail,
    this.latencyMs,
  });

  final String id;
  final String status;
  final String? detail;
  final int? latencyMs;

  bool get isOk => status == 'ok';
  bool get isFail => status == 'fail';
}

/// A recorded request failure.
class ConnectivityFailure {
  const ConnectivityFailure({
    required this.at,
    required this.method,
    required this.path,
    this.status,
    this.code,
    this.latencyMs = 0,
  });

  final DateTime at;
  final String method;
  final String path;
  final int? status;
  final String? code;
  final int latencyMs;

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'method': method,
        'path': path,
        if (status != null) 'status': status,
        if (code != null) 'code': code,
        'latencyMs': latencyMs,
      };
}

/// The state of the connectivity diagnostics.
class ConnectivityState {
  const ConnectivityState({
    this.tripped = false,
    this.visible = false,
    this.isRunning = false,
    this.checks = const [],
    this.failures = const [],
    this.lastRunAt,
  });

  /// The wall is shown: the connection is broken.
  final bool tripped;
  final bool visible;
  final bool isRunning;
  final List<ConnectivityCheck> checks;
  final List<ConnectivityFailure> failures;
  final DateTime? lastRunAt;

  /// True when the backend is the one that is down.
  bool get isServerOutage => checks.any(
        (c) => c.id == 'api' && (c.detail ?? '').startsWith('HTTP 5'),
      );

  ConnectivityState copyWith({
    bool? tripped,
    bool? visible,
    bool? isRunning,
    List<ConnectivityCheck>? checks,
    List<ConnectivityFailure>? failures,
    DateTime? lastRunAt,
  }) {
    return ConnectivityState(
      tripped: tripped ?? this.tripped,
      visible: visible ?? this.visible,
      isRunning: isRunning ?? this.isRunning,
      checks: checks ?? this.checks,
      failures: failures ?? this.failures,
      lastRunAt: lastRunAt ?? this.lastRunAt,
    );
  }
}

/// Watches the connection to the backend and runs the diagnostics when it
/// breaks.
///
/// Port of `src/features/connectivity/`.
class ConnectivityController extends Notifier<ConnectivityState> {
  /// Three failures within a minute trip the wall.
  static const int tripCount = 3;
  static const Duration tripWindow = Duration(seconds: 60);
  static const int maxFailures = 20;
  static const Duration checkTimeout = Duration(seconds: 8);

  @override
  ConnectivityState build() {
    return const ConnectivityState();
  }

  /// Records a failed request.
  void recordFailure({
    required String method,
    required String path,
    int? status,
    String? code,
    int latencyMs = 0,
  }) {
    // The playback and the lyrics requests fail for other reasons.
    if (isPlaybackPath(path)) return;

    final now = DateTime.now();
    final failures = [
      ...state.failures,
      ConnectivityFailure(
        at: now,
        method: method,
        path: stripQuery(path),
        status: status,
        code: code,
        latencyMs: latencyMs,
      ),
    ].take(maxFailures).toList(growable: false);

    final recent = failures
        .where((f) => now.difference(f.at) <= tripWindow)
        .length;

    if (recent >= tripCount) {
      state = state.copyWith(
        failures: failures,
        tripped: true,
        visible: true,
      );
      unawaited(runDiagnostics());
    } else {
      state = state.copyWith(failures: failures);
    }
  }

  /// Hides the wall and tries again.
  Future<void> retry() async {
    state = state.copyWith(visible: false, tripped: false, failures: const []);
    await runDiagnostics();
  }

  /// Hides the wall without trying again.
  void dismiss() {
    state = state.copyWith(visible: false, tripped: false);
  }

  /// Runs every diagnostic probe.
  Future<void> runDiagnostics() async {
    if (state.isRunning) return;
    state = state.copyWith(isRunning: true);

    final checks = <ConnectivityCheck>[];

    // 1. The state reported by the operating system.
    try {
      final connectivity = await Connectivity().checkConnectivity();
      final online = connectivity.any((r) => r != ConnectivityResult.none);
      checks.add(
        ConnectivityCheck(
          id: 'device',
          status: online ? 'ok' : 'fail',
          detail: online ? 'online' : 'the system reports no connection',
        ),
      );
    } catch (error) {
      checks.add(
        ConnectivityCheck(
          id: 'device',
          status: 'fail',
          detail: '$error',
        ),
      );
    }

    // 2. The reachability of the backends.
    if (!AppConfig.hasConfiguredBackend) {
      checks.add(
        const ConnectivityCheck(
          id: 'api',
          status: 'skipped',
          detail: 'no backend configured; offline/local-first mode',
        ),
      );
      checks.add(
        const ConnectivityCheck(
          id: 'covers',
          status: 'skipped',
          detail: 'no cover proxy configured; offline/local-first mode',
        ),
      );
      state = state.copyWith(
        checks: checks,
        isRunning: false,
        lastRunAt: DateTime.now(),
      );
      return;
    }

    checks.add(await _httpCheck('api', '${AppConfig.apiBaseUrl}/health'));
    checks.add(
      await _httpCheck('covers', '${AppConfig.coversProxyUrl}/'),
    );

    // 3. The name resolution.
    final apiHost = _hostOf(AppConfig.apiBaseUrl);
    if (apiHost.isNotEmpty) {
      final started = DateTime.now();
      try {
        final addresses = await InternetAddress.lookup(apiHost)
            .timeout(const Duration(seconds: 5));
        checks.add(
          ConnectivityCheck(
            id: 'dns',
            status: addresses.isEmpty ? 'fail' : 'ok',
            detail: addresses.isEmpty
                ? 'no address for $apiHost'
                : addresses.first.address,
            latencyMs: DateTime.now().difference(started).inMilliseconds,
          ),
        );
      } catch (error) {
        checks.add(
          ConnectivityCheck(
            id: 'dns',
            status: 'fail',
            detail: '$error',
            latencyMs: DateTime.now().difference(started).inMilliseconds,
          ),
        );
      }

      // 4. The TCP connection.
      final tcpStarted = DateTime.now();
      try {
        final socket = await Socket.connect(
          apiHost,
          443,
          timeout: const Duration(seconds: 5),
        );
        socket.destroy();
        checks.add(
          ConnectivityCheck(
            id: 'tcp',
            status: 'ok',
            detail: 'connected to $apiHost:443',
            latencyMs: DateTime.now().difference(tcpStarted).inMilliseconds,
          ),
        );
      } catch (error) {
        checks.add(
          ConnectivityCheck(
            id: 'tcp',
            status: 'fail',
            detail: '$error',
            latencyMs: DateTime.now().difference(tcpStarted).inMilliseconds,
          ),
        );
      }
    }

    state = state.copyWith(
      checks: checks,
      isRunning: false,
      lastRunAt: DateTime.now(),
    );
  }

  Future<ConnectivityCheck> _httpCheck(String id, String url) async {
    final started = DateTime.now();
    try {
      final client = HttpClient()..connectionTimeout = checkTimeout;
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(checkTimeout);
      await response.drain<void>();
      client.close();
      return ConnectivityCheck(
        id: id,
        status: response.statusCode < 500 ? 'ok' : 'fail',
        detail: 'HTTP ${response.statusCode}',
        latencyMs: DateTime.now().difference(started).inMilliseconds,
      );
    } catch (error) {
      return ConnectivityCheck(
        id: id,
        status: 'fail',
        detail: error.toString().split('\n').first,
        latencyMs: DateTime.now().difference(started).inMilliseconds,
      );
    }
  }

  static String _hostOf(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return '';
    }
  }
}

/// Removes the query string from a path.
String stripQuery(String path) {
  final cut = path.indexOf('?');
  return cut == -1 ? path : path.substring(0, cut);
}

/// True for the paths whose failures are not a connection problem.
bool isPlaybackPath(String path) {
  final stripped = stripQuery(path);
  return RegExp(r'^\/v1\/tracks\/[^/]+\/(?:playback|lyrics)(?:\/|$)')
          .hasMatch(stripped) ||
      RegExp(r'^\/v1\/playback(?:\/|$)').hasMatch(stripped);
}

/// The connectivity controller provider.
final connectivityControllerProvider =
    NotifierProvider<ConnectivityController, ConnectivityState>(
  ConnectivityController.new,
);
