/// The comparison of the artists.
///
/// Port of `src/shared/media/matching/artists.ts`.
library;

import 'phonetic.dart';

/// The known aliases: the same artist written in different languages.
const List<Set<String>> knownArtistAliases = [
  {'в цой', 'виктор цой', 'цой', 'кино'},
  {'горшок', 'михаил горшенев', 'князь', 'андрей князев', 'киш', 'король и шут'},
  {'лсп', 'lsp'},
  {'пошлая молли', 'poshlaya molly'},
  {'xxxmanera', 'хххманера'},
  {'og buda', 'ог буда'},
  {'scally milano', 'скалли милано'},
  {'uglystephan', 'аглистефан'},
  {'три дня дождя', 'three days of rain'},
  {'miyagi', 'мияги', 'эндшпиль', 'endspiel', 'andy panda', 'энди панда', 'hajime'},
  {'скриптонит', 'scriptonite', 'gruppa skryptonite'},
  {'pharaoh', 'фараон'},
  {'boulevard depo', 'бульвар депо'},
  {'saluki', 'салуки'},
  {'markul', 'маркул'},
  {'oxxxymiron', 'оксимирон'},
  {'noize mc', 'нойз мс'},
  {'валентин стрыкало', 'юрий каплан', 'стрыкало'},
  {'serebro', 'серебро'},
  {'tatu', 't a t u', 'тату'},
  {'macan', 'макан'},
  {'kizaru', 'кизару'},
  {'big baby tape', 'биг бейби тейп', 'bbtape'},
  {'егор крид', 'egor kreed'},
  {'morgenshtern', 'моргенштерн'},
  {'mc doni', 'doni', 'дони'},
  {'не будите спящих', 'ne budite spyashchikh'},
  {'дискотека авария', 'diskoteka avariya'},
];

bool _containsEither(String left, String right, int minLength) {
  return left.length >= minLength &&
      right.length >= minLength &&
      (left.contains(right) || right.contains(left));
}

/// True when the two artists are the same one.
bool artistsMatch(String sourceArtist, String candidateArtist) {
  if (sourceArtist.isEmpty || candidateArtist.isEmpty) return false;

  final sourceClean = normalizeTrackString(sourceArtist);
  final candidateClean = normalizeTrackString(candidateArtist);
  if (sourceClean.isNotEmpty && sourceClean == candidateClean) return true;

  final sourceCompact = sourceClean.replaceAll(RegExp(r'\s+'), '');
  final candidateCompact = candidateClean.replaceAll(RegExp(r'\s+'), '');
  if (sourceCompact.isNotEmpty && sourceCompact == candidateCompact) return true;

  for (final aliases in knownArtistAliases) {
    if (aliases.contains(sourceClean) && aliases.contains(candidateClean)) {
      return true;
    }
  }
  if (_containsEither(sourceCompact, candidateCompact, 3)) return true;

  final sourcePhonetic = toPhoneticLatin(sourceArtist);
  final candidatePhonetic = toPhoneticLatin(candidateArtist);
  if (sourcePhonetic.isNotEmpty && sourcePhonetic == candidatePhonetic) return true;
  return _containsEither(sourcePhonetic, candidatePhonetic, 4);
}
