import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import 'dart:io';

import '../../../models/track.dart';
import '../audius/audius_catalog.dart';
import '../resolved_audio_stream.dart';
export '../resolved_audio_stream.dart';
import '../../config/app_config.dart';
import '../../network/waveify_api.dart';

/// Resolves real file/HTTP sources. Unknown provider IDs require a configured
/// backend; they are never turned into fabricated URLs.
class StreamResolver {
  StreamResolver({this.api, this.youtube, this.audius});
  final AudiusCatalog? audius;
  final WaveifyApi? api;
  final yt.YoutubeExplode? youtube;
  static String mimeFor(String path) => audioMimeFor(path);

  Future<ResolvedAudioStream> resolveTrackStream(
    Track track, {
    bool forDownload = false,
  }) {
    if (track.id.startsWith('audius:')) {
      return _resolveAudius(track.id, forDownload: forDownload);
    }
    final source = track.sourceUrl;
    if (source.startsWith('storage:')) {
      return resolveDirectAudioStream(track.id);
    }
    return resolveDirectAudioStream(source.isEmpty ? track.id : source);
  }

  Future<ResolvedAudioStream> _resolveAudius(
    String id, {
    bool forDownload = false,
  }) async {
    final client = audius ?? AudiusCatalog();
    try {
      return await client.resolveStream(id, requireDownload: forDownload);
    } finally {
      if (audius == null) client.close();
    }
  }

  Future<ResolvedAudioStream> resolveDirectAudioStream(String id) async {
    if (id.startsWith('audius:')) return _resolveAudius(id);
    final uri = Uri.tryParse(id);
    if (uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty &&
        !uri.host.endsWith('youtube.com') &&
        uri.host != 'youtu.be') {
      return ResolvedAudioStream(
        url: uri.toString(),
        mimeType: mimeFor(uri.path),
      );
    }
    if (uri?.scheme == 'file' ||
        id.startsWith('/') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(id)) {
      final file = uri?.scheme == 'file' ? File.fromUri(uri!) : File(id);
      if (!await file.exists()) {
        throw const InnertubeException('The audio file is missing.', 404);
      }
      return ResolvedAudioStream.local(file.path);
    }
    final videoId =
        toVideoId(id) ??
        (id.contains('youtube.com/') || id.contains('youtu.be/')
            ? yt.VideoId.parseVideoId(id)
            : null);
    if (videoId != null) {
      final client = youtube ?? yt.YoutubeExplode();
      try {
        final manifest = await client.videos.streamsClient
            .getManifest(videoId)
            .timeout(const Duration(seconds: 20));
        final streams = manifest.audioOnly.toList()
          ..sort(
            (a, b) =>
                b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond),
          );
        if (streams.isEmpty) {
          throw const InnertubeException(
            'This video has no accessible audio stream.',
            404,
          );
        }
        final stream = streams.first;
        return ResolvedAudioStream(
          url: stream.url.toString(),
          mimeType: stream.container.name == 'mp4' ? 'audio/mp4' : 'audio/webm',
        );
      } finally {
        if (youtube == null) client.close();
      }
    }
    if (api == null) {
      throw const InnertubeException(
        'This source requires a configured media provider.',
        501,
      );
    }
    final result = await api!.getTrackStream(id);
    var url = '${result['url'] ?? result['streamUrl'] ?? ''}';
    if (url.startsWith('/')) url = AppConfig.mediaUrl(url);
    if (url.isEmpty || url == id) {
      throw const InnertubeException('No playable source was returned.', 404);
    }
    final stream = await resolveDirectAudioStream(url);
    return ResolvedAudioStream(
      url: stream.url,
      mimeType: '${result['mimeType'] ?? stream.mimeType}',
      durationMs: (result['durationMs'] as num?)?.toInt() ?? 0,
      headers: (result['headers'] as Map? ?? {}).map(
        (key, value) => MapEntry('$key', '$value'),
      ),
    );
  }

  static String? toVideoId(String id) =>
      id.length == 11 && RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id) ? id : null;
}
