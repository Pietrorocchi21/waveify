/// Phonetic and textual normalization of the track titles.
///
/// Port of `src/shared/media/matching/phonetic.ts`.
library;

const Map<String, String> _cyrillicToLatin = {
  'а': 'a',
  'б': 'b',
  'в': 'v',
  'г': 'g',
  'д': 'd',
  'е': 'e',
  'ё': 'e',
  'ж': 'zh',
  'з': 'z',
  'и': 'i',
  'й': 'y',
  'к': 'k',
  'л': 'l',
  'м': 'm',
  'н': 'n',
  'о': 'o',
  'п': 'p',
  'р': 'r',
  'с': 's',
  'т': 't',
  'у': 'u',
  'ф': 'f',
  'х': 'h',
  'ц': 'ts',
  'ч': 'ch',
  'ш': 'sh',
  'щ': 'shch',
  'ъ': '',
  'ы': 'y',
  'ь': '',
  'э': 'e',
  'ю': 'yu',
  'я': 'ya',
  'є': 'ye',
  'і': 'i',
  'ї': 'yi',
  'ґ': 'g',
};

/// A rough phonetic transcription, used to compare the titles that are
/// written in different languages.
String toPhoneticLatin(String value) {
  var result = value.toLowerCase().replaceAll('ё', 'e');
  _cyrillicToLatin.forEach((cyrillic, latin) {
    result = result.replaceAll(cyrillic, latin);
  });
  return result
      .replaceAll('kh', 'h')
      .replaceAll(RegExp('[yj]'), 'i')
      .replaceAll('w', 'v')
      .replaceAll('ph', 'f')
      .replaceAll('oo', 'u')
      .replaceAll('ee', 'i')
      .replaceAll('z', 's')
      .replaceAll(RegExp(r'e\b'), '')
      .replaceAll(RegExp('[^a-z0-9\\s]'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

/// Lowercases the string and keeps only the letters and the digits.
String normalizeWords(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

/// The normalized form used to compare the titles.
String normalizeTrackString(String value) {
  return normalizeWords(
    value
        .replaceAll('ё', 'е')
        .replaceAll(RegExp(r'\.(?:mp3|wav|flac|m4a|aac|ogg)\b', caseSensitive: false), ''),
  );
}
