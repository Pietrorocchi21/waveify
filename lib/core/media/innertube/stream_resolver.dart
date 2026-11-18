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
        videoUrl: uri.path.toLowerCase().endsWith('.mp4')
            ? uri.toString()
            : null,
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
        final manifest = await _youtubeManifest(client, videoId);
        final audio = _rankAudio(manifest.audioOnly);
        final muxed = manifest.muxed.toList()
          ..sort(
            (left, right) => left.bitrate.bitsPerSecond.compareTo(
              right.bitrate.bitsPerSecond,
            ),
          );
        if (audio.isEmpty && muxed.isEmpty) {
          throw const InnertubeException(
            'This video has no accessible audio stream.',
            404,
          );
        }
        final yt.StreamInfo stream = audio.firstOrNull ?? muxed.first;
        final video = manifest.videoOnly.toList()
          ..sort((left, right) {
            final leftHeight = left.videoResolution.height;
            final rightHeight = right.videoResolution.height;
            if (leftHeight <= 480 && rightHeight <= 480) {
              return rightHeight.compareTo(leftHeight);
            }
            return leftHeight.compareTo(rightHeight);
          });
        return ResolvedAudioStream(
          url: stream.url.toString(),
          mimeType: stream.container.name == 'mp4' ? 'audio/mp4' : 'audio/webm',
          videoUrl: (video.firstOrNull ?? muxed.firstOrNull)?.url.toString(),
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
      videoUrl: stream.videoUrl,
      headers: (result['headers'] as Map? ?? {}).map(
        (key, value) => MapEntry('$key', '$value'),
      ),
    );
  }

  Future<yt.StreamManifest> _youtubeManifest(
    yt.YoutubeExplode client,
    String videoId,
  ) async {
    try {
      final direct = await client.videos.streamsClient
          .getManifest(
            videoId,
            ytClients: [yt.YoutubeApiClient.androidSdkless],
            requireWatchPage: false,
          )
          .timeout(const Duration(seconds: 8));
      if (direct.audioOnly.isNotEmpty || direct.muxed.isNotEmpty) return direct;
    } catch (_) {
      // Some public videos require the library's standard watch-page flow.
    }
    return client.videos.streamsClient
        .getManifest(videoId)
        .timeout(const Duration(seconds: 12));
  }

  List<yt.AudioOnlyStreamInfo> _rankAudio(
    Iterable<yt.AudioOnlyStreamInfo> streams,
  ) => streams.toList()
    ..sort((left, right) {
      final leftMp4 = left.container.name == 'mp4';
      final rightMp4 = right.container.name == 'mp4';
      if (leftMp4 != rightMp4) return leftMp4 ? -1 : 1;
      return right.bitrate.bitsPerSecond.compareTo(left.bitrate.bitsPerSecond);
    });

  static String? toVideoId(String id) =>
      id.length == 11 && RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id) ? id : null;
}
