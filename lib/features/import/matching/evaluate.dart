/// The matching of an imported track with a candidate of the catalog.
///
/// Port of `src/shared/media/matching/{titleScore,artistScore,rankCandidate,
/// evaluate,duration}.ts`.
library;

import 'artist_title.dart';
import 'artists.dart';
import 'junk.dart';
import 'phonetic.dart';
import 'similarity.dart';
import 'source_profile.dart';
import 'version_tags.dart';

import '../../../models/track.dart';

/// A candidate that is too far from the source to be accepted.
const int disqualifyDeltaMs = 15000;

/// The difference between the durations, in milliseconds.
int? durationDelta(int? left, int? right) {
  if (left == null || right == null || left == 0 || right == 0) return null;
  return (left - right).abs();
}

/// The score of the duration.
int durationScore(int? delta) {
  if (delta == null) return 10;
  if (delta <= 3000) return 30;
  if (delta <= 5000) return 22;
  if (delta <= 8000) return 12;
  if (delta <= 12000) return 2;
  if (delta <= disqualifyDeltaMs) return -20;
  return -100;
}

int _bestRatio(String left, String right) {
  final sort = tokenSortRatio(left, right);
  final set = tokenSetRatio(left, right);
  return sort > set ? sort : set;
}

bool _isNearSubstring(String left, String right) {
  final minLength = left.length < right.length ? left.length : right.length;
  final maxLength = left.length > right.length ? left.length : right.length;
  return minLength >= 4 &&
      minLength / maxLength >= 0.7 &&
      (left.contains(right) || right.contains(left));
}

/// The ratio between the titles of the source and of the candidate.
int computeTitleRatio(
  SourceProfile profile,
  String candidateBaseTitle,
  String candidateFullClean,
) {
  var titleRatio = _bestRatio(profile.baseTitle, candidateBaseTitle);
  final b = _bestRatio(profile.fullClean, candidateFullClean);
  if (b > titleRatio) titleRatio = b;
  final c = _bestRatio(profile.baseTitle, candidateFullClean);
  if (c > titleRatio) titleRatio = c;
  final d = _bestRatio(profile.fullClean, candidateBaseTitle);
  if (d > titleRatio) titleRatio = d;

  if (_isNearSubstring(profile.baseTitle, candidateBaseTitle) ||
      _isNearSubstring(profile.fullClean, candidateFullClean)) {
    if (titleRatio < 92) titleRatio = 92;
  }

  final phoneticRatio = _bestRatio(
    toPhoneticLatin(profile.baseTitle),
    toPhoneticLatin(candidateBaseTitle),
  );
  return phoneticRatio > titleRatio ? phoneticRatio : titleRatio;
}

/// The result of an inverted match ("title - artist" swapped).
class InvertedMatch {
  const InvertedMatch({required this.titleRatio, required this.artistRatio});

  final int titleRatio;
  final int artistRatio;
}

/// Detects the sources whose artist and title are swapped.
InvertedMatch? computeInvertedMatch(
  SourceProfile profile,
  String candidateBaseTitle,
  List<String> candidateArtists,
) {
  if (!profile.hasTwoParts) return null;

  final titleRatio = _bestRatio(profile.part0Clean, candidateBaseTitle);
  var artistRatio = 0;
  for (final artist in candidateArtists) {
    final ratio = _bestRatio(profile.part1Clean, cleanBaseTitle(artist));
    if (ratio > artistRatio) artistRatio = ratio;
  }
  if (titleRatio >= 85 && artistRatio >= 85) {
    return InvertedMatch(titleRatio: titleRatio, artistRatio: artistRatio);
  }
  return null;
}

/// The score of the artists.
class ArtistScore {
  const ArtistScore({required this.artistExact, required this.bestArtistRatio});

  final bool artistExact;
  final int bestArtistRatio;
}

bool _hasDirectMatch(
  SourceProfile profile,
  List<String> candidateArtists,
  String primaryCandidateArtist,
) {
  if (artistsMatch(profile.primaryArtist, primaryCandidateArtist)) return true;
  if (profile.meta.artist.isNotEmpty &&
      candidateArtists.any((artist) => artistsMatch(profile.meta.artist, artist))) {
    return true;
  }
  return profile.artists.any(
    (sourceArtist) =>
        candidateArtists.any((artist) => artistsMatch(sourceArtist, artist)),
  );
}

