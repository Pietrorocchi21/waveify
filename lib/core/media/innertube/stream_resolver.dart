/// Generic stream resolution used by the player.
class ResolvedAudioStream {
  const ResolvedAudioStream({
    required this.url,
    required this.mimeType,
    this.durationMs = 0,
  });

  final String url;
  final String mimeType;
  final int durationMs;

  factory ResolvedAudioStream.local(String path, {int durationMs = 0}) =>
      ResolvedAudioStream(
        url: path,
        mimeType: 'audio/mpeg',
        durationMs: durationMs,
      );
}

class InnertubeException implements Exception {
  const InnertubeException(this.message, [this.statusCode = 0]);

  final String message;
  final int statusCode;

  @override
  String toString() => 'InnertubeException($statusCode): $message';
}

class StreamResolver {
  Future<ResolvedAudioStream> resolveDirectAudioStream(String id) async {
    final fallbackUrl = id.startsWith('http') ? id : 'https://example.invalid/audio/$id';
    return ResolvedAudioStream(
      url: fallbackUrl,
      mimeType: 'audio/mpeg',
      durationMs: 0,
    );
  }

  static String? toVideoId(String id) {
    if (id.length == 11 && RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
      return id;
    }
    return null;
  }
}
