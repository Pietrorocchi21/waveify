import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../models/lyrics.dart';
import '../../../models/track.dart';
import '../../../shared/widgets/common.dart';
import '../../lyrics/lyrics_controller.dart';
import '../player_controller.dart';
import '../player_state.dart';
import 'cover_visualizer.dart';
import 'mini_player.dart';

class FullscreenPlayerPage extends ConsumerWidget {
  const FullscreenPlayerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translatorProvider);
    final (track, playbackContext) = ref.watch(
      playerControllerProvider.select(
        (s) => (s.currentTrack, s.playbackContext),
      ),
    );
    final controller = ref.read(playerControllerProvider.notifier);

    if (track == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.music_note_rounded,
          title: t('player.nothing_playing'),
          description: t('player.choose_track'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(
              t('player.playing_from'),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.textTertiary,
              ),
            ),
            Text(
              playbackContext ?? t('common.app.name'),
              style: theme.textTheme.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: t('player.queue'),
            onPressed: () => showQueueSheet(context, ref),
            icon: const Icon(Icons.queue_music_rounded),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 980;

          if (!isDesktop) {
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    children: [
                      SizedBox(height: 320, child: _ArtworkTab(track: track)),
                      const SizedBox(height: 20),
                      _TransportBar(controller: controller),
                      const SizedBox(height: 16),
                      const _LyricsPanel(),
                      const SizedBox(height: 16),
                      const _SpeedPitchPanel(),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: _TimelineRow(onSeek: controller.seek),
                ),
              ],
            );
          }

          return Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 11,
                        child: Column(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: _ArtworkTab(track: track),
                              ),
                            ),
                            const SizedBox(height: 20),
                            _TransportBar(controller: controller),
                          ],
                        ),
                      ),
                      const SizedBox(width: 24),
                      const Expanded(
                        flex: 10,
                        child: Column(
                          children: [
                            Expanded(child: _LyricsPanel()),
                            SizedBox(height: 16),
                            SizedBox(height: 280, child: _SpeedPitchPanel()),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: _TimelineRow(onSeek: controller.seek),
              ),
            ],
          );
        },
      ),
    );
  }
}

String _formatMs(int milliseconds) {
  final total = milliseconds ~/ 1000;
  final minutes = total ~/ 60;
  final seconds = total % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

class _TimelineRow extends ConsumerWidget {
  const _TimelineRow({required this.onSeek});

  final Future<void> Function(Duration) onSeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final (position, duration) = ref.watch(
      playerControllerProvider.select((s) => (s.position, s.duration)),
    );

    final max = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;
    final value = duration.inMilliseconds > 0
        ? position.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble()
        : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          Text(
            _formatMs(position.inMilliseconds),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.textTertiary,
            ),
          ),
          Expanded(
            child: Slider(
              value: value,
              max: max,
              onChanged: (next) => onSeek(Duration(milliseconds: next.round())),
            ),
          ),
          Text(
            _formatMs(duration.inMilliseconds),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArtworkTab extends StatelessWidget {
  const _ArtworkTab({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CoverVisualizer(
            coverUrl: track.coverUrl,
            tint: theme.colorScheme.primary,
          ),
        ),
        ColoredBox(
          color: theme.scaffoldBackgroundColor.withValues(alpha: 0.55),
        ),
        Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 32,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: CoverImage(url: track.coverUrl, borderRadius: 24),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TransportBar extends ConsumerWidget {
  const _TransportBar({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final (status, track, volume) = ref.watch(
      playerControllerProvider.select(
        (s) => (s.status, s.currentTrack, s.volume),
      ),
    );
    final isPlaying = status == PlayerStatus.playing;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Text(
            track?.title ?? '',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            track?.artists ?? '',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.textTertiary,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const ShuffleButton(),
              const SizedBox(width: 8),
              IconButton(
                iconSize: 36,
                tooltip: 'Previous',
                onPressed: controller.skipPrevious,
                icon: const Icon(Icons.skip_previous_rounded),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                iconSize: 38,
                onPressed: controller.togglePlayPause,
                icon: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                iconSize: 36,
                tooltip: 'Next',
                onPressed: controller.skipNext,
                icon: const Icon(Icons.skip_next_rounded),
              ),
              const SizedBox(width: 8),
              const RepeatButton(),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.volume_down_rounded,
                size: 18,
                color: theme.textTertiary,
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 180,
                child: Slider(value: volume, onChanged: controller.setVolume),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.volume_up_rounded,
                size: 18,
                color: theme.textTertiary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LyricsPanel extends StatelessWidget {
  const _LyricsPanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: const _LyricsTab(),
    );
  }
}

class _SpeedPitchPanel extends StatelessWidget {
  const _SpeedPitchPanel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      child: const _SpeedPitchTab(),
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
        if (lyrics.isLoading)
          const LoadingState()
        else if (lyrics.error != null)
          ErrorState(message: lyrics.error!)
        else if (lyrics.parsed == null ||
            (lyrics.parsed!.syncedLines.isEmpty &&
                lyrics.parsed!.plainLyrics == null))
          EmptyState(
            icon: Icons.lyrics_outlined,
            title: t('player.no_lyrics'),
            description: t('player.no_lyrics_found'),
          )
        else
          _SyncedLyricsView(lyrics: lyrics.parsed!),
        if (lyrics.parsed?.plainLyrics != null &&
            (lyrics.parsed?.syncedLines.isEmpty ?? true))
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              lyrics.parsed!.plainLyrics!,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}

class _SyncedLyricsView extends ConsumerWidget {
  const _SyncedLyricsView({required this.lyrics});

  final ParsedLyrics lyrics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final positionMs = ref.watch(
      playerControllerProvider.select((s) => s.position.inMilliseconds),
    );

    var activeIndex = -1;
    for (var i = 0; i < lyrics.syncedLines.length; i++) {
      final line = lyrics.syncedLines[i];
      if (positionMs >= line.timeMs) {
        activeIndex = i;
      } else {
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lyrics.syncedLines.length; i++)
          AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: i == activeIndex ? 1 : 0.68,
            child: _LyricLineView(
              line: lyrics.syncedLines[i],
              isActive: i == activeIndex,
              positionMs: positionMs,
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
