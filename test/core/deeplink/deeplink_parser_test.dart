import 'package:flutter_test/flutter_test.dart';
import 'package:waveify/core/deeplink/deeplink_parser.dart';

void main() {
  group('parseDeepLink', () {
    test('accepts a valid artist link', () {
      final target = parseDeepLink(
        'waveify://artist?id=UCrXh37Y9LZk5D2KSi2O1cAx',
      );
      expect(target, isNotNull);
      expect(target!.type, DeepLinkType.artist);
      expect(target.id, 'UCrXh37Y9LZk5D2KSi2O1cAx');
    });

    test('accepts a valid album link', () {
      final target = parseDeepLink('waveify://album?id=MPREb_xCxkOKReFZv');
      expect(target?.type, DeepLinkType.album);
    });

    test('accepts a valid playlist link', () {
      final target = parseDeepLink('waveify://playlist?id=VLPLZ0oqv-_vPEM');
      expect(target?.type, DeepLinkType.playlist);
    });

    test('accepts a valid track link', () {
      final target = parseDeepLink('waveify://track?id=dQw4w9WgXcQ');
      expect(target?.type, DeepLinkType.track);
      expect(target?.id, 'dQw4w9WgXcQ');
    });

    test('rejects another scheme', () {
      expect(
        parseDeepLink('https://artist?id=UCrXh37Y9LZk5D2KSi2O1cAx'),
        isNull,
      );
      expect(
        parseDeepLink('spotify://artist?id=UCrXh37Y9LZk5D2KSi2O1cAx'),
        isNull,
      );
    });

    test('rejects an unknown entity type', () {
      expect(parseDeepLink('waveify://user?id=whatever'), isNull);
    });

    test('rejects a malformed id', () {
      // An artist id is always UC + 22 characters.
      expect(parseDeepLink('waveify://artist?id=tooshort'), isNull);
      // A track id is always 11 characters.
      expect(parseDeepLink('waveify://track?id=short'), isNull);
    });

    test('rejects a link without an id', () {
      expect(parseDeepLink('waveify://artist'), isNull);
      expect(parseDeepLink('waveify://artist?id='), isNull);
    });

    test('rejects a link with several ids', () {
      expect(
        parseDeepLink(
          'waveify://artist?id=UCrXh37Y9LZk5D2KSi2O1cAx&id=UCrXh37Y9LZk5D2KSi2O1cB',
        ),
        isNull,
      );
    });

    test('rejects a malformed url', () {
      expect(parseDeepLink('not a url at all'), isNull);
      expect(parseDeepLink(''), isNull);
    });

    test('is case insensitive on the entity type', () {
      final target = parseDeepLink(
        'waveify://ARTIST?id=UCrXh37Y9LZk5D2KSi2O1cAx',
      );
      expect(target?.type, DeepLinkType.artist);
    });
  });

  group('isUserPlaylistId', () {
    test('recognises the user playlist ids', () {
      expect(isUserPlaylistId('pl-abc123'), isTrue);
      expect(
        isUserPlaylistId('8f3610fe-5171-4167-9e67-7a1d0f8d9bb4'),
        isTrue,
      );
    });

    test('rejects the catalog ids', () {
      expect(isUserPlaylistId('VLPLZ0oqv-_vPEM'), isFalse);
      expect(isUserPlaylistId('MPREb_xCxkOKReFZv'), isFalse);
    });
  });

  group('findDeepLinkArgument', () {
    test('finds the link among the arguments', () {
      final found = findDeepLinkArgument([
        '/usr/bin/waveify',
        '--no-sandbox',
        'waveify://track?id=dQw4w9WgXcQ',
      ]);
      expect(found, 'waveify://track?id=dQw4w9WgXcQ');
    });

    test('returns null when there is no link', () {
      expect(findDeepLinkArgument(['/usr/bin/waveify']), isNull);
    });
  });
}
