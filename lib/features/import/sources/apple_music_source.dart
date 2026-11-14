/// The import of the Apple Music playlists and albums.
///
/// Port of `src/features/library/services/import/sources/appleMusic/`.
///
/// The catalog needs a developer token: it is read from the bundle of the web
/// player and cached for twelve hours.
library;

import '../../../core/utils/json.dart';
import '../matching/source_profile.dart';
import 'imported_playlist.dart';
import 'public_fetcher.dart';

const String _api = 'https://api.music.apple.com';

/// The catalog only answers to the requests that come from the web player.
const Map<String, String> _apiHeaders = {
  'origin': 'https://music.apple.com',
};
const Duration _tokenTtl = Duration(hours: 12);
const int _maxPages = 50;

/// The entity of an Apple Music URL.
class AppleMusicTarget {
  const AppleMusicTarget({
    required this.storefront,
    required this.type,
    required this.id,
  });

  final String storefront;
  final String type;
  final String id;
}

/// Reads the entity of an Apple Music URL.
AppleMusicTarget? parseAppleMusicUrl(String rawUrl) {
  final uri = Uri.tryParse(rawUrl.trim());
  if (uri == null || !uri.hasScheme) return null;

  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  var storefront = 'us';
  if (segments.isNotEmpty && RegExp(r'^[a-z]{2}$', caseSensitive: false).hasMatch(segments.first)) {
    storefront = segments.first.toLowerCase();
    segments.removeAt(0);
  }
  if (segments.isEmpty) return null;

  final typeSegment = segments.first.toLowerCase();
  final type = typeSegment == 'album'
      ? 'album'
      : typeSegment == 'playlist'
          ? 'playlist'
          : null;
  if (type == null) return null;

  final id = segments.last;
  if (id.isEmpty) return null;

  return AppleMusicTarget(storefront: storefront, type: type, id: id);
}

/// The Apple Music import source.
class AppleMusicSource {
  AppleMusicSource({PublicFetcher? fetcher})
      : _fetcher = fetcher ?? PublicFetcher();

  final PublicFetcher _fetcher;

  String? _token;
  DateTime? _tokenExpiry;

  /// Imports an Apple Music playlist or an album.
  Future<ImportedPlaylist> import(String rawUrl) async {
    final target = parseAppleMusicUrl(rawUrl);
    if (target == null) {
      throw StateError('The Apple Music URL is not valid.');
    }

    final token = await _developerToken();
    final resource = await _fetchResource(target, token);
    if (resource == null) {
      throw StateError('The Apple Music item was not found.');
    }

    // The tracks live in the relationships of the resource.
    final relationships = asRecord(resource['relationships']);
    final trackList = asRecord(relationships?['tracks']);
    final tracks = <ImportedTrack>[];
    _append(tracks, asArray(trackList?['data']));

    // The track list is paginated.
    var next = trimmedString(trackList?['next']);
    var page = 0;
    while (next != null && page < _maxPages) {
      page += 1;
      final url = next.startsWith('http') ? next : '$_api$next';
      final body = await _fetcher.json(url, headers: {
        ..._apiHeaders,
        'authorization': 'Bearer $token',
      });
      final data = asArray(body['data']);
      if (data.isEmpty) break;
      final before = tracks.length;
      _append(tracks, data);
      if (tracks.length == before) break;
      next = trimmedString(body['next']);
    }

    final attributes = asRecord(resource['attributes']);
    final title = trimmedString(attributes?['name']) ??
        trimmedString(attributes?['title']) ??
        'Imported Apple Music playlist';
    final description = asRecord(attributes?['description']);

    return ImportedPlaylist(
      source: 'appleMusic',
      sourceUrl: rawUrl,
      title: title,
      description: trimmedString(description?['standard']) ??
          trimmedString(description?['short']) ??
          '',
      author: trimmedString(asRecord(attributes?['artistName'])) ?? '',
      coverUrl: _artworkUrl(attributes),
      tracks: tracks,
    );
  }

