/// The similarity between the strings.
///
/// Port of `src/shared/media/matching/similarity.ts`.
library;

import 'phonetic.dart';

/// The Levenshtein distance between two strings.
int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var v0 = List<int>.generate(b.length + 1, (i) => i);
  var v1 = List<int>.filled(b.length + 1, 0);

  for (var i = 0; i < a.length; i++) {
    v1[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      final deletion = v1[j] + 1;
      final insertion = v0[j + 1] + 1;
      final substitution = v0[j] + cost;
      v1[j + 1] = deletion < insertion
          ? (deletion < substitution ? deletion : substitution)
          : (insertion < substitution ? insertion : substitution);
    }
    for (var j = 0; j <= b.length; j++) {
      v0[j] = v1[j];
    }
  }

  return v0[b.length];
}

/// The ratio of the sorted tokens, between 0 and 100.
int tokenSortRatio(String a, String b) {
  final normA = normalizeTrackString(a);
  final normB = normalizeTrackString(b);
  if (normA.isEmpty || normB.isEmpty) return 0;
  if (normA == normB) return 100;

  final sortedA = (normA.split(' ').where((t) => t.isNotEmpty).toList()..sort()).join(' ');
  final sortedB = (normB.split(' ').where((t) => t.isNotEmpty).toList()..sort()).join(' ');
  if (sortedA == sortedB) return 100;

  final distance = levenshtein(sortedA, sortedB);
  final maxLength = sortedA.length > sortedB.length ? sortedA.length : sortedB.length;
  if (maxLength == 0) return 0;
  final ratio = ((1 - distance / maxLength) * 100).round();
  return ratio < 0 ? 0 : ratio;
}

/// The ratio of the common tokens, between 0 and 100.
int tokenSetRatio(String a, String b) {
  final normA = normalizeTrackString(a);
  final normB = normalizeTrackString(b);
  if (normA.isEmpty || normB.isEmpty) return 0;
  if (normA == normB) return 100;

  final setA = normA.split(' ').where((t) => t.isNotEmpty).toSet();
  final setB = normB.split(' ').where((t) => t.isNotEmpty).toSet();
  final intersection = setA.where(setB.contains).toList();
  if (intersection.isEmpty) return 0;

  final minTokens = setA.length < setB.length ? setA.length : setB.length;
  final maxTokens = setA.length > setB.length ? setA.length : setB.length;
  if (setA.length == setB.length && intersection.length == setA.length) {
    return 100;
  }

  final coverage = (2 * intersection.length) / (setA.length + setB.length);
  var ratio = (coverage * 100).round();

  if (intersection.length == minTokens) {
    if (minTokens >= 2) {
      final boost = ((minTokens / maxTokens) * 35 + 55).round();
      if (boost > ratio) ratio = boost;
    } else if (minTokens == 1 &&
        intersection.first.length >= 5 &&
        minTokens / maxTokens >= 0.5) {
      if (ratio < 72) ratio = 72;
    }
  }

  return ratio;
}
