import 'dart:io' show File, Platform, exit, pid;
import 'dart:convert';

import 'core/diagnostics/native_self_test.dart';
import 'core/diagnostics/network_self_test.dart';
import 'core/diagnostics/ota_self_test.dart';
import 'core/diagnostics/update_feed_self_test.dart';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'app.dart';
import 'core/deeplink/deeplink_service.dart';
import 'core/platform/updater_service.dart';
import 'core/platform/window_service.dart';
import 'core/providers/app_providers.dart';
import 'features/auth/auth_controller.dart';
import 'features/player/audio_handler.dart';
import 'features/player/player_controller.dart';
import 'features/shortcuts/global_shortcut_controller.dart';
import 'features/shortcuts/shortcut_controller.dart';

/// The platforms that provide the OS media controls (lock screen, media
/// notification, hardware media keys).
bool get _hasMediaControls =>
    Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // The overlay runs in its own engine: it is a second window of the
  // application and it only shows the player.
  // Desktop audio backend: libmpv through media_kit. It backs the same
  // `just_audio` API used on mobile and adds Opus/WebM support on Windows.
  JustAudioMediaKit.ensureInitialized();
  if (args.contains('--self-test')) {
    final output = args
        .where((arg) => arg.startsWith('--self-test-output='))
        .firstOrNull;
    final ok = await runNativeSelfTest(
      output == null
          ? 'waveify-self-test.json'
          : output.substring('--self-test-output='.length),
    );
    exit(ok ? 0 : 1);
  }

  String? argument(String name) => args
      .where((arg) => arg.startsWith('$name='))
      .firstOrNull
      ?.substring(name.length + 1);
  if (args.contains('--update-feed-self-test')) {
    final passed = await runUpdateFeedSelfTest(
      argument('--self-test-output') ?? 'waveify-feed-test.json',
    );
    exit(passed ? 0 : 1);
  }
  if (args.contains('--network-self-test')) {
    final passed = await runNetworkSelfTest(
      argument('--self-test-output') ?? 'waveify-network-test.json',
    );
    exit(passed ? 0 : 1);
  }
  if (args.contains('--ota-self-test')) {
    final report = argument('--ota-report')!;
    try {
      await startOtaSelfTest(
        installerPath: argument('--ota-installer')!,
        hash: argument('--ota-sha256')!,
        targetExecutable: argument('--ota-target')!,
        reportPath: report,
        startupPath: argument('--ota-startup')!,
      );
      exit(0);
    } catch (error) {
      await File('$report.host-error.json').writeAsString(
        jsonEncode({
          'status': 'failed',
          'error_type': '${error.runtimeType}',
          'message': '$error',
        }),
        flush: true,
      );
      exit(1);
    }
  }
  final otaReport = argument('--ota-verify-state');
  if (otaReport != null) await verifyOtaSelfTest(otaReport);

  // The updater is prepared before the first frame.
  UpdaterService.instance.initialize();

  // The desktop window is frameless: the controls are drawn by the app.
  await WindowService.instance.initialize();

  // The audio handler owns the `just_audio` player; it is created before the
  // app starts so the OS media controls can reach it immediately.
  final handler = WaveifyAudioHandler();

  if (_hasMediaControls) {
    await AudioService.init(
      builder: () => handler,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.pietrorocchi.waveify.player',
        androidNotificationChannelName: 'Waveify',
        // The service stays in the foreground while paused, so the paused
        // track remains in the notification and Android 12+ does not throw a
        // ForegroundServiceStartNotAllowedException when resuming.
        // `androidNotificationOngoing` has to stay false for that, because
        // the two options are mutually exclusive in audio_service.
        androidStopForegroundOnPause: false,
      ),
    );
  }

  final container = ProviderContainer(
    overrides: [audioHandlerProvider.overrideWithValue(handler)],
  );

  // Restore the persisted settings and session before the first frame.
  await container.read(settingsProvider.notifier).init();
  await container.read(shortcutControllerProvider.notifier).load();
  await container.read(globalShortcutControllerProvider.notifier).load();
  await container.read(authControllerProvider.notifier).initialize();

  // The deep links (waveify://) are listened to as soon as the app starts.
  await container.read(deepLinkServiceProvider).start();

  final startupOutput = args
      .where((arg) => arg.startsWith('--startup-report='))
      .firstOrNull;
  if (startupOutput != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final file = File(startupOutput.substring('--startup-report='.length));
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'status': 'passed',
          'first_frame': 'rendered',
          'pid': pid,
          'window_fits_work_area': await WindowService.instance.fitsWorkArea(),
          'authenticated': container
              .read(authControllerProvider)
              .isAuthenticated,
        }),
        flush: true,
      );
    });
  }

  runApp(
    UncontrolledProviderScope(container: container, child: const WaveifyApp()),
  );
}
