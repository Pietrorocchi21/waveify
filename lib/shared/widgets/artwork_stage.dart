import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/artwork_palette.dart';
import '../../core/theme/design_tokens.dart';
import 'common.dart';

/// Presentation data only: every item points to an existing track or mix.
class StageArtwork {
  const StageArtwork({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.onActivate,
    this.actionLabel,
  });
  final String id, title, subtitle, coverUrl;
  final VoidCallback? onActivate;
  final String? actionLabel;
}

/// A cover-led listening scene, with no card surfaces around the artwork.
/// Selection never starts playback; activating the centred cover is explicit.
class ArtworkStage extends ConsumerStatefulWidget {
  const ArtworkStage({
    super.key,
    required this.items,
    this.initialIndex = 0,
    required this.actionLabel,
    this.large = false,
  });
  final List<StageArtwork> items;
  final int initialIndex;
  final String actionLabel;
  final bool large;
  @override
  ConsumerState<ArtworkStage> createState() => _ArtworkStageState();
}

class _ArtworkStageState extends ConsumerState<ArtworkStage> {
  late PageController _controller;
  late int _page;
  double _fraction = 0;
  int? _focusedPage;
  int get _selected => _page % widget.items.length;

  @override
  void initState() {
    super.initState();
    _page = widget.items.length <= 1
        ? 0
        : widget.items.length * 100 +
              widget.initialIndex.clamp(0, widget.items.length - 1);
  }

  @override
  void didUpdateWidget(ArtworkStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIndex != widget.initialIndex &&
        widget.items.isNotEmpty) {
      final target = widget.initialIndex.clamp(0, widget.items.length - 1);
      _page = widget.items.length <= 1 ? 0 : _page - _selected + target;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _fraction != 0 && _controller.hasClients) {
          _controller.jumpToPage(_page);
        }
      });
    }
  }

  @override
  void dispose() {
    if (_fraction != 0) _controller.dispose();
    super.dispose();
  }

  void _go(int page, bool reduced) {
    if (reduced) {
      _controller.jumpToPage(page);
      return;
    }
    _controller.animateToPage(
      page,
      duration: DesignTokens.animSlow,
      curve: DesignTokens.curveStandard,
    );
  }

  void _move(int delta, bool reduced) => _go(_page + delta, reduced);

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    final selected = widget.items[_selected];
    final tint =
        ref.watch(artworkPaletteProvider(selected.coverUrl)).asData?.value ??
        theme.colorScheme.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;
        final fraction = wide ? 0.40 : 0.76;
        if (_fraction != fraction) {
          if (_fraction != 0) {
            final previous = _controller;
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => previous.dispose(),
            );
          }
          _fraction = fraction;
          _controller = PageController(
            initialPage: _page,
            viewportFraction: fraction,
          );
        }
        final coverSize = (constraints.maxWidth * fraction - (wide ? 36 : 16))
            .clamp(
              120.0,
              widget.large
                  ? DesignTokens.focusedArtworkSize
                  : DesignTokens.sceneArtworkSize,
            );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: coverSize + (wide ? 64 : 42),
              child: Stack(
                children: [
                  PageView.builder(
                    key: ValueKey(fraction),
                    controller: _controller,
                    onPageChanged: (page) => setState(() => _page = page),
                    itemCount: widget.items.length == 1 ? 1 : null,
                    itemBuilder: (context, page) {
                      final item = widget.items[page % widget.items.length];
                      return AnimatedBuilder(
                        animation: _controller,
                        builder: (context, child) {
                          final position =
                              _controller.hasClients &&
                                  _controller.position.hasContentDimensions
                              ? _controller.page ?? _page.toDouble()
                              : _page.toDouble();
                          final distance = (page - position).clamp(-1.5, 1.5);
                          final active =
                              page == _page || widget.items.length == 1;
                          final scale = reduced
                              ? 1.0
                              : 1 -
                                    distance.abs().clamp(0, 1) *
                                        (1 - DesignTokens.carouselItemScale);
                          final transform = Matrix4.identity()
                            ..setEntry(3, 2, DesignTokens.carouselPerspective)
                            ..translateByDouble(
                              wide ? -distance * coverSize * 0.80 : 0,
                              wide ? distance.abs() * 10 : 0,
                              0,
                              1,
                            );
                          if (!reduced) {
                            transform.rotateY(
                              -distance * DesignTokens.carouselRotation,
                            );
                          }
                          return Center(
                            child: Transform.scale(
                              scale: scale,
                              child: Transform(
                                alignment: Alignment.center,
                                transform: transform,
                                child: Opacity(
                                  opacity: active
                                      ? 1
                                      : DesignTokens.carouselItemOpacity,
                                  child: SizedBox(
                                    width: coverSize,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Semantics(
                                          label: item.title,
                                          selected: active,
                                          button: true,
                                          child: Tooltip(
                                            message: active
                                                ? item.actionLabel ??
                                                      widget.actionLabel
                                                : item.title,
                                            child: Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                onFocusChange: (focused) =>
                                                    setState(
                                                      () => _focusedPage =
                                                          focused ? page : null,
                                                    ),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      DesignTokens.radiusLg,
                                                    ),
                                                onTap: active
                                                    ? item.onActivate
                                                    : () => _go(page, reduced),
                                                child: Container(
                                                  width: coverSize,
                                                  height: coverSize,
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          DesignTokens.radiusLg,
                                                        ),
                                                    border: Border.all(
                                                      color:
                                                          _focusedPage == page
                                                          ? theme
                                                                .colorScheme
                                                                .primary
                                                          : Colors.white
                                                                .withValues(
                                                                  alpha: active
                                                                      ? 0.18
                                                                      : 0.06,
                                                                ),
                                                      width:
                                                          _focusedPage == page
                                                          ? 2
                                                          : 1,
                                                    ),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black
                                                            .withValues(
                                                              alpha: 0.5,
                                                            ),
                                                        blurRadius: 36,
                                                        offset: const Offset(
                                                          0,
                                                          22,
                                                        ),
                                                      ),
                                                      if (active)
                                                        BoxShadow(
                                                          color: tint
                                                              .withValues(
                                                                alpha: 0.12,
                                                              ),
                                                          blurRadius: 60,
                                                          spreadRadius: -12,
                                                        ),
                                                    ],
                                                  ),
                                                  child: CoverImage(
                                                    url: item.coverUrl,
                                                    size: coverSize,
                                                    borderRadius:
                                                        DesignTokens.radiusLg,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: AnimatedSwitcher(
                duration: reduced ? Duration.zero : DesignTokens.animDefault,
                child: Column(
                  key: ValueKey(selected.id),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      selected.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontSize: wide ? 32 : 24,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.7,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      selected.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.items.length > 1)
                  IconButton(
                    tooltip: MaterialLocalizations.of(context)
                        .previousPageTooltip,
                    onPressed: () => _move(-1, reduced),
                    icon: const Icon(Icons.chevron_left_rounded, size: 20),
                  ),
                TextButton.icon(
                  onPressed: selected.onActivate,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(selected.actionLabel ?? widget.actionLabel),
                ),
                if (widget.items.length > 1)
                  IconButton(
                    tooltip: MaterialLocalizations.of(context).nextPageTooltip,
                    onPressed: () => _move(1, reduced),
                    icon: const Icon(Icons.chevron_right_rounded, size: 20),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
