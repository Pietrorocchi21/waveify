import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/app_providers.dart';

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

  /// Reject commands meant for another player, echoes and commands from an
  /// earlier connection. Playback-only updates must never trigger the player.
  static bool acceptsCommand(
    Map<String, dynamic> row, {
    required String deviceId,
    required DateTime connectedAt,
    String? lastCommandId,
  }) {
    final value = RemotePlaybackState.fromRow(row);
    final sentAt = DateTime.tryParse('${row['command_created_at'] ?? ''}');
    return value.deviceId == deviceId &&
        row['command_sender_id'] != deviceId &&
        value.commandId.isNotEmpty &&
        value.commandId != lastCommandId &&
        value.command != RemoteCommand.none &&
        sentAt != null &&
        !sentAt.isBefore(connectedAt);
  }

  RemotePlaybackState withCommand(RemotePlaybackState incoming) =>
      RemotePlaybackState(
        userId: userId,
        deviceId: deviceId,
        deviceName: deviceName,
        trackId: trackId,
        trackTitle: trackTitle,
        trackArtist: trackArtist,
        isPlaying: isPlaying,
        positionSeconds: positionSeconds,
        updatedAt: updatedAt,
        command: incoming.command,
        commandId: incoming.commandId,
      );

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
/// `waveify_playback_state` table of Supabase and the changes are received in real
/// time through the realtime channel.
class RemoteController extends Notifier<RemoteState> {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  static const String _table = 'waveify_playback_state';
  static const String _publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const String _channelName = 'realtime-playback';

  SupabaseClient? _client;
  SupabaseClient? _accountClient;
  RealtimeChannel? _channel;

  bool _disposed = false;
  int _listenGeneration = 0;
  int _connectionGeneration = 0;
  Future<void>? _identityReady;
  DateTime _connectedAt = DateTime.now().toUtc();
  String? _lastCommandId;

