import 'package:flutter_test/flutter_test.dart';
import 'package:waveify/features/import/matching/artist_title.dart';
import 'package:waveify/features/import/matching/artists.dart';
import 'package:waveify/features/import/matching/junk.dart';
import 'package:waveify/features/import/matching/phonetic.dart';
import 'package:waveify/features/import/matching/similarity.dart';
import 'package:waveify/features/import/matching/version_tags.dart';

/// The expectations come from the test suite of the Electron client
/// (`src/shared/media/matching/text.test.ts`): the port has to behave exactly
/// like the original.
void main() {
  group('similarity', () {
    test('tokenSortRatio handles the inverted word orders', () {
      expect(tokenSortRatio('Кино - Кукушка', 'Кукушка Кино'), 100);
      expect(
        tokenSortRatio(
          'Pharaoh & Boulevard Depo',
          'Boulevard Depo, Pharaoh',
        ),
        100,
      );
    });

    test('tokenSetRatio rewards the subsets', () {
      expect(
        tokenSetRatio('в машине целуемся', 'мы в машине с тобой целуемся'),
        73,
      );
      expect(tokenSetRatio('abc', 'xyz'), 0);
    });

    test('computes the levenshtein distance', () {
      expect(levenshtein('kitten', 'sitting'), 3);
      expect(levenshtein('', 'abc'), 3);
    });
  });

  group('phonetic', () {
    test('transliterates the cyrillic', () {
      expect(
        toPhoneticLatin('Пошлая Молли'),
        toPhoneticLatin('Poshlaya Molly'),
      );
    });
  });

  group('artists', () {
    test('matches the known aliases', () {
      expect(artistsMatch('Кино', 'Виктор Цой'), isTrue);
      expect(artistsMatch('Pharaoh', 'Фараон'), isTrue);
      expect(artistsMatch('Skrillex', 'Kavinsky'), isFalse);
    });
  });

  group('version tags', () {
    test('detects the tags', () {
      final tags = getVersionTags('Nightcall (Slowed + Reverb)').toList()..sort();
      expect(tags, ['reverb', 'slowed']);
    });

    test('compares the tags', () {
      final both = compareVersionTags({}, {});
      expect(both.matches, isTrue);
      expect(both.penalty, 0);
      expect(both.bonus, 5);

      final one = compareVersionTags({'remix'}, {});
      expect(one.matches, isFalse);
      expect(one.penalty, 50);
      expect(one.bonus, 0);
    });
  });

  group('junk', () {
    test('strips the junk and the search noise', () {
      expect(stripJunk('Track (Official Video) @handle'), 'Track');
      expect(cleanSearchTitle('Song (Official Music Video) [Explicit]'), 'Song');
    });
  });

  group('artist and title', () {
    test('parses the artist and title pairs', () {
      final pair = parseArtistAndTitle('Doja Cat - Say So');
      expect(pair.artist, 'Doja Cat');
      expect(pair.title, 'Say So');

      final triple = parseArtistAndTitle('Uploader - Artist - Title');
      expect(triple.artist, 'Artist');
      expect(triple.title, 'Title');

      final plain = parseArtistAndTitle('Plain Title');
      expect(plain.artist, isNull);
      expect(plain.title, 'Plain Title');
    });

    test('cleans the metadata keeping the artist and the version tags', () {
      final first = cleanSourceMetadata(
        'Skrillex - Scary Monsters (VIP Flip) [FREE DL] (prod by Skrillex)',
        'DubstepNation',
      );
      expect(first.artist, 'Skrillex');
      expect(first.title, 'Scary Monsters (VIP Flip)');
      expect(first.searchQuery, 'Skrillex Scary Monsters (VIP Flip)');
      expect(first.versionTags.toList()..sort(), ['flip', 'vip']);

      final second = cleanSourceMetadata('Doja Cat - Say So', 'Doja Cat');
      expect(second.artist, 'Doja Cat');
      expect(second.title, 'Say So');
      expect(second.searchQuery, 'Doja Cat Say So');

      final third = cleanSourceMetadata(
        'Lil Peep - Star Shopping (Prod. Kryptik) [FREE DL] (Link in bio) *OG*',
        'Lil Peep',
      );
      expect(third.title, 'Star Shopping');
      expect(third.searchQuery, 'Lil Peep Star Shopping');
    });
  });
}
