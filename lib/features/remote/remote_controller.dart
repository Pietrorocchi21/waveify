import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The commands a device can send to the other one.
enum RemoteCommand { none, play, pause, next, previous }

/// The state of the player, shared between the devices.
class RemotePlaybackState {
  const RemotePlaybackState({
    this.userId = '',
    this.deviceId = '',
    this.deviceName = '',
    this.trackId,
    this.trackTitle,
    this.trackArtist,
    this.isPlaying = false,
    this.positionSeconds = 0,
    this.command = RemoteCommand.none,
    this.commandId = '',
    this.updatedAt,
  });

  factory RemotePlaybackState.fromRow(Map<String, dynamic> row) {
    return RemotePlaybackState(
      userId: '${row['user_id'] ?? ''}',
      deviceId: '${row['device_id'] ?? ''}',
      deviceName: '${row['device_name'] ?? ''}',
      trackId: row['track_id'] as String?,
      trackTitle: row['track_title'] as String?,
      trackArtist: row['track_artist'] as String?,
      isPlaying: row['is_playing'] as bool? ?? false,
      positionSeconds: (row['position_seconds'] as num?)?.toDouble() ?? 0,
      command: _commandFromRaw('${row['command'] ?? 'none'}'),
      commandId: '${row['command_id'] ?? ''}',
      updatedAt: DateTime.tryParse('${row['updated_at'] ?? ''}'),
    );
  }

  final String userId;
  final String deviceId;
  final String deviceName;
  final String? trackId;
  final String? trackTitle;
  final String? trackArtist;
  final bool isPlaying;
  final double positionSeconds;
  final RemoteCommand command;
  final String commandId;
  final DateTime? updatedAt;

  bool get hasTrack => trackId != null && trackId!.isNotEmpty;

  static RemoteCommand _commandFromRaw(String raw) {
    return RemoteCommand.values.firstWhere(
      (c) => c.name == raw,
      orElse: () => RemoteCommand.none,
    );
  }
}

/// The state of the remote control.
class RemoteState {
  const RemoteState({
    this.isConfigured = false,
    this.isAuthenticated = false,
    this.isConnecting = false,
    this.remote,
    this.deviceId = '',
    this.deviceName = '',
    this.error,
  });

  /// The Supabase credentials are configured.
  final bool isConfigured;
  final bool isAuthenticated;
  final bool isConnecting;

  /// The state published by the other device.
  final RemotePlaybackState? remote;

  /// The identifier of this device.
  final String deviceId;
  final String deviceName;

  final String? error;

