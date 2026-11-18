import 'dart:io';

class ResolvedAudioStream {
  const ResolvedAudioStream({
    required this.url,
    required this.mimeType,
    this.durationMs = 0,
    this.headers = const {},
    this.videoUrl,
  });
  final String url, mimeType;
  final String? videoUrl;
  final int durationMs;
  final Map<String, String> headers;
  factory ResolvedAudioStream.local(String path, {int durationMs = 0}) =>
      ResolvedAudioStream(
        url: File(path).uri.toString(),
        mimeType: audioMimeFor(path),
        videoUrl: path.toLowerCase().endsWith('.mp4')
            ? File(path).uri.toString()
            : null,
        durationMs: durationMs,
      );
}

class InnertubeException implements Exception {
  const InnertubeException(this.message, [this.statusCode = 0]);
  final String message;
  final int statusCode;
  @override
  String toString() => 'Audio source ($statusCode): $message';
}

String audioMimeFor(String path) {
  final extension = Uri.tryParse(path)?.path.split('.').last.toLowerCase();
  return switch (extension) {
    'm4a' || 'mp4' => 'audio/mp4',
    'wav' => 'audio/wav',
    'flac' => 'audio/flac',
    'ogg' || 'opus' => 'audio/ogg',
    'aac' => 'audio/aac',
    'webm' => 'audio/webm',
    'aif' || 'aiff' => 'audio/aiff',
    _ => 'audio/mpeg',
  };
}
