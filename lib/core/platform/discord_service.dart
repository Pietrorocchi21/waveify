import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// The Rich Presence shown in Discord.
///
/// The protocol is the local IPC of the Discord client: a JSON frame over a
/// Unix socket (Linux, macOS). Windows named pipes are not supported. It is implemented
/// here directly, so the app does not depend on an unmaintained package.
class DiscordService {
  DiscordService._()
    : socketPaths = null,
      reconnectDelay = const Duration(seconds: 15);

  @visibleForTesting
  DiscordService.forTesting(
    this.socketPaths, {
    this.reconnectDelay = const Duration(milliseconds: 50),
  });

  final List<String>? socketPaths;
  final Duration reconnectDelay;

  static final DiscordService instance = DiscordService._();

  /// The application id of the Rich Presence.
  static const String clientId = String.fromEnvironment(
    'DISCORD_APPLICATION_ID',
    defaultValue: '1561339119617974362',
  );

  Socket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _handshakeTimeout;
  final List<int> _buffer = [];
  bool _ready = false;
  int _generation = 0;
  Timer? _reconnect;
  int _nonce = 0;
  bool _enabled = false;
  bool _connecting = false;

  bool get isEnabled => _enabled;

  bool get isSupported => !kIsWeb && (Platform.isLinux || Platform.isMacOS);

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
  void setOptions({bool? showArtwork, bool? showArtistImage, bool? showTime}) {
    if (showArtwork != null) _showArtwork = showArtwork;
    if (showArtistImage != null) _showArtistImage = showArtistImage;
    if (showTime != null) _showTime = showTime;
    if (_enabled) unawaited(_sendActivity());
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
    if (!_enabled || _socket != null || _connecting) return;
    _connecting = true;
    final generation = _generation;
    try {
      Socket? connected;
      for (final path in socketPaths ?? _socketPaths()) {
        try {
          connected = await Socket.connect(
            InternetAddress(path, type: InternetAddressType.unix),
            0,
            timeout: const Duration(seconds: 2),
          );
          break;
        } on SocketException {
          // Discord may expose any of the ten IPC slots.
        }
      }
      if (generation != _generation || !_enabled) {
        connected?.destroy();
        return;
      }
      if (connected == null) {
        _scheduleReconnect();
        return;
      }
      _socket = connected;
      _subscription = connected.listen(
        _onData,
        onError: (Object error) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
      _sendFrame(0, {'v': 1, 'client_id': clientId});
      _handshakeTimeout = Timer(const Duration(seconds: 5), _scheduleReconnect);
    } catch (error) {
      debugPrint('[discord] not connected: $error');
      if (generation == _generation) _scheduleReconnect();
    } finally {
      _connecting = false;
      if (_enabled && _socket == null && _reconnect == null) {
        _reconnect = Timer(reconnectDelay, _connect);
      }
    }
  }

  Future<void> _disconnect() async {
    _generation++;
    _handshakeTimeout?.cancel();
    _handshakeTimeout = null;
    _reconnect?.cancel();
    _reconnect = null;
    _ready = false;
    _buffer.clear();
    final subscription = _subscription;
    _subscription = null;
    _socket?.destroy();
    _socket = null;
    await subscription?.cancel();
  }

  Future<void> dispose() async {
    _enabled = false;
    await _disconnect();
  }

  void _scheduleReconnect() {
    unawaited(_disconnect());
    if (!_enabled) return;
    _reconnect = Timer(reconnectDelay, _connect);
  }

  void _onData(List<int> data) {
    _buffer.addAll(data);
    while (_buffer.length >= 8) {
      final header = ByteData.sublistView(
        Uint8List.fromList(_buffer.sublist(0, 8)),
      );
      final opcode = header.getUint32(0, Endian.little);
      final length = header.getUint32(4, Endian.little);
      if (length > 1024 * 1024) {
        _scheduleReconnect();
        return;
      }
      if (_buffer.length < 8 + length) return;
      final payload = Uint8List.fromList(_buffer.sublist(8, 8 + length));
      _buffer.removeRange(0, 8 + length);
      if (opcode == 3) {
        _writeFrame(4, payload);
      } else if (opcode == 2) {
        _scheduleReconnect();
        return;
      } else if (opcode == 1) {
        try {
          final message = jsonDecode(utf8.decode(payload));
          if (message is Map && message['evt'] == 'READY') {
            _ready = true;
            _handshakeTimeout?.cancel();
            unawaited(_sendActivity());
          } else if (message is Map && message['evt'] == 'ERROR') {
            debugPrint('[discord] RPC error: ${message['data']}');
          }
        } on FormatException {
          _scheduleReconnect();
          return;
        }
      }
    }
  }

  void _sendFrame(int opcode, Map<String, dynamic> payload) =>
      _writeFrame(opcode, utf8.encode(jsonEncode(payload)));

  void _writeFrame(int opcode, List<int> payload) {
    final frame = ByteData(8);
    frame.setUint32(0, opcode, Endian.little);
    frame.setUint32(4, payload.length, Endian.little);
    try {
      _socket?.add([...frame.buffer.asUint8List(), ...payload]);
    } catch (_) {
      _scheduleReconnect();
    }
  }

  Future<void> _sendActivity() async {
    if (!_ready) return;
    _sendFrame(1, {
      'cmd': 'SET_ACTIVITY',
      'nonce': '${++_nonce}',
      'args': {'pid': pid, 'activity': _activity()},
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
      return uri.scheme == 'https' && uri.host.isNotEmpty ? url : null;
    } catch (_) {
      return null;
    }
  }

  /// Windows named pipes need a native transport and are not supported here.
  static Iterable<String> _socketPaths() sync* {
    final directories = <String>{
      for (final key in ['XDG_RUNTIME_DIR', 'TMPDIR', 'TMP', 'TEMP'])
        if (Platform.environment[key]?.isNotEmpty ?? false)
          Platform.environment[key]!,
      '/tmp',
      '/var/run',
    };
    for (final directory in directories) {
      for (var slot = 0; slot < 10; slot++) {
        yield '$directory/discord-ipc-$slot';
        if (Platform.isLinux) {
          yield '$directory/app/com.discordapp.Discord/discord-ipc-$slot';
        }
      }
    }
  }
}
