import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:waveify/core/providers/app_providers.dart';
import 'package:waveify/shared/widgets/common.dart';
import '../library/library_controller.dart' as lib;
import 'import_controller.dart';
import 'sources/import_source.dart';

/// The import of a playlist from an external source.
///
/// The tracks are matched against the catalog and reviewed before they are
/// added to one of the user's playlists.
class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key});

  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  final _urlController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translatorProvider);
    final state = ref.watch(importControllerProvider);
    final controller = ref.read(importControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(t('import.title'))),
      body: switch (state.phase) {
        ImportPhase.idle || ImportPhase.failed => _buildForm(context, t, state),
        ImportPhase.loading => _buildProgress(context, t, state),
        ImportPhase.reviewing => _buildReview(context, t, state, controller),
        ImportPhase.importing => const LoadingState(),
        ImportPhase.done => _buildDone(context, t, state),
      },
    );
  }

  Widget _buildForm(BuildContext context, dynamic t, ImportState state) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Text(
          t('import.description'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.textTertiary,
          ),
        ),
        const SizedBox(height: 20),
        _buildSourceHint(context, t),
        const SizedBox(height: 12),
        TextField(
          controller: _urlController,
          keyboardType: TextInputType.url,
          autocorrect: false,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: t('import.link_label'),
            hintText: t('import.link_hint'),
            prefixIcon: const Icon(Icons.link_rounded),
          ),
          onSubmitted: (_) => _start(),
        ),
        if (state.error != null) ...[
          const SizedBox(height: 12),
          Text(
            state.error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.download_rounded, size: 18),
          label: Text(t('import.start')),
        ),
        const SizedBox(height: 24),
        AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('import.sources_title'),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                t('import.sources_desc'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The progress of the matching: the reviews appear as they are resolved.
  /// The hint of the detected source.
  Widget _buildSourceHint(BuildContext context, dynamic t) {
    final theme = Theme.of(context);
    final text = _urlController.text.trim();
    if (text.isEmpty) return const SizedBox.shrink();

    final source = detectImportSource(text);
    if (!source.isSupported) {
      return Row(
        children: [
          Icon(
            Icons.link_off_rounded,
            size: 16,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t('import.unsupported_source'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Icon(
          Icons.check_circle_rounded,
          size: 16,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            t('import.detected_source', {'source': source.label}),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.textTertiary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProgress(BuildContext context, dynamic t, ImportState state) {
    final theme = Theme.of(context);
    final total = state.playlist?.tracks.length ?? 0;

    if (state.reviews.isEmpty) {
      return Column(
        children: [
          const LoadingState(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              t('import.matching'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTertiary,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${state.reviews.length} / $total',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: state.reviews.length,
            itemBuilder: (context, index) => _ReviewTile(review: state.reviews[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildReview(
    BuildContext context,
    dynamic t,
    ImportState state,
    ImportController controller,
  ) {
    final theme = Theme.of(context);
    final library = ref.watch(lib.libraryControllerProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Text(
          state.playlist?.title.isNotEmpty == true
              ? state.playlist!.title
              : t('import.title'),
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${state.reviews.length} ${t('player.tracks')} · '
          '${state.approvedCount} ${t('import.approved')}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.textTertiary,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: controller.approveAll,
              icon: const Icon(Icons.done_all_rounded, size: 18),
              label: Text(t('import.approve_all')),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final review in state.reviews)
          _ReviewTile(review: review),
        const SizedBox(height: 20),
        if (library.playlists.isEmpty)
          EmptyState(
            icon: Icons.queue_music_rounded,
            title: t('library.no_playlists_title'),
            description: t('library.no_playlists_desc'),
          )
        else
          for (final playlist in library.playlists)
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: Text(playlist.title),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                final added = await controller.finalize(playlist.id);
                if (added && context.mounted) {
                  showAppSnackBar(
                    context,
                    '${t('import.added')} ${state.approvedCount}',
                  );
                }
              },
            ),
      ],
    );
  }

  Widget _buildDone(BuildContext context, dynamic t, ImportState state) {
    return EmptyState(
      icon: Icons.check_circle_outline_rounded,
      title: t('import.done_title'),
      description: '${t('import.added')} ${state.addedCount}',
      action: FilledButton(
        onPressed: () {
          ref.read(importControllerProvider.notifier).reset();
        },
        child: Text(t('import.done_action')),
      ),
    );
  }

  void _start() {
    ref
        .read(importControllerProvider.notifier)
        .start(_urlController.text);
  }
}

/// The review of one imported track.
class _ReviewTile extends ConsumerWidget {
  const _ReviewTile({required this.review});

  final ImportReview review;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);
    final controller = ref.read(importControllerProvider.notifier);

    final matched = review.proposedTrack;
    final subtitle = matched != null
        ? matched.artists
        : switch (review.reason) {
            ImportReviewReason.noCatalogCandidates =>
              t('import.reason.no_catalog_candidates'),
            ImportReviewReason.lowConfidenceMatch =>
              t('import.reason.low_confidence_match'),
            ImportReviewReason.ambiguousMatch =>
              t('import.reason.ambiguous_match'),
            ImportReviewReason.durationMismatch =>
              t('import.reason.duration_mismatch'),
            ImportReviewReason.catalogLookupFailed =>
              t('import.reason.catalog_lookup_failed'),
            null => '',
          };

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CoverImage(
        url: matched?.coverUrl ?? review.source.coverUrl,
        size: 44,
        borderRadius: 6,
      ),
      title: Text(
        review.source.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: matched == null ? theme.colorScheme.error : theme.textTertiary,
        ),
      ),
      trailing: matched == null
          ? const Icon(Icons.block_rounded, size: 18)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (review.score != null)
                  Text(
                    '${review.score}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTertiary,
                    ),
                  ),
                IconButton(
                  tooltip: t('common.confirm'),
                  icon: Icon(
                    review.isApproved
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 20,
                    color: review.isApproved ? theme.colorScheme.primary : null,
                  ),
                  onPressed: () => controller.decide(
                    review.reviewId,
                    review.isApproved
                        ? ImportDecision.denied
                        : ImportDecision.approved,
                  ),
                ),
              ],
            ),
    );
  }
}
