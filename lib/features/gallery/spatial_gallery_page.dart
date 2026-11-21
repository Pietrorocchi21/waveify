import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/app_providers.dart';
import '../../core/theme/artwork_palette.dart';
import '../../shared/widgets/common.dart';
import '../artist/ui/artist_page.dart';
import '../library/library_controller.dart';
import 'gallery_art.dart';
import 'gallery_catalog.dart';
import 'spatial_album_page.dart';

class SpatialGalleryPage extends ConsumerWidget {
  const SpatialGalleryPage({super.key, this.artistId});

  final String? artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translatorProvider);
    List<GalleryAlbum> albums;
    if (artistId case final id?) {
      final artist = ref.watch(artistProvider(id));
      if (artist.isLoading && !artist.hasValue) return const LoadingState();
      if (artist.hasError && !artist.hasValue) {
        return ErrorState(
          message: '${artist.error}',
          onRetry: () => ref.invalidate(artistProvider(id)),
        );
      }
      final data = artist.requireValue;
      albums = [
        for (final release in data.albums)
          GalleryAlbum(
            id: release.id,
            title: release.title,
            artist: data.name,
            year: release.year,
            cover: release.cover?.url ?? '',
          ),
      ];
    } else {
      final saved = ref.watch(
        libraryControllerProvider.select((s) => s.savedAlbums),
      );
      albums = [
        for (final item in saved)
          if (item.id.isNotEmpty)
            GalleryAlbum(
              id: item.id,
              title: item.title,
              artist: item.subtitle,
              cover: item.coverUrl,
            ),
      ];
    }

    if (albums.isEmpty) albums = demoAlbums;
    return _SpatialRoom(
      key: ValueKey(albums.map((item) => item.id).join('|')),
      albums: albums,
      title: t('gallery.title'),
    );
  }
}

class _SpatialRoom extends ConsumerStatefulWidget {
  const _SpatialRoom({super.key, required this.albums, required this.title});
  final List<GalleryAlbum> albums;
  final String title;

  @override
  ConsumerState<_SpatialRoom> createState() => _SpatialRoomState();
}

