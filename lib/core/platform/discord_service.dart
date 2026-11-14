import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// The Rich Presence shown in Discord.
///
/// The protocol is the local IPC of the Discord client: a JSON frame over a
/// unix socket (Linux, macOS) or a named pipe (Windows). It is implemented
/// here directly, so the app does not depend on an unmaintained package.
class DiscordService {
  DiscordService._();

  static final DiscordService instance = DiscordService._();

  /// The application id of the Rich Presence.
  static const String clientId = '1561339119617974362';

  Socket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeat;
  Timer? _reconnect;
  int _nonce = 0;
  bool _enabled = false;
  bool _connecting = false;

  bool get isEnabled => _enabled;

  bool get isSupported => !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  /// The state shown in Discord.
  String? _details;
  String? _state;
  String? _largeImageKey;
  String? _largeImageText;
  String? _smallImageKey;
  int? _startTimestamp;
  int? _endTimestamp;
  bool _showArtwork = true;
  bool _showArtistImage = true;
  bool _showTime = true;

  /// Enables or disables the Rich Presence.
  Future<void> setEnabled(bool enabled) async {
    if (!isSupported) return;
    if (enabled == _enabled) return;
    _enabled = enabled;
    if (enabled) {
      await _connect();
    } else {
      await _disconnect();
    }
  }

  /// The options of the Rich Presence.
  void setOptions({
    bool? showArtwork,
    bool? showArtistImage,
    bool? showTime,
  }) {
    if (showArtwork != null) _showArtwork = showArtwork;
    if (showArtistImage != null) _showArtistImage = showArtistImage;
    if (showTime != null) _showTime = showTime;
  }

  /// Updates the activity.
  Future<void> update({
    String? details,
    String? state,
    String? largeImageKey,
    String? largeImageText,
    String? smallImageKey,
    int? startTimestamp,
    int? endTimestamp,
  }) async {
    _details = details;
    _state = state;
    _largeImageKey = largeImageKey;
    _largeImageText = largeImageText;
    _smallImageKey = smallImageKey;
    _startTimestamp = startTimestamp;
    _endTimestamp = endTimestamp;
    if (_enabled) await _sendActivity();
  }

  Future<void> _connect() async {
    if (_socket != null || _connecting) return;
    _connecting = true;

    try {
      final path = _socketPath();
      if (path == null) {
        _connecting = false;
        return;
      }

      final socket = await Socket.connect(
        path,
        0,
        timeout: const Duration(seconds: 2),
      );
      _socket = socket;

      _subscription = socket.listen(
        (data) => _onData(data),
        onError: (Object error) {
          debugPrint('[discord] socket error: $error');
          _scheduleReconnect();
        },
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );

      // The handshake.
      _send({
        'cmd': 'DISPATCH',
        'evt': 'READY',
        'data': {
          'v': 1,
          'config': {
            'client_id': clientId,
            'properties': {'os': Platform.operatingSystem},
          },
        },
      });

      // The heartbeat keeps the connection alive.
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
        _send({
          'cmd': 'SET_ACTIVITY',
          'args': {
            'pid': pid,
            'activity': _activity(),
          },
        });
      });

      await _sendActivity();
      _connecting = false;
    } catch (error) {
      _connecting = false;
      debugPrint('[discord] not connected: $error');
      _scheduleReconnect();
    }
  }

  Future<void> _disconnect() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    _reconnect?.cancel();
    _reconnect = null;
    await _subscription?.cancel();
    _subscription = null;
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
  }

  void _scheduleReconnect() {
    unawaited(_disconnect());
    if (!_enabled) return;
    _reconnect?.cancel();
    _reconnect = Timer(const Duration(seconds: 15), _connect);
  }

  void _onData(dynamic data) {
    // The Discord client only sends the acknowledgements.
  }

  void _send(Map<String, dynamic> payload) {
    final socket = _socket;
    if (socket == null) return;
    try {
      socket.write('${jsonEncode(payload)}\n');
    } catch (error) {
      debugPrint('[discord] send failed: $error');
    }
  }

  Future<void> _sendActivity() async {
    _nonce += 1;
    _send({
      'cmd': 'SET_ACTIVITY',
      'args': {
        'pid': pid,
        'nonce': '$_nonce',
        'activity': _activity(),
      },
    });
  }

  Map<String, dynamic> _activity() {
    final assets = <String, dynamic>{};
    if (_showArtwork && _largeImageKey != null) {
      assets['large_image'] = _largeImageKey;
      if (_largeImageText != null) assets['large_text'] = _largeImageText;
    }
    if (_showArtistImage && _smallImageKey != null) {
      assets['small_image'] = _smallImageKey;
    }

    return {
      'name': 'Waveify',
      // 2 = ActivityType.Listening: Discord renders "Listening to" and the
      // progress bar.
      'type': 2,
      if (_details != null) 'details': _details,
      if (_state != null) 'state': _state,
      if (assets.isNotEmpty) 'assets': assets,
      if (_showTime && _startTimestamp != null)
        'timestamps': {
          'start': _startTimestamp,
          if (_endTimestamp != null) 'end': _endTimestamp,
        },
    };
  }

  /// Only the https images are accepted by Discord.
  static String? toDiscordImageUrl(String? url) {
    if (url == null || url.isEmpty || url.length > 512) return null;
    try {
      final uri = Uri.parse(url);
      return uri.scheme == 'https' ? url : null;
    } catch (_) {
      return null;
    }
  }

  /// The path of the Discord IPC socket.
  static String? _socketPath() {
    if (Platform.isWindows) {
      return r'\\.\pipe\discord-ipc-0';
    }
    final runtimeDir = Platform.environment['XDG_RUNTIME_DIR'];
    final candidates = <String>[
      if (runtimeDir != null && runtimeDir.isNotEmpty)
        '$runtimeDir/discord-ipc-0',
      if (Platform.isMacOS)
        '${Platform.environment['TMPDIR'] ?? '/tmp'}/com.discordapp.Discord/ipc.0',
      '/tmp/discord-ipc-0',
      '/var/run/discord-ipc-0',
    ];
    for (final candidate in candidates) {
      if (candidate.isEmpty) continue;
      if (Platform.isLinux || Platform.isMacOS) {
        if (File(candidate).existsSync()) return candidate;
      } else {
        return candidate;
      }
    }
    return null;
  }
}
