import 'package:go_router/go_router.dart';

import '../../../core/media/innertube/stream_resolver.dart';
import '../../../shared/widgets/waveify_brand.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../models/lyrics.dart';
import '../../../shared/widgets/common.dart';
import '../../lyrics/lyrics_controller.dart';
import '../player_controller.dart';
import '../../../shared/widgets/glass.dart';
import '../../../shared/widgets/artwork_stage.dart';
import '../../../core/theme/artwork_palette.dart';
import '../../library/library_controller.dart';
import 'mini_player.dart';

void showLyricsSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (context) => GlassSheet(
    maxHeight: MediaQuery.sizeOf(context).height * 0.8,
    padding: EdgeInsets.zero,
    child: const _LyricsPanel(),
  ),
);

/// Focused listening view. Existing detail tools open on demand instead of
/// taking half the canvas away from the artwork.
class FullscreenPlayerPage extends ConsumerWidget {
  const FullscreenPlayerPage({super.key});

  void _openPanel(BuildContext context, Widget child) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => GlassSheet(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        padding: EdgeInsets.zero,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translatorProvider);
    final playback = ref.watch(
      playerControllerProvider.select(
        (s) => (s.currentTrack, s.queue, s.currentIndex),
      ),
    );
    final track = playback.$1;
    final controller = ref.read(playerControllerProvider.notifier);
    final isPlaying = ref.watch(
      playerControllerProvider.select((s) => s.isPlaying),
    );
    if (track == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.music_note_outlined,
          title: t('player.nothing_playing'),
          description: t('player.choose_track'),
        ),
      );
    }
    final tracks = playback.$2.isEmpty ? [track] : playback.$2;
    final liked = ref.watch(
      libraryControllerProvider.select(
        (s) => s.likedTracks.any((item) => item.id == track.id),
      ),
    );
    return AmbientBackground(
      accentColor: ref.watch(ambientAccentProvider),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: MediaQuery.sizeOf(context).width < 420
              ? const WaveifyMark()
              : const WaveifyWordmark(),
          actions: [
            IconButton(
              tooltip: t('player.lyrics'),
              onPressed: () => _openPanel(context, const _LyricsPanel()),
              icon: const Icon(Icons.lyrics_outlined),
            ),
            IconButton(
              tooltip: t('player.speed_pitch'),
              onPressed: () => _openPanel(context, const _SpeedPitchPanel()),
              icon: const Icon(Icons.tune_rounded),
            ),
            IconButton(
              tooltip: t('player.queue'),
              onPressed: () => showQueueSheet(context, ref),
              icon: const Icon(Icons.queue_music_rounded),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: ArtworkStage(
                            key: ValueKey(
                              tracks.map((item) => item.id).join('|'),
                            ),
                            items: [
                              for (final item in tracks)
                                StageArtwork(
                                  id: item.id,
                                  title: item.title,
                                  subtitle: item.artists,
                                  coverUrl: item.coverUrl,
                                  actionLabel: t(
                                    item.id == track.id && isPlaying
                                        ? 'common.pause'
                                        : 'common.play',
                                  ),
                                  onActivate: () => item.id == track.id
                                      ? controller.togglePlayPause()
                                      : controller.playTrack(
                                          item,
                                          queue: tracks,
                                          index: tracks.indexOf(item),
                                          preserveQueue: true,
                                        ),
                                ),
                            ],
                            initialIndex: playback.$3 < 0 ? 0 : playback.$3,
                            actionLabel: t('common.play'),
                            large: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (StreamResolver.toVideoId(track.id) != null &&
                  ref.watch(
                    playerControllerProvider.select((s) => s.error != null),
                  ))
                TextButton.icon(
                  onPressed: () => context.go(
                    Uri(
                      path: '/search',
                      queryParameters: {
                        'q': '${track.title} ${track.artists}'.trim(),
                      },
                    ).toString(),
                  ),
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: Text(t('player.find_on_audius')),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (MediaQuery.sizeOf(context).width < 900)
                    const ShuffleButton(),
                  IconButton(
                    tooltip: t(liked ? 'common.unlike' : 'common.like'),
                    onPressed: () => ref
                        .read(libraryControllerProvider.notifier)
                        .toggleLike(track),
                    icon: Icon(
                      liked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                    ),
                  ),
                  if (MediaQuery.sizeOf(context).width < 900)
                    const RepeatButton(),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 940),
                    child: GlassPlayerBar(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: MiniPlayer(fullControls: true),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LyricsPanel extends StatelessWidget {
  const _LyricsPanel();

  @override
  Widget build(BuildContext context) {
    return const GlassPanel(
      blur: 0,
      padding: EdgeInsets.zero,
      child: _LyricsTab(),
    );
  }
}

class _SpeedPitchPanel extends StatelessWidget {
  const _SpeedPitchPanel();

  @override
  Widget build(BuildContext context) {
    return const GlassPanel(
      blur: 0,
      padding: EdgeInsets.zero,
      child: _SpeedPitchTab(),
    );
  }
}

class _LyricsTab extends ConsumerWidget {
  const _LyricsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);
    final lyrics = ref.watch(lyricsControllerProvider);
    final track = ref.watch(
      playerControllerProvider.select((s) => s.currentTrack),
    );

    if (track == null) {
      return const EmptyState(
        icon: Icons.lyrics_outlined,
        title: 'Nothing playing',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        Text(
          t('player.lyrics'),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        if (lyrics.providers.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in lyrics.providers)
                ChoiceChip(
                  label: Text(option.provider),
                  selected: lyrics.candidate?.provider == option.provider,
                  onSelected: (_) => ref
                      .read(lyricsControllerProvider.notifier)
                      .selectProvider(option),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (lyrics.isLoading && lyrics.parsed == null)
          const LoadingState()
        else if (lyrics.error != null)
          ErrorState(message: lyrics.error!)
        else if (lyrics.candidate?.isInstrumental == true)
          EmptyState(
            icon: Icons.music_note,
            title: t('player.lyrics_instrumental'),
          )
        else if (lyrics.parsed == null ||
            (lyrics.parsed!.syncedLines.isEmpty &&
                lyrics.parsed!.plainLyrics == null))
          EmptyState(
            icon: Icons.lyrics_outlined,
            title: t('player.no_lyrics'),
            description: t('player.no_lyrics_found'),
          )
        else
          _SyncedLyricsView(
            key: ValueKey(lyrics.trackId),
            lyrics: lyrics.parsed!,
          ),
        if (lyrics.parsed?.plainLyrics != null &&
            (lyrics.parsed?.syncedLines.isEmpty ?? true))
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('player.lyrics_unsynced'),
                  style: theme.textTheme.labelMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  lyrics.parsed!.plainLyrics!,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SyncedLyricsView extends ConsumerStatefulWidget {
  const _SyncedLyricsView({super.key, required this.lyrics});
  final ParsedLyrics lyrics;

  @override
  ConsumerState<_SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends ConsumerState<_SyncedLyricsView> {
  final _keys = <GlobalKey>[];
  ScrollPosition? _position;
  DateTime _resumeAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastActive = -2;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _position?.removeListener(_onScroll);
    _position = Scrollable.maybeOf(context)?.position;
    _position?.addListener(_onScroll);
  }

  void _onScroll() {
    if (_position?.userScrollDirection != ScrollDirection.idle) {
      _resumeAt = DateTime.now().add(const Duration(seconds: 4));
      _lastActive = -2;
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_onScroll);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = widget.lyrics;
    final positionMs = ref.watch(
      playerControllerProvider.select((s) => s.position.inMilliseconds),
    );
    final activeIndex = lyrics.activeLineIndex(positionMs);
    while (_keys.length < lyrics.syncedLines.length) {
      _keys.add(GlobalKey());
    }
    if (activeIndex != _lastActive &&
        activeIndex >= 0 &&
        DateTime.now().isAfter(_resumeAt)) {
      _lastActive = activeIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || DateTime.now().isBefore(_resumeAt)) return;
        final target = _keys[activeIndex].currentContext;
        if (target != null) {
          Scrollable.ensureVisible(
            target,
            alignment: 0.35,
            duration: const Duration(milliseconds: 300),
          );
        }
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lyrics.syncedLines.length; i++)
          AnimatedOpacity(
            key: _keys[i],
            duration: const Duration(milliseconds: 180),
            opacity: i == activeIndex ? 1 : 0.68,
            child: InkWell(
              onTap: () => ref
                  .read(playerControllerProvider.notifier)
                  .seek(Duration(milliseconds: lyrics.syncedLines[i].timeMs)),
              child: _LyricLineView(
                line: lyrics.syncedLines[i],
                isActive: i == activeIndex,
                positionMs: positionMs,
              ),
            ),
          ),
      ],
    );
  }
}

class _LyricLineView extends StatelessWidget {
  const _LyricLineView({
    required this.line,
    required this.isActive,
    required this.positionMs,
  });

  final SyncedLine line;
  final bool isActive;
  final int positionMs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final style = theme.textTheme.titleMedium?.copyWith(
      height: 1.35,
      color: isActive ? theme.colorScheme.primary : theme.textSecondary,
      fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
    );

    if (line.words.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(line.text, style: style),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: RichText(
        text: TextSpan(
          children: [
            for (final word in line.words)
              TextSpan(
                text: word.text,
                style: style?.copyWith(
                  color: isActive && positionMs >= word.timeMs
                      ? theme.colorScheme.primary
                      : style.color,
                  fontWeight: isActive && positionMs >= word.timeMs
                      ? FontWeight.w700
                      : style.fontWeight,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SpeedPitchTab extends ConsumerWidget {
  const _SpeedPitchTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);
    final (playbackRate, pitchSemitones, isPitchLinked) = ref.watch(
      playerControllerProvider.select(
        (s) => (s.playbackRate, s.pitchSemitones, s.isPitchLinked),
      ),
    );
    final controller = ref.read(playerControllerProvider.notifier);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        Text(
          t('player.speed_pitch'),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          t('player.speed'),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Slider(
          value: playbackRate,
          min: 0.5,
          max: 2,
          divisions: 30,
          label: '${playbackRate.toStringAsFixed(2)}x',
          onChanged: controller.setPlaybackRate,
        ),
        Center(
          child: Text(
            '${playbackRate.toStringAsFixed(2)}x',
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          t('player.pitch'),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Slider(
          value: pitchSemitones,
          min: -12,
          max: 12,
          divisions: 48,
          label: '${pitchSemitones.toStringAsFixed(1)} st',
          onChanged: controller.setPitchSemitones,
        ),
        Center(
          child: Text(
            '${pitchSemitones > 0 ? '+' : ''}${pitchSemitones.toStringAsFixed(1)} st',
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t('player.link_speed_pitch')),
          subtitle: Text(t('player.link_speed_pitch_hint')),
          value: isPitchLinked,
          onChanged: controller.setIsPitchLinked,
        ),
        const SizedBox(height: 16),
        const _LyricsOffsetSection(),
      ],
    );
  }
}

class _LyricsOffsetSection extends ConsumerWidget {
  const _LyricsOffsetSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);
    final lyrics = ref.watch(lyricsControllerProvider);
    final controller = ref.read(lyricsControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t('player.lyrics_offset'),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          t('player.lyrics_offset_hint'),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.textTertiary),
        ),
        Slider(
          value: lyrics.offsetMs.toDouble().clamp(-5000, 5000),
          min: -5000,
          max: 5000,
          divisions: 100,
          label: '${lyrics.offsetMs} ms',
          onChanged: (value) => controller.setOffset(value.round()),
        ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
              onPressed: () => controller.setOffset(lyrics.offsetMs - 100),
              child: Text(t('player.earlier')),
            ),
            Text(
              '${lyrics.offsetMs} ms',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTertiary,
              ),
            ),
            TextButton(
              onPressed: () => controller.setOffset(lyrics.offsetMs + 100),
              child: Text(t('player.later')),
            ),
            TextButton(
              onPressed: () => controller.setOffset(0),
              child: Text(t('player.reset')),
            ),
          ],
        ),
      ],
    );
  }
}
