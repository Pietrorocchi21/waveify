/// Generic audio-format metadata used by the player and import helpers.
class AudioFormat {
  const AudioFormat({
    required this.mimeType,
    required this.quality,
    required this.url,
    this.bitrate = 0,
  });

  final String mimeType;
  final String quality;
  final String url;
  final int bitrate;
}

class AudioFormats {
  const AudioFormats._();

  static const List<AudioFormat> empty = <AudioFormat>[];
}
