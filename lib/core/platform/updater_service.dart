import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

/// The state of the update check.
enum UpdateState { idle, checking, available, upToDate, error }

/// The result of an update check.
class UpdateInfo {
  const UpdateInfo({
    required this.state,
    this.version,
    this.notes,
    this.error,
  });

  final UpdateState state;
  final String? version;
  final String? notes;
  final String? error;

  bool get hasUpdate => state == UpdateState.available;
}

/// Checks whether a new version of the app is available.
///
/// Port of `src/features/updater/`: the desktop builds update in place
/// through the bundled updater, the Android build delegates to the store.
class UpdaterService with UpdaterListener {
  UpdaterService._();

  static final UpdaterService instance = UpdaterService._();

  /// The feed of the released versions, set at build time.
  static const String feedUrl = String.fromEnvironment('UPDATE_FEED_URL');
  static const String fallbackFeedUrl =
      'https://github.com/pietrorocchi21/waveify/releases/latest/download/appcast.xml';

  static String get effectiveFeedUrl => feedUrl.isEmpty ? fallbackFeedUrl : feedUrl;

  bool get isDesktop =>
      !kIsWeb &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  bool get isAndroid => !kIsWeb && Platform.isAndroid;

  /// The in-place updater only exists on Windows and macOS.
  bool get _supportsInPlaceUpdate => Platform.isWindows || Platform.isMacOS;

  UpdateState _state = UpdateState.idle;
  UpdateState get state => _state;

  String? _version;
  String? _notes;
  String? _error;

  String? get version => _version;
  String? get notes => _notes;
  String? get error => _error;

  /// Prepares the updater.
  void initialize() {
    if (!_supportsInPlaceUpdate || effectiveFeedUrl.isEmpty) return;
    try {
      autoUpdater.addListener(this);
      autoUpdater.setFeedURL(effectiveFeedUrl);
      // The check is repeated once a day.
      autoUpdater.setScheduledCheckInterval(86400);
    } catch (error) {
      debugPrint('[updater] init: $error');
    }
  }

  /// Checks whether a new version is available.
  Future<UpdateInfo> check() async {
    _error = null;

    if (isAndroid) {
      return _checkOnStore();
    }

    if (!_supportsInPlaceUpdate || effectiveFeedUrl.isEmpty) {
      _state = UpdateState.upToDate;
      return const UpdateInfo(state: UpdateState.upToDate);
    }

    _state = UpdateState.checking;
    try {
      await autoUpdater.checkForUpdates();
      return UpdateInfo(
        state: _state,
        version: _version,
        notes: _notes,
        error: _error,
      );
    } catch (error) {
      _state = UpdateState.error;
      _error = '$error';
      return UpdateInfo(state: UpdateState.error, error: _error);
    }
  }

  Future<UpdateInfo> _checkOnStore() async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        _state = UpdateState.upToDate;
        return const UpdateInfo(state: UpdateState.upToDate);
      }
      _state = UpdateState.available;
      // The store only reports the availability: the version is on the
      // listing page.
      return const UpdateInfo(state: UpdateState.available);
    } catch (error) {
      _state = UpdateState.error;
      _error = '$error';
      return UpdateInfo(state: UpdateState.error, error: _error);
    }
  }

  /// Installs the update.
  ///
  /// On Android the store takes over; on the desktop the updater downloads
  /// the update in the background and asks the app to quit.
  Future<bool> install() async {
    if (isAndroid) {
      try {
        await InAppUpdate.performImmediateUpdate();
        return true;
      } catch (error) {
        _error = '$error';
        return false;
      }
    }

    // Desktop auto-update is handled by the native updater after the appcast
    // resolves a newer build. Keeping this as a no-op avoids manual reinstall
    // steps while the library downloads and quits for the update.
    if (isDesktop) {
      return true;
    }

    return false;
  }

  /// Opens the release page of the app.
  Future<void> openReleasePage() async {
    await _openUrl('https://github.com/pietrorocchi21/waveify/releases');
  }

  static Future<void> _openUrl(String url) async {
    try {
      final process = await Process.run('xdg-open', [url]);
      if (process.exitCode != 0) {
        await Process.run('open', [url]);
      }
    } catch (_) {
      // The page cannot be opened: the user can do it manually.
    }
  }

  // --- auto_updater listener ---

  @override
  void onUpdaterCheckingForUpdate(Appcast? appcast) {
    _state = UpdateState.checking;
  }

  @override
  void onUpdaterUpdateAvailable(AppcastItem? appcastItem) {
    _state = UpdateState.available;
    _version = appcastItem?.displayVersionString ?? appcastItem?.versionString;
    _notes = appcastItem?.itemDescription;
  }

  @override
  void onUpdaterUpdateNotAvailable(UpdaterError? error) {
    _state = UpdateState.upToDate;
  }

  @override
  void onUpdaterError(UpdaterError? error) {
    _state = UpdateState.error;
    _error = error?.toString();
  }

  @override
  void onUpdaterUpdateDownloaded(AppcastItem? appcastItem) {
    _state = UpdateState.available;
  }

  @override
  void onUpdaterBeforeQuitForUpdate(AppcastItem? appcastItem) {
    // The updater takes over from here.
  }
}
