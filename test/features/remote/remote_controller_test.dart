import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:waveify/features/remote/remote_controller.dart';

void main() {
  final connected = DateTime.utc(2026, 11, 14);
  final command = <String, dynamic>{
    'device_id': 'player',
    'command_sender_id': 'controller',
    'command': 'next',
    'command_id': 'command-1',
    'command_created_at': '2026-11-14T00:00:01Z',
    'track_id': 'youtube:video-id',
  };
  bool accepts(Map<String, dynamic> row, {String? last}) =>
      RemotePlaybackState.acceptsCommand(
        row,
        deviceId: 'player',
        connectedAt: connected,
        lastCommandId: last,
      );

  test('accepts a fresh command only for the intended player', () {
    expect(accepts(command), isTrue);
    expect(accepts({...command, 'device_id': 'another-player'}), isFalse);
    expect(accepts({...command, 'command_sender_id': 'player'}), isFalse);
    expect(accepts(command, last: 'command-1'), isFalse);
    expect(accepts({...command, 'command_id': ''}), isFalse);
    expect(accepts({...command, 'command': 'none'}), isFalse);
    expect(accepts({...command, 'command': 'future-command'}), isFalse);
    expect(
      accepts({...command, 'command_created_at': '2026-11-13T23:59:59Z'}),
      isFalse,
    );
    expect(accepts({...command, 'command_created_at': null}), isFalse);
  });

  test('wire format preserves non-UUID media IDs and command keeps target metadata', () {
    final incoming = RemotePlaybackState.fromRow(command);
    expect(incoming.trackId, 'youtube:video-id');
    const target = RemotePlaybackState(
      deviceId: 'other',
      trackId: '/music/file.mp3',
    );
    final displayed = target.withCommand(incoming);
    expect(displayed.deviceId, 'other');
    expect(displayed.trackId, '/music/file.mp3');
    expect(displayed.command, RemoteCommand.next);
    expect(displayed.commandId, 'command-1');
  });

  test('device UUID survives controller recreation', () async {
    SharedPreferences.setMockInitialValues({});
    final first = ProviderContainer();
    first.read(remoteControllerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final id = first.read(remoteControllerProvider).deviceId;
    expect(
      id,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    first.dispose();
    final second = ProviderContainer();
    second.read(remoteControllerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(second.read(remoteControllerProvider).deviceId, id);
    second.dispose();
  });
}
