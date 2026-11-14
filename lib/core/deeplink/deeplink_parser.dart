/// Parsing of the `waveify://` deep links.
///
/// Deep links are strictly validated so only safe opaque ids are accepted.
library;

const String deepLinkScheme = 'waveify';

/// The entity types a deep link can point at.
enum DeepLinkType { artist, album, playlist, track }

/// The target of a deep link.
class DeepLinkTarget {
  const DeepLinkTarget({required this.type, required this.id});

  final DeepLinkType type;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is DeepLinkTarget && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);

  @override
  String toString() => 'DeepLinkTarget(${type.name}, $id)';
}

/// The accepted id shapes, one per entity type.
final Map<DeepLinkType, RegExp> _deepLinkIds = {
  // YouTube channel ids: always UC + 22 base64url characters.
  DeepLinkType.artist: RegExp(r'^UC[A-Za-z0-9_-]{22}$'),
  // InnerTube album browse ids, e.g. MPREb_xCxkOKReFZv.
  DeepLinkType.album: RegExp(r'^MPRE[A-Za-z0-9_-]{4,64}$'),
  // Catalog playlists (VLPL…/PL…) and user playlists (uuid / pl-…), all
  // opaque tokens from the same safe charset.
  DeepLinkType.playlist: RegExp(r'^[A-Za-z0-9_-]{8,64}$'),
  // YouTube video ids are always 11 base64url characters.
  DeepLinkType.track: RegExp(r'^[A-Za-z0-9_-]{11}$'),
};

/// True when the id belongs to a user playlist rather than to the catalog.
bool isUserPlaylistId(String id) {
  if (id.startsWith('pl-')) return true;
  return RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  ).hasMatch(id);
}

/// Parses a `waveify://` link.
///
/// Returns null when the link does not match the scheme, the entity type or
/// the id shape. Exactly one `id` parameter is required, so a link with
/// several ids cannot pick a winner.
DeepLinkTarget? parseDeepLink(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null) return null;
  if (uri.scheme.toLowerCase() != deepLinkScheme) return null;

  final type = _typeFromHost(uri.host);
  if (type == null) return null;

  final ids = uri.queryParametersAll['id'] ?? const [];
  if (ids.length != 1) return null;

  final id = ids.first;
  final pattern = _deepLinkIds[type]!;
  if (!pattern.hasMatch(id)) return null;

  return DeepLinkTarget(type: type, id: id);
}

DeepLinkType? _typeFromHost(String host) {
  switch (host.toLowerCase()) {
    case 'artist':
      return DeepLinkType.artist;
    case 'album':
      return DeepLinkType.album;
    case 'playlist':
      return DeepLinkType.playlist;
    case 'track':
      return DeepLinkType.track;
    default:
      return null;
  }
}

/// Finds the first deep link among the command line arguments.
String? findDeepLinkArgument(List<String> argv) {
  for (final argument in argv) {
    if (argument.startsWith('$deepLinkScheme://')) return argument;
  }
  return null;
}