  Future<Map<String, dynamic>?> _fetchResource(
    AppleMusicTarget target,
    String token,
  ) async {
    // The track list comes with the relationships, they have to be asked for.
    final url = '$_api/v1/catalog/${target.storefront}/${target.type}s/'
        '${Uri.encodeComponent(target.id)}'
        '?include=tracks';

    try {
      final body = await _fetcher.json(url, headers: {
        ..._apiHeaders,
        'authorization': 'Bearer $token',
      });
      final resource = asRecord(asArray(body['data']).first);
      if (resource != null) return resource;
    } catch (_) {
      // The storefront is tried again below.
    }

    if (target.storefront != 'us') {
      final fallback = await _fetcher.json(
        '$_api/v1/catalog/us/${target.type}s/'
        '${Uri.encodeComponent(target.id)}'
        '?include=tracks',
        headers: {
          ..._apiHeaders,
          'authorization': 'Bearer $token',
        },
      );
      final resource = asRecord(asArray(fallback['data']).first);
      if (resource != null) return resource;
    }
    return null;
  }

  /// The developer token, read from the bundle of the web player.
  Future<String> _developerToken() async {
    final cached = _token;
    final expiry = _tokenExpiry;
    if (cached != null && expiry != null && DateTime.now().isBefore(expiry)) {
      return cached;
    }

    final html = await _fetcher.text('https://music.apple.com/us/browse');
    final script = _pickIndexScript(html);
    if (script == null) {
      throw StateError('The Apple Music web scripts were not found.');
    }

    final scriptUrl = script.startsWith('http')
        ? script
        : 'https://music.apple.com$script';
    final js = await _fetcher.text(scriptUrl);

    final token = extractAppleMusicToken(js);
    if (token == null) {
      throw StateError(
        'The Apple Music developer token could not be read from the web bundle.',
      );
    }

    _token = token;
    _tokenExpiry = DateTime.now().add(_tokenTtl);
    return token;
  }

  static String? _pickIndexScript(String html) {
    final scripts = RegExp(r'src="([^"]+\.js)"')
        .allMatches(html)
        .map((m) => m.group(1)!)
        .toList();
    for (final src in scripts) {
      if (src.contains('index~') ||
          src.contains('index-') ||
          src.contains('index.js')) {
        return src;
      }
    }
    return scripts.isEmpty ? null : scripts.first;
  }

  /// Extracts the developer token from the bundle.
  static String? extractAppleMusicToken(String js) {
    final developer = RegExp(r'developerToken:\s*([a-zA-Z0-9_$]+)').firstMatch(js);
    if (developer != null) {
      final name = RegExp.escape(developer.group(1)!);
      final withDeclaration = RegExp(
        '(?:const|let|var|,|;)\\s*$name\\s*=\\s*"([^"]+)"',
      ).firstMatch(js);
      final simple = RegExp('$name\\s*=\\s*"([^"]+)"').firstMatch(js);
      final value = withDeclaration?.group(1) ?? simple?.group(1);
      if (value != null) return value;
    }
    return RegExp(r'eyJhbGciOiJ[a-zA-Z0-9_\-.]+').firstMatch(js)?.group(0);
  }

  void _append(List<ImportedTrack> tracks, List<Object?> items) {
    for (final raw in items) {
      final item = asRecord(raw);
      final attributes = asRecord(item?['attributes']);
      if (item == null || attributes == null) continue;

      final title = trimmedString(attributes['name']);
      if (title == null) continue;

      final rawArtist = trimmedString(attributes['artistName']) ?? '';
      final artists = rawArtist.isEmpty
          ? const <String>['Apple Music Artist']
          : rawArtist
              .split(RegExp(r'(?:,\s*|\s*&\s*)'))
              .map((a) => a.trim())
              .where((a) => a.isNotEmpty)
              .toList();

      tracks.add(
        ImportedTrack(
          id: '${asRecord(attributes['playParams'])?['id'] ?? item['id'] ?? ''}',
          title: title,
          artists: artists.isEmpty ? const ['Apple Music Artist'] : artists,
          album: trimmedString(attributes['albumName']) ?? '',
          durationMs: (attributes['durationInMillis'] as num?)?.round(),
          coverUrl: _artworkUrl(attributes),
        ),
      );
    }
  }

  static String _artworkUrl(Map<String, dynamic>? attributes) {
    final url = trimmedString(asRecord(attributes?['artwork'])?['url']);
    if (url == null) return '';
    return url.replaceAll('{w}', '400').replaceAll('{h}', '400');
  }
}
