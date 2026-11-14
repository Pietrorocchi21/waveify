import 'package:flutter_test/flutter_test.dart';
import 'package:waveify/features/import/sources/apple_music_source.dart';
import 'package:waveify/features/import/sources/deezer_source.dart';
import 'package:waveify/features/import/sources/import_source.dart';
import 'package:waveify/features/import/sources/spotify_source.dart';
import 'package:waveify/features/import/sources/youtube_source.dart';

void main() {
  group('detectImportSource', () {
    test('detects a YouTube playlist', () {
      final source = detectImportSource(
        'https://www.youtube.com/playlist?list=PLZ0oqv-_vPEM',
      );
      expect(source.kind, ImportSourceKind.youtube);
      expect(source.id, 'VLPLZ0oqv-_vPEM');
      expect(source.type, 'playlist');
    });

    test('detects a YouTube video', () {
      final source = detectImportSource(
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
      expect(source.kind, ImportSourceKind.youtube);
      expect(source.id, 'dQw4w9WgXcQ');
      expect(source.type, 'video');
    });

    test('detects a Spotify playlist', () {
      final source = detectImportSource(
        'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M',
      );
      expect(source.kind, ImportSourceKind.spotify);
      expect(source.id, '37i9dQZF1DXcBWIGoYBM5M');
      expect(source.type, 'playlist');
    });

    test('detects a Spotify album', () {
      final source = detectImportSource(
        'https://open.spotify.com/album/1ATL5GLyefJaxhQzSPVrLX',
      );
      expect(source.kind, ImportSourceKind.spotify);
      expect(source.type, 'album');
    });

    test('detects a Deezer playlist', () {
      final source = detectImportSource(
        'https://www.deezer.com/en/playlist/908622995',
      );
      expect(source.kind, ImportSourceKind.deezer);
      expect(source.id, '908622995');
    });

    test('detects an Apple Music album', () {
      final source = detectImportSource(
        'https://music.apple.com/us/album/random-access-memories/617154241',
      );
      expect(source.kind, ImportSourceKind.appleMusic);
      expect(source.id, '617154241');
      expect(source.type, 'album');
    });

    test('does not support an unknown link', () {
      final source = detectImportSource('https://example.com/playlist');
      expect(source.kind, ImportSourceKind.unknown);
      expect(source.isSupported, isFalse);
    });
  });

  group('parseSpotifyUrl', () {
    test('reads the id of a playlist', () {
      final entity = parseSpotifyUrl(
        'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M',
      );
      expect(entity?.type, SpotifyEntityType.playlist);
      expect(entity?.id, '37i9dQZF1DXcBWIGoYBM5M');
    });

    test('reads the id of an embed url', () {
      final entity = parseSpotifyUrl(
        'https://open.spotify.com/embed/album/1ATL5GLyefJaxhQzSPVrLX',
      );
      expect(entity?.type, SpotifyEntityType.album);
      expect(entity?.id, '1ATL5GLyefJaxhQzSPVrLX');
    });

    test('rejects an invalid url', () {
      expect(parseSpotifyUrl('not a url'), isNull);
      expect(parseSpotifyUrl('https://open.spotify.com/'), isNull);
    });
  });

  group('parseAppleMusicUrl', () {
    test('reads the storefront, the type and the id', () {
      final target = parseAppleMusicUrl(
        'https://music.apple.com/it/playlist/x/pl.u-abc',
      );
      expect(target?.storefront, 'it');
      expect(target?.type, 'playlist');
      expect(target?.id, 'pl.u-abc');
    });

    test('defaults to the us storefront', () {
      final target = parseAppleMusicUrl(
        'https://music.apple.com/album/x/617154241',
      );
      expect(target?.storefront, 'us');
      expect(target?.type, 'album');
    });

    test('rejects an invalid url', () {
      expect(parseAppleMusicUrl('not a url'), isNull);
      expect(parseAppleMusicUrl('https://music.apple.com/us/'), isNull);
    });
  });

  group('AppleMusicSource.extractAppleMusicToken', () {
    test('reads the token from the bundle', () {
      const bundle = 'const qa="eyJhbGciOiJFUzI1NiJ9.abc.def";'
          'return{developerToken:qa};';
      expect(
        AppleMusicSource.extractAppleMusicToken(bundle),
        'eyJhbGciOiJFUzI1NiJ9.abc.def',
      );
    });

    test('falls back to the jwt of the bundle', () {
      const bundle = 'const x="eyJhbGciOiJFUzI1NiIsImtpZCI6IkxUMlpEWlNYTlEi.payload.sig";';
      expect(
        AppleMusicSource.extractAppleMusicToken(bundle),
        'eyJhbGciOiJFUzI1NiIsImtpZCI6IkxUMlpEWlNYTlEi.payload.sig',
      );
    });

    test('returns null when there is no token', () {
      expect(AppleMusicSource.extractAppleMusicToken('var a = 1;'), isNull);
    });
  });

  group('DeezerSource.idFromUrl', () {
    test('reads the numeric id', () {
      expect(
        DeezerSource.idFromUrl('https://www.deezer.com/en/playlist/908622995'),
        '908622995',
      );
    });

    test('rejects a link without an id', () {
      expect(DeezerSource.idFromUrl('https://www.deezer.com/en/playlist'), isNull);
    });
  });

  group('YoutubeSource', () {
    test('reads the playlist id', () {
      expect(
        YoutubeSource.playlistIdFromYoutube(
          'https://www.youtube.com/playlist?list=PLZ0oqv-_vPEM',
        ),
        'VLPLZ0oqv-_vPEM',
      );
    });

    test('reads the video id', () {
      expect(
        YoutubeSource.videoIdFromYoutube(
          'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        ),
        'dQw4w9WgXcQ',
      );
      expect(
        YoutubeSource.videoIdFromYoutube('https://youtu.be/dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
    });
  });
}
