import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' as media;
import 'package:media_kit_video/media_kit_video.dart';

import '../core/providers/app_providers.dart';
import '../features/player/player_controller.dart';
import '../features/player/player_state.dart';

/// A muted visual companion to the audio transport.
class PlaybackVideoBackdrop extends ConsumerWidget {
  const PlaybackVideoBackdrop({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!Platform.isWindows ||
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.highContrastOf(context) ||
        !ref.watch(settingsProvider.select((s) => s.videoBackdrop))) {
      return const SizedBox.shrink();
    }

    final (url, headers, available) = ref.watch(
      playerControllerProvider.select(
        (s) => (
          s.backdropVideoUrl,
          s.backdropVideoHeaders,
          s.status == PlayerStatus.playing || s.status == PlayerStatus.paused,
        ),
      ),
    );
    if (url == null || !available) return const SizedBox.shrink();
    return _MutedVideo(key: ValueKey(url), url: url, headers: headers);
  }
}

class _MutedVideo extends ConsumerStatefulWidget {
  const _MutedVideo({super.key, required this.url, required this.headers});

  final String url;
  final Map<String, String> headers;

  @override
  ConsumerState<_MutedVideo> createState() => _MutedVideoState();
}

class _MutedVideoState extends ConsumerState<_MutedVideo> {
  media.Player? _player;
  VideoController? _controller;
  StreamSubscription<String>? _errors;
  bool _ready = false;
  bool _syncing = false;
  bool _failed = false;
  final _syncClock = Stopwatch()..start();
  int _lastPositionCheck = -1000;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_open());
    });
  }

  Future<void> _open() async {
    try {
      final player = media.Player();
      _player = player;
      final controller = VideoController(player);
      setState(() => _controller = controller);
      _errors = player.stream.error.listen((_) => _hide());
      await player.setVolume(0);
      if (!mounted || _failed) return;
      await player
          .open(
            media.Media(widget.url, httpHeaders: widget.headers),
            play: false,
          )
          .timeout(const Duration(seconds: 12));
      if (!mounted || _failed) return;
      await player.setAudioTrack(media.AudioTrack.no());
      if (!mounted || _failed) return;
      await _followTransport(initial: true);
      await controller.waitUntilFirstFrameRendered.timeout(
        const Duration(seconds: 12),
      );
      if (mounted && !_failed) setState(() => _ready = true);
    } catch (_) {
      _hide();
    }
  }

  void _hide() {
    if (!mounted || _failed) return;
    setState(() {
      _failed = true;
      _ready = false;
    });
    final player = _player;
    _player = null;
    if (player != null) unawaited(player.dispose().catchError((Object _) {}));
  }

  Future<void> _followTransport({bool initial = false}) async {
    final player = _player;
    if (player == null || _failed || _syncing || (!initial && !_ready)) return;
    final state = ref.read(playerControllerProvider);
    _syncing = true;
    try {
      if (player.state.rate != state.playbackRate) {
        await player.setRate(state.playbackRate);
      }
      if (!mounted || _failed) return;
      final now = _syncClock.elapsedMilliseconds;
      if (initial || now - _lastPositionCheck >= 650) {
        _lastPositionCheck = now;
        final drift = (player.state.position - state.position).inMilliseconds
            .abs();
        if (initial || drift > 750) await player.seek(state.position);
      }
      if (!mounted || _failed) return;
      if (state.isPlaying != player.state.playing) {
        if (state.isPlaying) {
          await player.play();
        } else {
          await player.pause();
        }
      }
    } catch (_) {
      _hide();
    } finally {
      _syncing = false;
    }
  }

  @override
  void dispose() {
    unawaited(_errors?.cancel());
    final player = _player;
    _player = null;
    if (player != null) unawaited(player.dispose().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      playerControllerProvider.select(
        (s) => (s.position, s.status, s.playbackRate),
      ),
      (_, _) => unawaited(_followTransport()),
    );
    final controller = _controller;
    if (controller == null || _failed) return const SizedBox.shrink();
    return IgnorePointer(
      child: ExcludeSemantics(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 420),
          opacity: _ready ? 1 : 0,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Video(
                controller: controller,
                fit: BoxFit.cover,
                controls: NoVideoControls,
                wakelock: false,
                resumeUponEnteringForegroundMode: true,
              ),
              const ColoredBox(color: Color(0x90071124)),
            ],
          ),
        ),
      ),
    );
  }
}