class _SpatialRoomState extends ConsumerState<_SpatialRoom>
    with SingleTickerProviderStateMixin {
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 105,
    damping: 19,
  );
  late final _camera = AnimationController.unbounded(vsync: this)
    ..addListener(_onCamera);
  int _focused = 0;
  int _target = 0;
  bool _plain = false;
  int _request = 0;
  final Map<int, Object> _heroTags = {};
  final _stageFocus = FocusNode(debugLabel: 'Waveify spatial gallery');

  int get _last => widget.albums.length - 1;

  void _onCamera() {
    final next = _camera.value.round().clamp(0, _last);
    if (next != _focused) setState(() => _focused = next);
  }

  @override
  void dispose() {
    _camera.dispose();
    _stageFocus.dispose();
    super.dispose();
  }

  Object _heroTag(int index) => _heroTags.putIfAbsent(index, Object.new);

  Future<void> _moveTo(int index, {double velocity = 0}) async {
    _target = index.clamp(0, _last);
    if (MediaQuery.disableAnimationsOf(context) || _plain) {
      _camera.value = _target.toDouble();
      return;
    }
    await _camera
        .animateWith(
          SpringSimulation(
            _spring,
            _camera.value,
            _target.toDouble(),
            velocity,
          ),
        )
        .orCancel;
  }

  void _step(int direction) {
    _request++;
    _moveTo(_target + direction).catchError((Object error) {
      if (error is! TickerCanceled) throw error;
    });
  }

  Future<void> _open(int index) async {
    final request = ++_request;
    try {
      await _moveTo(index);
    } on TickerCanceled {
      return;
    }
    if (!mounted || request != _request) return;
    final album = widget.albums[index];
    final reduced = MediaQuery.disableAnimationsOf(context) || _plain;
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: reduced
            ? Duration.zero
            : const Duration(milliseconds: 780),
        reverseTransitionDuration: reduced
            ? Duration.zero
            : const Duration(milliseconds: 680),
        pageBuilder: (context, _, _) =>
            SpatialAlbumPage(album: album, heroTag: _heroTag(index)),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: animation.drive(CurveTween(curve: Curves.easeInOutCubic)),
          child: child,
        ),
      ),
    );
    if (mounted && request == _request) {
      _stageFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translatorProvider);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final current = widget.albums[_focused];
    final reduced = MediaQuery.disableAnimationsOf(context);
    final flat = reduced || _plain;
    final accent = current.isDemo
        ? galleryDemoTint(current.demoIndex)
        : ref.watch(artworkPaletteProvider(current.cover)).asData?.value ??
              (dark ? const Color(0xFFC247C8) : const Color(0xFF920C7B));
    final surface = dark ? const Color(0xFF08080C) : const Color(0xFFFBF7FC);
    final secondary = dark ? const Color(0xFF12121A) : const Color(0xFFF0E7F3);
    return AnimatedContainer(
      duration: reduced ? Duration.zero : const Duration(milliseconds: 540),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -.25),
          radius: .96,
          colors: [
            Color.alphaBlend(
              accent.withValues(alpha: dark ? .22 : .16),
              secondary,
            ),
            surface,
          ],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final coverSize = math
              .min(
                constraints.maxHeight * .45,
                (constraints.maxWidth * .56).clamp(128.0, 340.0),
              )
              .clamp(68.0, 340.0);
          final step = coverSize * (flat ? .92 : .73);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: [
                    BackButton(
                      color: theme.colorScheme.onSurface,
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/');
                        }
                      },
                    ),
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: t('gallery.standard'),
                      isSelected: _plain,
                      onPressed: reduced
                          ? null
                          : () {
                              _step(0);
                              setState(() => _plain = !_plain);
                            },
                      icon: const Icon(Icons.view_in_ar_outlined),
                      selectedIcon: const Icon(Icons.view_carousel_outlined),
                    ),
                  ],
                ),
              ),
              if (current.isDemo)
                Text(t('gallery.demo'), style: theme.textTheme.labelLarge),
              Expanded(
                child: Focus(
                  focusNode: _stageFocus,
                  onKeyEvent: (_, event) {
                    if (event is! KeyDownEvent) return KeyEventResult.ignored;
                    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                      _step(-1);
                    } else if (event.logicalKey ==
                        LogicalKeyboardKey.arrowRight) {
                      _step(1);
                    } else if (event.logicalKey == LogicalKeyboardKey.enter &&
                        identical(
                          FocusManager.instance.primaryFocus,
                          _stageFocus,
                        )) {
                      _open(_focused);
                    } else {
                      return KeyEventResult.ignored;
                    }
                    return KeyEventResult.handled;
                  },
                  child: Listener(
                    onPointerSignal: (event) {
                      if (event is! PointerScrollEvent) return;
                      GestureBinding.instance.pointerSignalResolver.register(
                        event,
                        (_) {
                          final delta = event.scrollDelta;
                          final value = delta.dx.abs() > delta.dy.abs()
                              ? delta.dx
                              : delta.dy;
                          if (value != 0) _step(value.isNegative ? -1 : 1);
                        },
                      );
                    },
                    child: GestureDetector(
                      key: const ValueKey('spatial-gallery-stage'),
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: (_) {
                        _request++;
                        _camera.stop();
                      },
                      onHorizontalDragUpdate: (event) {
                        _camera.value = (_camera.value - event.delta.dx / step)
                            .clamp(0.0, _last.toDouble());
                      },
                      onHorizontalDragEnd: (event) {
                        final velocity = (-event.primaryVelocity! / step).clamp(
                          -7.0,
                          7.0,
                        );
                        _target = (_camera.value + velocity * .23)
                            .round()
                            .clamp(0, _last);
                        _moveTo(
                          _target,
                          velocity: flat ? 0 : velocity,
                        ).catchError((Object error) {
                          if (error is! TickerCanceled) throw error;
                        });
                      },
                      onHorizontalDragCancel: () {
                        _target = _focused;
                        _step(0);
                      },
                      child: RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _camera,
                          builder: (context, _) {
                            final center = _camera.value.clamp(
                              0.0,
                              _last.toDouble(),
                            );
                            final visible =
                                [
                                  for (
                                    var i = math.max(0, center.floor() - 4);
                                    i <= math.min(_last, center.ceil() + 4);
                                    i++
                                  )
                                    i,
                                ]..sort(
                                  (a, b) => (b - center).abs().compareTo(
                                    (a - center).abs(),
                                  ),
                                );
                            return Stack(
                              fit: StackFit.expand,
                              clipBehavior: Clip.hardEdge,
                              children: [
                                if (!flat)
                                  IgnorePointer(
                                    child: CustomPaint(
                                      painter: _RoomFloor(accent, center),
                                    ),
                                  ),
                                for (final index in visible)
                                  _cover(
                                    index,
                                    center,
                                    step,
                                    coverSize,
                                    flat,
                                    accent,
                                    reduced,
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 14),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: MaterialLocalizations.of(context)
                          .previousPageTooltip,
                      onPressed: _focused == 0 ? null : () => _step(-1),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            current.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge,
                          ),
                          Text(
                            '${current.artist} · ${_focused + 1} / ${widget.albums.length}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          TextButton(
                            onPressed: () => _open(_focused),
                            child: Text(t('artist.open_album')),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(context)
                          .nextPageTooltip,
                      onPressed: _focused == _last ? null : () => _step(1),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _cover(
    int index,
    double camera,
    double step,
    double size,
    bool flat,
    Color accent,
    bool reduced,
  ) {
    final album = widget.albums[index];
    final distance = index - camera;
    final magnitude = distance.abs();
    final angle = (distance * .28).clamp(-1.35, 1.35);
    final depth = flat ? 0.0 : (1 - math.cos(angle)) * size * 1.85;
    final x = flat ? distance * step : math.sin(angle) / .28 * step;
    final lift = flat ? 0.0 : depth * .11;
    final matrix = Matrix4.identity()
      ..setEntry(3, 2, flat ? 0 : -.00125)
      ..translateByDouble(x, lift, -depth, 1)
      ..rotateY(flat ? 0 : -angle * .82);
    final focused = index == _focused;
    return Center(
      key: ValueKey(index),
      child: Transform(
        alignment: Alignment.center,
        transform: matrix,
        child: Opacity(
          opacity: (1 - magnitude * (flat ? .22 : .24)).clamp(.06, 1.0),
          child: Semantics(
            button: true,
            selected: focused,
            label: album.title,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                hoverDuration: reduced
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                onTap: () => _open(index),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: focused && !flat
                        ? [
                            BoxShadow(
                              color: accent.withValues(alpha: .28),
                              blurRadius: 32,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: Hero(
                    tag: _heroTag(index),
                    child: RepaintBoundary(
                      child: GalleryArt(album: album, size: size),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomFloor extends CustomPainter {
  const _RoomFloor(this.accent, this.camera);
  final Color accent;
  final double camera;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2 - (camera % 1 - .5) * 20;
    final y = size.height * .68;
    final paint = Paint()
      ..color = accent.withValues(alpha: .16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 5; i++) {
      final path = Path()
        ..moveTo(0, y + i * i * 5)
        ..quadraticBezierTo(x, y + 18 + i * i * 7, size.width, y + i * i * 5);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_RoomFloor oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.camera != camera;
}
