import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';

import '../../core/utils/json.dart';
import '../../models/lyrics.dart';

/// Streams lyrics events from the backend SSE endpoint.
///
/// Mirrors `api.streamLyrics` in `src/shared/api/api.ts`: the server pushes
/// one candidate per provider as it resolves them, then a final `done` event.
class LyricsStream {
  LyricsStream({required this.client});

  final ApiClient client;

  /// Opens the lyrics stream for a track.
  Stream<LyricsStreamEvent> events({
    required String trackId,
    String? title,
    String? artist,
    int? durationMs,
    CancelToken? cancelToken,
  }) async* {
    final query = <String, dynamic>{};
    if (title != null &&
        title.trim().isNotEmpty &&
        artist != null &&
        artist.trim().isNotEmpty) {
      query['title'] = title.trim();
      query['artist'] = artist.trim();
      if (durationMs != null && durationMs > 0) {
        query['durationMs'] = durationMs.round();
      }
    }

    final body = await client.stream(
      '/v1/tracks/${Uri.encodeComponent(trackId)}/lyrics',
      query: query.isEmpty ? null : query,
      cancelToken: cancelToken,
    );

    final buffer = StringBuffer();
    await for (final chunk in body.stream.cast<List<int>>().transform(
      const Utf8Decoder(allowMalformed: true),
    )) {
      buffer.write(chunk);
      var text = buffer.toString().replaceAll('\r\n', '\n');

      while (true) {
        final separator = text.indexOf('\n\n');
        if (separator == -1) break;

        final rawEvent = text.substring(0, separator);
        text = text.substring(separator + 2);
        buffer
          ..clear()
          ..write(text);

        final event = _parseEvent(rawEvent);
        if (event != null) yield event;
      }
    }

    // The last event of the stream is not followed by a blank line: it is
    // flushed here, otherwise the "done" event would be lost.
    final rest = buffer.toString().trim();
    if (rest.isNotEmpty) {
      final event = _parseEvent(rest);
      if (event != null) yield event;
    }
  }

  LyricsStreamEvent? _parseEvent(String rawEvent) {
    final dataLines = <String>[];
    for (final line in rawEvent.split('\n')) {
      if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trim());
      }
    }
    if (dataLines.isEmpty) return null;

    try {
      final decoded = jsonDecode(dataLines.join('\n'));
      if (decoded is! Map) return null;
      return parseLyricsEvent(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }
}

/// Parses one SSE payload into a typed event.
LyricsStreamEvent? parseLyricsEvent(Map<String, dynamic> json) {
  final type = asString(json['type']);

  switch (type) {
    case 'metadata':
      final track = asRecord(json['track']);
      return LyricsMetadataEvent(
        asString(track?['title']),
        (track?['artists'] as List?)
                ?.map((e) => asString(asRecord(e)?['name']))
                .toList(growable: false) ??
            const [],
        asInt(track?['durationMs']),
      );

    case 'provider':
      final provider = asString(json['provider']);
      final status = asString(json['status']);
      final durationMs = json['durationMs'] == null
          ? null
          : asInt(json['durationMs']);

      if (status == 'found') {
        return LyricsProviderFoundEvent(
          LyricsCandidate.fromJson(asRecord(json['candidate'])),
          durationMs,
        );
      }
      if (status == 'not_found') {
        return LyricsProviderNotFoundEvent(provider, durationMs);
      }
      if (status == 'error') {
        return LyricsProviderErrorEvent(
          provider,
          asString(json['message']),
          durationMs,
        );
      }
      return null;

    case 'done':
      final best = asRecord(json['best']);
      return LyricsDoneEvent(
        cached: asBool(json['cached']),
        bestProvider: best == null ? null : asStringOrNull(best['provider']),
        bestQuality: best == null ? null : asInt(best['quality']),
        bestSyncLevel: best == null
            ? null
            : LyricsSyncLevel.fromRaw(asStringOrNull(best['syncLevel'])),
        status: asStringOrNull(json['status']),
      );
  }

  return null;
}