  @override
  RemoteState build() {
    final deviceId = const Uuid().v4();
    _identityReady = Future<void>.microtask(() async {
      final preferences = await SharedPreferences.getInstance();
      final saved = preferences.getString('waveify.remote.device_id');
      final id = saved ?? deviceId;
      if (saved == null) {
        await preferences.setString('waveify.remote.device_id', id);
      }
      if (!_disposed) {
        state = state.copyWith(deviceId: id, deviceName: _loadDeviceName(id));
      }
    });
    final account = ref.read(supabaseClientProvider);
    _accountClient = account;
    final subscription = account?.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedOut &&
          identical(_client, account)) {
        unawaited(disconnect());
      } else if (event.session != null && !state.isAuthenticated) {
        unawaited(_connectAccount(account));
      }
    });
    if (account?.auth.currentSession != null) {
      unawaited(Future<void>.microtask(() => _connectAccount(account!)));
    }
    ref.onDispose(() {
      if (subscription != null) unawaited(subscription.cancel());
      _disposed = true;
      final client = _client;
      _client = null;
      final channel = _channel;
      _channel = null;
      if (client != null && identical(client, _accountClient)) {
        if (channel != null) unawaited(client.removeChannel(channel));
      } else if (client != null) {
        unawaited(client.dispose());
      }
    });
    return RemoteState(
      isConfigured:
          supabaseUrl.isNotEmpty &&
          (supabaseAnonKey.isNotEmpty || _publishableKey.isNotEmpty),
      deviceId: deviceId,
      deviceName: _loadDeviceName(deviceId),
    );
  }

  String _loadDeviceName(String deviceId) =>
      'Waveify ${deviceId.split('-').first}';

  Future<void> _connectAccount(SupabaseClient account) async {
    await _identityReady;
    if (_disposed ||
        state.isConnecting ||
        state.isAuthenticated ||
        account.auth.currentSession == null) {
      return;
    }
    final attempt = ++_connectionGeneration;
    final previousClient = _client;
    _client = account;
    state = state.copyWith(isConnecting: true, clearError: true);
    try {
      if (previousClient != null && !identical(previousClient, account)) {
        await previousClient.dispose();
      }
      if (_disposed || attempt != _connectionGeneration) return;
      _connectedAt = DateTime.now().toUtc();
      _lastCommandId = null;
      await _listen();
      if (_disposed || attempt != _connectionGeneration) return;
      state = state.copyWith(isAuthenticated: true, isConnecting: false);
    } catch (error) {
      if (_disposed || attempt != _connectionGeneration) return;
      state = state.copyWith(isConnecting: false, error: '$error');
    }
  }

  /// Signs in to the Supabase account that links the devices.
  Future<bool> connect({
    required String email,
    required String password,
  }) async {
    await _identityReady;
    if (_disposed || state.isConnecting) return false;
    if (!state.isConfigured) {
      state = state.copyWith(
        error: 'The Supabase credentials are not configured.',
      );
      return false;
    }

    final attempt = ++_connectionGeneration;
    state = state.copyWith(
      isConnecting: true,
      clearRemote: true,
      clearError: true,
    );
    try {
      await _ensureClient();
      final response = await _client!.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (_disposed || attempt != _connectionGeneration) return false;
      if (response.session == null) {
        state = state.copyWith(
          isConnecting: false,
          error: 'The sign in was refused.',
        );
        return false;
      }
      _connectedAt = DateTime.now().toUtc();
      _lastCommandId = null;
      await _listen();
      if (_disposed || attempt != _connectionGeneration) return false;
      state = state.copyWith(isAuthenticated: true, isConnecting: false);
      return true;
    } catch (error) {
      if (_disposed || attempt != _connectionGeneration) return false;
      state = state.copyWith(
        isAuthenticated: false,
        isConnecting: false,
        error: '$error',
      );
      return false;
    }
  }

  /// Signs out and stops listening.
  Future<void> disconnect() async {
    _connectionGeneration++;
    _listenGeneration++;
    _connectedAt = DateTime.now().toUtc();
    final client = _client;
    final channel = _channel;
    _channel = null;
    if (client != null && channel != null) {
      try {
        await client.removeChannel(channel);
      } catch (_) {}
    }
    if (identical(client, _accountClient)) {
      _client = null;
    } else {
      try {
        await client?.auth.signOut(scope: SignOutScope.local);
      } catch (_) {}
    }
    if (_disposed) return;
    state = state.copyWith(
      isAuthenticated: false,
      isConnecting: false,
      clearRemote: true,
    );
  }

  Future<SupabaseClient> _ensureClient() async {
    final existing = _client;
    if (existing != null) return existing;

    final client = SupabaseClient(
      supabaseUrl,
      supabaseAnonKey.isNotEmpty ? supabaseAnonKey : _publishableKey,
    );
    _client = client;
    return client;
  }

  /// Listens to the state published by the other device.
  Future<void> _listen() async {
    final generation = ++_listenGeneration;
    final client = _client;
    if (client == null) return;

    final previous = _channel;
    if (previous != null) {
      try {
        await client.removeChannel(previous);
      } catch (_) {}
    }

    final userId = client.auth.currentUser?.id;
    if (userId == null) throw StateError('Remote session expired.');
    final channel = client
        .channel(_channelName)
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
            if (_disposed || generation != _listenGeneration) return;
            if (remote.deviceId == state.deviceId) {
              if (!RemotePlaybackState.acceptsCommand(
                row,
                deviceId: state.deviceId,
                connectedAt: _connectedAt,
                lastCommandId: _lastCommandId,
              )) {
                return;
              }
              _lastCommandId = remote.commandId;
              state = state.copyWith(
                remote: (state.remote ?? const RemotePlaybackState())
                    .withCommand(remote),
              );
            } else {
              // Only commands addressed to this player may reach its listener.
              state = state.copyWith(
                remote: RemotePlaybackState.fromRow({
                  ...row,
                  'command': 'none',
                  'command_id': '',
                }),
              );
            }
          },
        )
        .subscribe((status, error) {
          if (_disposed || generation != _listenGeneration) return;
          if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) {
            state = state.copyWith(
              error: 'Remote connection interrupted: ${error ?? status.name}',
            );
          } else if (status == RealtimeSubscribeStatus.subscribed) {
            state = state.copyWith(clearError: true);
          }
        });

    _channel = channel;

    // The current state is read once, so the other device is shown even when
    // it does not change anything.
    try {
      final rows = await client
          .from(_table)
          .select('*')
          .eq('user_id', userId)
          .neq('device_id', state.deviceId)
          .order('updated_at', ascending: false)
          .limit(1);
      if (_disposed || generation != _listenGeneration) return;
      for (final row in rows) {
        final remote = RemotePlaybackState.fromRow({
          ...row,
          'command': 'none',
          'command_id': '',
        });
        if (remote.deviceId == state.deviceId) continue;
        state = state.copyWith(remote: remote);
      }
    } catch (error) {
      rethrow;
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
      final values = <String, dynamic>{
        'user_id': client.auth.currentUser!.id,
        'device_id': state.deviceId,
        'device_name': state.deviceName,
        'track_id': trackId,
        'track_title': trackTitle,
        'track_artist': trackArtist,
        'is_playing': isPlaying,
        'position_seconds': positionSeconds,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      // An upsert can replace omitted command columns with insert defaults.
      // Update only playback columns so a pending command survives publishing.
      final existing = await client
          .from(_table)
          .update(values)
          .eq('user_id', client.auth.currentUser!.id)
          .eq('device_id', state.deviceId)
          .select('device_id');
      if (existing.isEmpty) {
        await client
            .from(_table)
            .upsert(
              values,
              onConflict: 'user_id,device_id',
              ignoreDuplicates: true,
            );
      }
    } catch (error) {
      debugPrint('[remote] publish: $error');
      if (!_disposed) state = state.copyWith(error: '$error');
    }
  }

  /// Sends a command to the other device.
  Future<void> sendCommand(RemoteCommand command) async {
    final client = _client;
    if (client == null || !state.isAuthenticated) return;

    final target = state.remote;
    if (target == null ||
        target.deviceId == state.deviceId ||
        command == RemoteCommand.none) {
      return;
    }
    try {
      await client
          .from(_table)
          .update({
            'command': command.name,
            'command_id': const Uuid().v4(),
            'command_sender_id': state.deviceId,
            'command_created_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('user_id', client.auth.currentUser!.id)
          .eq('device_id', target.deviceId);
    } catch (error) {
      debugPrint('[remote] command: $error');
      if (!_disposed) state = state.copyWith(error: '$error');
    }
  }
}

/// The remote control provider.
final remoteControllerProvider =
    NotifierProvider<RemoteController, RemoteState>(RemoteController.new);