bool _hasInTitleArtist(
  SourceProfile profile,
  List<String> candidateArtists,
) {
  final phoneticTitle = toPhoneticLatin(profile.title);
  return candidateArtists.any((artist) {
    final normalized = normalizeTrackString(artist);
    return normalized.length >= 3 &&
        (profile.fullClean.contains(normalized) ||
            phoneticTitle.contains(toPhoneticLatin(artist)));
  });
}

/// The score of the artists of a candidate.
ArtistScore computeArtistScore(
  SourceProfile profile,
  List<String> candidateArtists,
  String primaryCandidateArtist,
) {
  if (_hasDirectMatch(profile, candidateArtists, primaryCandidateArtist) ||
      _hasInTitleArtist(profile, candidateArtists)) {
    return const ArtistScore(artistExact: true, bestArtistRatio: 100);
  }

  var bestArtistRatio = 0;
  for (final sourceArtist in profile.artists) {
    for (final candidateArtist in candidateArtists) {
      final ratio = _bestRatio(sourceArtist, candidateArtist);
      if (ratio > bestArtistRatio) bestArtistRatio = ratio;
      final phonetic = tokenSortRatio(
        toPhoneticLatin(sourceArtist),
        toPhoneticLatin(candidateArtist),
      );
      if (phonetic > bestArtistRatio) bestArtistRatio = phonetic;
    }
  }
  return ArtistScore(
    artistExact: bestArtistRatio >= 85,
    bestArtistRatio: bestArtistRatio,
  );
}

/// A candidate, scored against the source.
class RankedCandidate {
  const RankedCandidate({
    required this.track,
    required this.score,
    required this.delta,
    required this.isDisqualified,
    required this.titleExact,
    required this.bestTitleRatio,
    required this.artistExact,
    required this.bestArtistRatio,
    required this.titleClean,
    required this.primaryArtist,
    required this.versionMatches,
  });

  final Track track;
  final int score;
  final int? delta;
  final bool isDisqualified;
  final bool titleExact;
  final int bestTitleRatio;
  final bool artistExact;
  final int bestArtistRatio;
  final String titleClean;
  final String primaryArtist;
  final bool versionMatches;
}

/// Scores a candidate against the source.
RankedCandidate rankCandidate(SourceProfile profile, Track candidate) {
  final parsed = parseArtistAndTitle(candidate.title);
  final candidateBaseTitle = cleanBaseTitle(
    parsed.title.isNotEmpty ? parsed.title : candidate.title,
  );
  final candidateFullClean = cleanBaseTitle(candidate.title);
  final versionResult = compareVersionTags(
    profile.versionTags,
    getVersionTags(candidate.title),
  );

  final candidateArtists =
      (candidate.artistList ?? const []).map((a) => a.name).toList();
  if (candidate.artists.isNotEmpty && candidateArtists.isEmpty) {
    candidateArtists.addAll(
      candidate.artists.split(',').map((a) => a.trim()).where((a) => a.isNotEmpty),
    );
  }
  final parsedArtist = parsed.artist;
  if (parsedArtist != null &&
      parsedArtist.isNotEmpty &&
      !candidateArtists.any((artist) => artistsMatch(artist, parsedArtist))) {
    candidateArtists.add(parsedArtist);
  }
  final primaryArtist = candidateArtists.isNotEmpty ? candidateArtists.first : '';

  var bestTitleRatio =
      computeTitleRatio(profile, candidateBaseTitle, candidateFullClean);
  var artistScore = computeArtistScore(
    profile,
    candidateArtists,
    primaryArtist,
  );
  var artistExact = artistScore.artistExact;
  var bestArtistRatio = artistScore.bestArtistRatio;

  final inverted =
      computeInvertedMatch(profile, candidateBaseTitle, candidateArtists);
  if (inverted != null) {
    if (inverted.titleRatio > bestTitleRatio) bestTitleRatio = inverted.titleRatio;
    if (inverted.artistRatio > bestArtistRatio) bestArtistRatio = inverted.artistRatio;
    artistExact = true;
  }

  final delta = durationDelta(profile.durationMs, candidate.durationMs);
  final rawScore = (45 * (bestTitleRatio / 100)).round() +
      (30 * (bestArtistRatio / 100)).round() +
      durationScore(delta) +
      versionResult.bonus -
      versionResult.penalty;

  return RankedCandidate(
    track: candidate,
    score: rawScore.clamp(0, 100),
    delta: delta,
    isDisqualified: delta != null && delta > disqualifyDeltaMs,
    titleExact: bestTitleRatio >= 90,
    bestTitleRatio: bestTitleRatio,
    artistExact: artistExact,
    bestArtistRatio: bestArtistRatio,
    titleClean: candidateBaseTitle,
    primaryArtist: primaryArtist,
    versionMatches: versionResult.matches,
  );
}

