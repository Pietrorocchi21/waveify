import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/catalog_service.dart';
import '../../core/providers/app_providers.dart';
import '../../models/track.dart';
import '../library/library_controller.dart';
import 'matching/evaluate.dart';
import 'matching/source_profile.dart';
import 'sources/apple_music_source.dart';
import 'sources/deezer_source.dart';
import 'sources/import_source.dart';
import 'sources/imported_playlist.dart';
import 'sources/spotify_source.dart';
import 'sources/youtube_source.dart';

/// The decision taken on an imported track.
enum ImportDecision { pending, approved, denied }

/// Why a track was not matched.
enum ImportReviewReason {
  noCatalogCandidates,
  lowConfidenceMatch,
  ambiguousMatch,
  durationMismatch,
  catalogLookupFailed,
}

/// The review of one imported track.
class ImportReview {
  const ImportReview({
    required this.reviewId,
    required this.source,
    this.proposedTrack,
    this.score,
    this.reason,
    this.decision = ImportDecision.pending,
  });

  final String reviewId;
  final ImportedTrack source;
  final Track? proposedTrack;
  final int? score;
  final ImportReviewReason? reason;
  final ImportDecision decision;

  bool get isApproved => decision == ImportDecision.approved;

  ImportReview copyWith({ImportDecision? decision}) {
    return ImportReview(
      reviewId: reviewId,
      source: source,
      proposedTrack: proposedTrack,
      score: score,
      reason: reason,
      decision: decision ?? this.decision,
    );
  }
}

/// The phase of the import.
enum ImportPhase { idle, loading, reviewing, importing, done, failed }

/// The state of the import.
class ImportState {
  const ImportState({
    this.phase = ImportPhase.idle,
    this.playlist,
    this.reviews = const [],
    this.error,
    this.addedCount = 0,
  });

  final ImportPhase phase;
  final ImportedPlaylist? playlist;
  final List<ImportReview> reviews;
  final String? error;
  final int addedCount;

  int get approvedCount =>
      reviews.where((r) => r.isApproved).length;

  int get pendingCount => reviews
      .where((r) => r.decision == ImportDecision.pending)
      .length;

  ImportState copyWith({
    ImportPhase? phase,
    ImportedPlaylist? playlist,
    List<ImportReview>? reviews,
    String? error,
    bool clearError = false,
    int? addedCount,
  }) {
    return ImportState(
      phase: phase ?? this.phase,
      playlist: playlist ?? this.playlist,
      reviews: reviews ?? this.reviews,
      error: clearError ? null : (error ?? this.error),
      addedCount: addedCount ?? this.addedCount,
    );
  }
}

/// Runs an import: it reads the source, matches the tracks and adds the
/// approved ones to a playlist.
class ImportController extends Notifier<ImportState> {
  @override
  ImportState build() => const ImportState();

  /// Reads the source and matches its tracks.
  Future<void> start(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      state = state.copyWith(
        phase: ImportPhase.failed,
        error: 'Paste the link of a playlist.',
      );
      return;
    }

    state = state.copyWith(phase: ImportPhase.loading, clearError: true);

