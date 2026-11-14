/// The version tags of a title (remix, slowed, live, …).
///
/// Port of `src/shared/media/matching/versionTags.ts`.
library;

class VersionPattern {
  const VersionPattern(this.tag, this.regex);

  final String tag;
  final RegExp regex;
}

final List<VersionPattern> versionPatterns = [
  VersionPattern('remix', RegExp(r'\b(remix(?:ed)?|ремикс|rmx)\b', caseSensitive: false)),
  VersionPattern('vip', RegExp(r'\b(vip|v\.i\.p\.?)\b', caseSensitive: false)),
  VersionPattern('flip', RegExp(r'\b(flip|флип)\b', caseSensitive: false)),
  VersionPattern('bootleg', RegExp(r'\b(bootleg|бутлег)\b', caseSensitive: false)),
  VersionPattern('mashup', RegExp(r'\b(mash\s*up|мэшап|мешап)\b', caseSensitive: false)),
  VersionPattern('edit', RegExp(r'\b((?:radio|club|extended)?\s*edit|эдит)\b', caseSensitive: false)),
  VersionPattern(
    'slowed',
    RegExp(r'\b(slowed(?:\s*(?:\+|&|and)\s*reverb)?|слоу)\b', caseSensitive: false),
  ),
  VersionPattern('reverb', RegExp(r'\b(reverb|реверб)\b', caseSensitive: false)),
  VersionPattern(
    'sped_up',
    RegExp(r'\b(sp(?:ed|eed)\s*up|sp(?:ed|eed)up|спид\s*ап|спидап)\b', caseSensitive: false),
  ),
  VersionPattern('nightcore', RegExp(r'\b(nightcore|найткор)\b', caseSensitive: false)),
  VersionPattern(
    'instrumental',
    RegExp(r'\b(instrumental|инструментал|inst\b\.?)\b', caseSensitive: false),
  ),
  VersionPattern('acoustic', RegExp(r'\b(acoustic|акустика)\b', caseSensitive: false)),
  VersionPattern('live', RegExp(r'\b(live(?:\s+at[^)]+)?|лайв|концерт)\b', caseSensitive: false)),
  VersionPattern('cover', RegExp(r'\b(cover|кавер)\b', caseSensitive: false)),
  VersionPattern(
    'bass_boosted',
    RegExp(r'\b(bass\s*boost(?:ed)?|басс\s*буст)\b', caseSensitive: false),
  ),
];

/// The version tags found in a title.
Set<String> getVersionTags(String value) {
  final tags = <String>{};
  for (final pattern in versionPatterns) {
    if (pattern.regex.hasMatch(value)) tags.add(pattern.tag);
  }
  return tags;
}

/// The first version tag of a title.
String? getVersionTag(String value) {
  final tags = getVersionTags(value);
  return tags.isEmpty ? null : tags.first;
}

/// The comparison of the version tags of the source and of the candidate.
class VersionComparison {
  const VersionComparison({
    required this.matches,
    required this.penalty,
    required this.bonus,
  });

  final bool matches;
  final int penalty;
  final int bonus;
}

/// Compares the version tags: a source "slowed" must not be matched with a
/// plain track.
VersionComparison compareVersionTags(
  Set<String> sourceTags,
  Set<String> candidateTags,
) {
  if (sourceTags.isEmpty && candidateTags.isEmpty) {
    return const VersionComparison(matches: true, penalty: 0, bonus: 5);
  }
  if (sourceTags.isNotEmpty && candidateTags.isNotEmpty) {
    final hasCommon = sourceTags.any(candidateTags.contains);
    return hasCommon
        ? const VersionComparison(matches: true, penalty: 0, bonus: 15)
        : const VersionComparison(matches: false, penalty: 50, bonus: 0);
  }
  return const VersionComparison(matches: false, penalty: 50, bonus: 0);
}