/// Why a match was refused.
enum MatchRejectionReason {
  lowConfidenceMatch,
  ambiguousMatch,
  durationMismatch,
}

/// The outcome of the matching.
class MatchDecision {
  const MatchDecision.accepted({required this.track, required this.score})
      : reason = null,
        proposedTrack = null;

  const MatchDecision.rejected({
    required this.reason,
    this.score,
    this.proposedTrack,
  }) : track = null;

  final Track? track;
  final int? score;
  final MatchRejectionReason? reason;
  final Track? proposedTrack;

  bool get isAccepted => track != null;
}

bool _isAmbiguous(RankedCandidate best, RankedCandidate? second) {
  if (second == null || second.isDisqualified || best.score - second.score >= 10) {
    return false;
  }
  final delta = durationDelta(best.track.durationMs, second.track.durationMs);
  final isDuplicate = best.titleClean == second.titleClean &&
      artistsMatch(best.primaryArtist, second.primaryArtist) &&
      (delta ?? double.maxFinite) <= 3000;
  final isClearWinner = best.score >= 75 &&
      best.versionMatches &&
      best.artistExact &&
      best.delta != null &&
      best.delta! <= 4000;
  return !isDuplicate &&
      !isClearWinner &&
      (!best.titleExact || !best.versionMatches);
}

int? _acceptedScore(RankedCandidate best) {
  bool withinDelta(int limit) => best.delta == null || best.delta! <= limit;

  if (best.bestTitleRatio >= 85 &&
      best.artistExact &&
      best.versionMatches &&
      withinDelta(10000)) {
    return best.score > 95 ? best.score : 95;
  }
  if (best.bestTitleRatio >= 88 &&
      best.titleClean.length >= 4 &&
      best.delta != null &&
      best.delta! <= 3000 &&
      best.versionMatches) {
    return best.score > 88 ? best.score : 88;
  }
  if (best.artistExact &&
      withinDelta(4000) &&
      best.bestTitleRatio >= 70 &&
      best.versionMatches) {
    return best.score > 85 ? best.score : 85;
  }
  if (best.score >= 75 &&
      best.bestTitleRatio >= 75 &&
      (best.artistExact || best.bestArtistRatio >= 70) &&
      best.versionMatches &&
      withinDelta(8000)) {
    return best.score;
  }
  return null;
}

/// Matches an imported track with the candidates of the catalog.
MatchDecision evaluateImportedTrack(
  ImportedTrack source,
  List<Track> candidates,
) {
  final profile = buildSourceProfile(source);
  final ranked = candidates
      .map((candidate) => rankCandidate(profile, candidate))
      .toList()
    ..sort((a, b) => b.score.compareTo(a.score));

  if (ranked.isEmpty) {
    return const MatchDecision.rejected(
      reason: MatchRejectionReason.lowConfidenceMatch,
    );
  }

  final best = ranked.first;
  if (best.isDisqualified) {
    return MatchDecision.rejected(
      reason: MatchRejectionReason.durationMismatch,
      score: best.score,
      proposedTrack: best.track,
    );
  }
  if (_isAmbiguous(best, ranked.length > 1 ? ranked[1] : null)) {
    return MatchDecision.rejected(
      reason: MatchRejectionReason.ambiguousMatch,
      score: best.score,
      proposedTrack: best.track,
    );
  }

  final score = _acceptedScore(best);
  if (score == null) {
    return MatchDecision.rejected(
      reason: MatchRejectionReason.lowConfidenceMatch,
      score: best.score,
      proposedTrack: best.track,
    );
  }
  return MatchDecision.accepted(track: best.track, score: score);
}