    try {
      final playlist = await _importFrom(trimmed);
      final reviews = await _match(playlist);
      state = state.copyWith(
        phase: ImportPhase.reviewing,
        playlist: playlist,
        reviews: reviews,
      );
    } catch (error) {
      state = state.copyWith(phase: ImportPhase.failed, error: '$error');
    }
  }

  /// How many tracks are looked up in the catalog at the same time.
  static const int _lookupConcurrency = 4;

  /// Reads the playlist from the source the link points at.
  Future<ImportedPlaylist> _importFrom(String url) async {
    final source = detectImportSource(url);
    switch (source.kind) {
      case ImportSourceKind.spotify:
        return SpotifySource().import(url);
      case ImportSourceKind.deezer:
        return DeezerSource().import(url);
      case ImportSourceKind.youtube:
        return YoutubeSource().import(url);
      case ImportSourceKind.appleMusic:
        return AppleMusicSource().import(url);
      case ImportSourceKind.unknown:
        throw StateError(
          'The link must point to a YouTube, Spotify or Deezer playlist.',
        );
    }
  }

  /// Matches every imported track with the catalog.
  ///
  /// The lookups run in parallel, but only a few at a time: a playlist has
  /// often hundreds of tracks and the catalog does not like the hammering.
  Future<List<ImportReview>> _match(ImportedPlaylist playlist) async {
    final catalog = ref.read(catalogProvider);
    final reviews = <ImportReview>[];

    var next = 0;
    Future<void> worker() async {
      while (next < playlist.tracks.length) {
        final index = next++;
        final review = await _matchOne(catalog, playlist.tracks[index], index);
        reviews.add(review);
        state = state.copyWith(
          reviews: [...reviews],
          phase: ImportPhase.loading,
        );
      }
    }

    await Future.wait([
      for (var i = 0; i < _lookupConcurrency; i++) worker(),
    ]);

    reviews.sort((a, b) => a.reviewId.compareTo(b.reviewId));
    return reviews;
  }

  /// Matches one imported track with the catalog.
  Future<ImportReview> _matchOne(
    CatalogService catalog,
    ImportedTrack source,
    int index,
  ) async {
    final reviewId = 'r$index';

    try {
      final results = await catalog.search(
        '${source.title} ${source.artists.join(' ')}'.trim(),
        type: 'track',
      );
      final candidates = results
          .map((item) => item.track)
          .whereType<Track>()
          .toList(growable: false);

      if (candidates.isEmpty) {
        return ImportReview(
          reviewId: reviewId,
          source: source,
          reason: ImportReviewReason.noCatalogCandidates,
        );
      }

      final decision = evaluateImportedTrack(source, candidates);
      if (decision.isAccepted) {
        return ImportReview(
          reviewId: reviewId,
          source: source,
          proposedTrack: decision.track,
          score: decision.score,
          decision: ImportDecision.approved,
        );
      }
      return ImportReview(
        reviewId: reviewId,
        source: source,
        proposedTrack: decision.proposedTrack,
        score: decision.score,
        reason: _reasonOf(decision.reason),
      );
    } catch (_) {
      return ImportReview(
        reviewId: reviewId,
        source: source,
        reason: ImportReviewReason.catalogLookupFailed,
      );
    }
  }

  static ImportReviewReason? _reasonOf(MatchRejectionReason? reason) {
    switch (reason) {
      case MatchRejectionReason.lowConfidenceMatch:
        return ImportReviewReason.lowConfidenceMatch;
      case MatchRejectionReason.ambiguousMatch:
        return ImportReviewReason.ambiguousMatch;
      case MatchRejectionReason.durationMismatch:
        return ImportReviewReason.durationMismatch;
      case null:
        return null;
    }
  }

  /// Approves or denies a track.
  void decide(String reviewId, ImportDecision decision) {
    state = state.copyWith(
      reviews: [
        for (final review in state.reviews)
          if (review.reviewId == reviewId)
            review.copyWith(decision: decision)
          else
            review,
      ],
    );
  }

  /// Approves every track that has a match.
  void approveAll() {
    state = state.copyWith(
      reviews: [
        for (final review in state.reviews)
          if (review.proposedTrack != null)
            review.copyWith(decision: ImportDecision.approved)
          else
            review,
      ],
    );
  }

  /// Adds the approved tracks to a playlist.
  Future<bool> finalize(String playlistId) async {
    final approved = state.reviews
        .where((r) => r.isApproved && r.proposedTrack != null)
        .map((r) => r.proposedTrack!)
        .toList(growable: false);

    if (approved.isEmpty) {
      state = state.copyWith(
        phase: ImportPhase.failed,
        error: 'No track was approved.',
      );
      return false;
    }

    state = state.copyWith(phase: ImportPhase.importing, clearError: true);

    try {
      final library = ref.read(libraryControllerProvider.notifier);
      final added = await library.addTracksToPlaylist(playlistId, approved);
      state = state.copyWith(
        phase: added > 0 ? ImportPhase.done : ImportPhase.failed,
        addedCount: added,
        error: added > 0 ? null : 'The tracks could not be added.',
      );
      return added > 0;
    } catch (error) {
      state = state.copyWith(phase: ImportPhase.failed, error: '$error');
      return false;
    }
  }

  /// Returns to the idle state.
  void reset() {
    state = const ImportState();
  }
}

/// The import controller provider.
final importControllerProvider =
    NotifierProvider<ImportController, ImportState>(ImportController.new);
