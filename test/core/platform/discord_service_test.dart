import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:waveify/core/platform/discord_service.dart';

List<int> frame(int opcode, Object payload) {
  final body = utf8.encode(jsonEncode(payload));
  final header = ByteData(8)
    ..setUint32(0, opcode, Endian.little)
    ..setUint32(4, body.length, Endian.little);
  return [...header.buffer.asUint8List(), ...body];
}

void main() {
  test(
    'Unix IPC handshake, fragmented READY, activity, ping and disposal',
    () async {
      final directory = await Directory.systemTemp.createTemp('waveify-ipc');
      final path = '${directory.path}/discord-ipc-0';
      final server = await ServerSocket.bind(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      final service = DiscordService.forTesting([path]);
      final messages = <Map<String, dynamic>>[];
      final pong = Completer<void>();
      Socket? peer;
      final subscription = server.listen((socket) {
        peer = socket;
        final buffer = <int>[];
        socket.listen((bytes) {
          buffer.addAll(bytes);
          while (buffer.length >= 8) {
            final header = ByteData.sublistView(Uint8List.fromList(buffer));
            final opcode = header.getUint32(0, Endian.little);
            final size = header.getUint32(4, Endian.little);
            if (buffer.length < 8 + size) return;
            final payload = jsonDecode(
              utf8.decode(buffer.sublist(8, 8 + size)),
            );
            buffer.removeRange(0, 8 + size);
            if (opcode == 0) {
              expect(payload, {'v': 1, 'client_id': DiscordService.clientId});
              final ready = frame(1, {'evt': 'READY'});
              socket.add(ready.sublist(0, 3));
              socket.add(ready.sublist(3));
              socket.add(frame(3, {'hello': 'ping'}));
            } else if (opcode == 4) {
              expect(payload, {'hello': 'ping'});
              pong.complete();
            } else {
              messages.add(Map<String, dynamic>.from(payload as Map));
            }
          }
        });
      });
      try {
        await service.update(details: 'Song', state: 'Artist');
        await service.setEnabled(true);
        await pong.future.timeout(const Duration(seconds: 3));
        for (var attempt = 0; messages.isEmpty && attempt < 100; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(messages, isNotEmpty);
        expect(messages.first['cmd'], 'SET_ACTIVITY');
        expect(messages.first['nonce'], isA<String>());
        final args = messages.first['args'] as Map;
        expect(args.containsKey('nonce'), false);
        expect((args['activity'] as Map)['details'], 'Song');
        await service.dispose();
        expect(service.isEnabled, false);
      } finally {
        await service.dispose();
        peer?.destroy();
        await subscription.cancel();
        await server.close();
        await directory.delete(recursive: true);
      }
    },
    skip: !Platform.isLinux && !Platform.isMacOS,
  );

  test('reconnects after Discord closes IPC and stops on disable', () async {
    final directory = await Directory.systemTemp.createTemp(
      'waveify-reconnect',
    );
    final path = '${directory.path}/discord-ipc-0';
    final server = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    final service = DiscordService.forTesting([path]);
    final reconnected = Completer<void>();
    final peers = <Socket>[];
    final subscription = server.listen((socket) {
      peers.add(socket);
      socket.listen((_) {});
      if (peers.length == 1) {
        socket.add(frame(2, {'code': 1000}));
      } else if (!reconnected.isCompleted) {
        reconnected.complete();
      }
    });
    try {
      await service.setEnabled(true);
      await reconnected.future.timeout(const Duration(seconds: 3));
      await service.setEnabled(false);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(peers.length, 2);
      expect(service.isEnabled, false);
    } finally {
      await service.dispose();
      for (final peer in peers) {
        peer.destroy();
      }
      await subscription.cancel();
      await server.close();
      await directory.delete(recursive: true);
    }
  }, skip: !Platform.isLinux && !Platform.isMacOS);

  test('only valid HTTPS artwork URLs pass', () {
    expect(DiscordService.toDiscordImageUrl('https:///broken'), isNull);
    expect(DiscordService.toDiscordImageUrl('http://example.com/a'), isNull);
    expect(
      DiscordService.toDiscordImageUrl('https://example.com/a'),
      'https://example.com/a',
    );
  });
}