  RemoteState copyWith({
    bool? isConfigured,
    bool? isAuthenticated,
    bool? isConnecting,
    RemotePlaybackState? remote,
    bool clearRemote = false,
    String? deviceId,
    String? deviceName,
    String? error,
    bool clearError = false,
  }) {
    return RemoteState(
      isConfigured: isConfigured ?? this.isConfigured,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isConnecting: isConnecting ?? this.isConnecting,
      remote: clearRemote ? null : (remote ?? this.remote),
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Publishes the state of the player and receives the commands of the other
/// device.
///
/// Port of the "Remote" feature of the legacy apps: the state lives in the
/// `playback_state` table of Supabase and the changes are received in real
/// time through the realtime channel.
class RemoteController extends Notifier<RemoteState> {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  static const String _table = 'playback_state';
  static const String _channelName = 'realtime-playback';

  SupabaseClient? _client;
  RealtimeChannel? _channel;

  @override
  RemoteState build() {
    final deviceId = _loadDeviceId();
    return RemoteState(
      isConfigured: supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty,
      deviceId: deviceId,
      deviceName: _loadDeviceName(deviceId),
    );
  }

  String _loadDeviceId() {
    // The identifier is kept in memory: it is regenerated on every start.
    return _deviceIdCache ??= _generateId();
  }

  String? _deviceIdCache;

  static String _generateId() {
    final random = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final salt = DateTime.now().hashCode.toRadixString(36);
    return '$random-$salt';
  }

  String _loadDeviceName(String deviceId) {
    final short = deviceId.split('-').first;
    return 'Waveify $short';
  }

  /// Signs in to the Supabase account that links the devices.
  Future<bool> connect({required String email, required String password}) async {
    if (!state.isConfigured) {
      state = state.copyWith(
        error: 'The Supabase credentials are not configured.',
      );
      return false;
    }

    state = state.copyWith(isConnecting: true, clearError: true);
    try {
      await _ensureClient();
      final response = await _client!.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (response.session == null) {
        state = state.copyWith(
          isConnecting: false,
          error: 'The sign in was refused.',
        );
        return false;
      }
      await _listen();
      state = state.copyWith(isAuthenticated: true, isConnecting: false);
      return true;
    } catch (error) {
      state = state.copyWith(isConnecting: false, error: '$error');
      return false;
    }
  }

  /// Signs out and stops listening.
  Future<void> disconnect() async {
    final client = _client;
    final channel = _channel;
    _channel = null;
    if (client != null && channel != null) {
      try {
        await client.removeChannel(channel);
      } catch (_) {}
    }
    try {
      await _client?.auth.signOut();
    } catch (_) {}
    state = state.copyWith(isAuthenticated: false, clearRemote: true);
  }

  Future<SupabaseClient> _ensureClient() async {
    final existing = _client;
    if (existing != null) return existing;

    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
    );
    final client = Supabase.instance.client;
    _client = client;
    return client;
  }

  /// Listens to the state published by the other device.
  Future<void> _listen() async {
    final client = _client;
    if (client == null) return;

    final previous = _channel;
    if (previous != null) {
      try {
        await client.removeChannel(previous);
      } catch (_) {}
    }

    final userId = client.auth.currentUser!.id;
    final channel = client.channel(_channelName)
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: _table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: userId,
        ),
        callback: (payload) {
          final row = payload.newRecord;
          if (row.isEmpty) return;
          final remote = RemotePlaybackState.fromRow(row);
          // The state published by this device is ignored.
          if (remote.deviceId == state.deviceId) return;
          state = state.copyWith(remote: remote);
        },
      )
      .subscribe();

    _channel = channel;

    // The current state is read once, so the other device is shown even when
    // it does not change anything.
    try {
      final rows = await client
          .from(_table)
          .select('*')
          .eq('user_id', client.auth.currentUser!.id)
          .limit(1);
      for (final row in rows) {
        final remote = RemotePlaybackState.fromRow(
          Map<String, dynamic>.from(row),
        );
        if (remote.deviceId == state.deviceId) continue;
        state = state.copyWith(remote: remote);
      }
    } catch (error) {
      debugPrint('[remote] initial state: $error');
    }
  }

  /// Publishes the state of the player.
  Future<void> publish({
    String? trackId,
    String? trackTitle,
    String? trackArtist,
    bool isPlaying = false,
    double positionSeconds = 0,
  }) async {
    final client = _client;
    if (client == null || !state.isAuthenticated) return;

    try {
      await client.from(_table).upsert({
        'user_id': client.auth.currentUser!.id,
        'device_id': state.deviceId,
        'device_name': state.deviceName,
        'track_id': trackId,
        'track_title': trackTitle,
        'track_artist': trackArtist,
        'is_playing': isPlaying,
        'position_seconds': positionSeconds,
        'command': RemoteCommand.none.name,
      });
    } catch (error) {
      debugPrint('[remote] publish: $error');
    }
  }

  /// Sends a command to the other device.
  Future<void> sendCommand(RemoteCommand command) async {
    final client = _client;
    if (client == null || !state.isAuthenticated) return;

    try {
      await client.from(_table).upsert({
        'user_id': client.auth.currentUser!.id,
        'device_id': state.deviceId,
        'device_name': state.deviceName,
        'command': command.name,
        'command_id': _generateId(),
      });
    } catch (error) {
      debugPrint('[remote] command: $error');
    }
  }

}

/// The remote control provider.
final remoteControllerProvider =
    NotifierProvider<RemoteController, RemoteState>(RemoteController.new);
