import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// A glass panel with backdrop blur, border, and optional dimming.
/// The foundation of the glassmorphism system.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.opacity = DesignTokens.glassOpacityLight,
    this.blur = DesignTokens.glassBlurDefault,
    this.dim = DesignTokens.glassDimDefault,
    this.borderOpacity = DesignTokens.glassBorderDefault,
    this.borderColor,
    this.borderRadius = DesignTokens.radiusLg,
    this.shadows,
    this.onTap,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double opacity;
  final double blur;
  final double dim;
  final double borderOpacity;
  final Color? borderColor;
  final double borderRadius;
  final List<BoxShadow>? shadows;
  final VoidCallback? onTap;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveBorderColor = borderColor ?? Colors.white.withValues(alpha: borderOpacity);
    final effectiveShadows = shadows ?? (dim > 0.2 ? DesignTokens.shadowDefault : DesignTokens.shadowSubtle);

    final panel = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: opacity),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: effectiveBorderColor, width: 1),
            boxShadow: effectiveShadows,
          ),
          child: child,
        ),
      ),
    );

    if (dim <= 0) {
      return onTap != null
          ? Material(
              color: Colors.transparent,
              child: InkWell(onTap: onTap, child: panel),
            )
          : panel;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Dim layer behind the panel
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: ColoredBox(
              color: Colors.black.withValues(alpha: dim),
            ),
          ),
        ),
        panel,
      ],
    );
  }
}

/// A glass card - elevated glass panel with stronger visual weight.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(DesignTokens.spaceLg),
    this.onTap,
    this.selected = false,
    this.accentColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool selected;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = accentColor ?? theme.colorScheme.primary;

    return GlassPanel(
      opacity: selected ? DesignTokens.glassOpacityMedium : DesignTokens.glassOpacityLight,
      blur: DesignTokens.glassBlurDefault,
      dim: DesignTokens.glassDimDefault,
      borderOpacity: selected ? DesignTokens.glassBorderStrong : DesignTokens.glassBorderDefault,
      borderColor: selected ? accent.withValues(alpha: 0.4) : null,
      borderRadius: DesignTokens.radiusLg,
      shadows: selected ? DesignTokens.shadowElevated : DesignTokens.shadowDefault,
      padding: padding,
      onTap: onTap,
      child: child,
    );
  }
}

/// A glass container for the floating player bar.
class GlassPlayerBar extends StatelessWidget {
  const GlassPlayerBar({
    super.key,
    required this.child,
    this.accentColor,
    this.padding = const EdgeInsets.symmetric(
      horizontal: DesignTokens.spaceXl,
      vertical: DesignTokens.spaceMd,
    ),
  });

  final Widget child;
  final Color? accentColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = accentColor ?? theme.colorScheme.primary;

    return GlassPanel(
      opacity: DesignTokens.glassOpacityStrong,
      blur: DesignTokens.glassBlurStrong,
      dim: DesignTokens.glassDimStrong,
      borderOpacity: DesignTokens.glassBorderStrong,
      borderColor: accent.withValues(alpha: 0.25),
      borderRadius: DesignTokens.radiusXxl,
      shadows: DesignTokens.shadowPlayer,
      padding: padding,
      child: child,
    );
  }
}

/// A glass sheet for bottom sheets and modals.
class GlassSheet extends StatelessWidget {
  const GlassSheet({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(DesignTokens.spaceXxl),
    this.maxHeight,
    this.borderRadius = DesignTokens.radiusXxl,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? maxHeight;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: maxHeight ?? MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: GlassPanel(
        opacity: DesignTokens.glassOpacityOverlay,
        blur: DesignTokens.glassBlurOverlay,
        dim: DesignTokens.glassDimOverlay,
        borderOpacity: DesignTokens.glassBorderStrong,
        borderRadius: borderRadius,
        shadows: DesignTokens.shadowElevated,
        padding: padding,
        child: child,
      ),
    );
  }
}

/// A glass navigation rail/sidebar.
class GlassSidebar extends StatelessWidget {
  const GlassSidebar({
    super.key,
    required this.child,
    this.width = 200,
    this.accentColor,
  });

  final Widget child;
  final double width;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = accentColor ?? theme.colorScheme.primary;

    return SizedBox(
      width: width,
      child: GlassPanel(
        opacity: DesignTokens.glassOpacityLight,
        blur: DesignTokens.glassBlurDefault,
        dim: DesignTokens.glassDimDefault,
        borderOpacity: DesignTokens.glassBorderSubtle,
        borderColor: accent.withValues(alpha: 0.1),
        borderRadius: 0,
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(4, 0),
          ),
        ],
        padding: EdgeInsets.zero,
        clipBehavior: Clip.none,
        child: child,
      ),
    );
  }
}

/// A glass cover image with ambient glow.
class GlassCover extends StatefulWidget {
  const GlassCover({
    super.key,
    required this.url,
    this.size,
    this.width,
    this.height,
    this.borderRadius = DesignTokens.radiusMd,
    this.accentColor,
    this.showGlow = false,
    this.fit = BoxFit.cover,
  });

  final String url;
  final double? size;
  final double? width;
  final double? height;
  final double borderRadius;
  final Color? accentColor;
  final bool showGlow;
  final BoxFit fit;

  @override
  State<GlassCover> createState() => _GlassCoverState();
}

class _GlassCoverState extends State<GlassCover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = widget.accentColor ?? theme.colorScheme.primary;
    final w = widget.width ?? widget.size ?? 100;
    final h = widget.height ?? widget.size ?? 100;

    if (!widget.showGlow) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: _buildImage(context, w, h),
      );
    }

    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        final glowOpacity = 0.15 + 0.1 * _glowController.value;
        return Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: glowOpacity),
                blurRadius: 24,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: _buildImage(context, w, h),
          ),
        );
      },
    );
  }

  Widget _buildImage(BuildContext context, double w, double h) {
    final theme = Theme.of(context);
    if (widget.url.isEmpty) {
      return Container(
        width: w,
        height: h,
        color: theme.colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(
          Icons.music_note_rounded,
          color: theme.colorScheme.onSurfaceVariant,
          size: w * 0.4,
        ),
      );
    }

    return Image.network(
      widget.url,
      width: w,
      height: h,
      fit: widget.fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          width: w,
          height: h,
          color: theme.colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: CircularProgressIndicator(
            value: loadingProgress.expectedTotalBytes != null
                ? loadingProgress.cumulativeBytesLoaded /
                    loadingProgress.expectedTotalBytes!
                : null,
            strokeWidth: 2,
          ),
        );
      },
      errorBuilder: (_, __, ___) => Container(
        width: w,
        height: h,
        color: theme.colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(
          Icons.music_note_rounded,
          color: theme.colorScheme.onSurfaceVariant,
          size: w * 0.4,
        ),
      ),
    );
  }
}

/// Ambient background with animated gradient.
class AmbientBackground extends StatefulWidget {
  const AmbientBackground({
    super.key,
    required this.child,
    this.accentColor,
    this.intensity = 1.0,
  });

  final Widget child;
  final Color? accentColor;
  final double intensity;

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: DesignTokens.animAmbient,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = widget.accentColor ?? theme.colorScheme.primary;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final gradient = LinearGradient(
          begin: Alignment.lerp(Alignment.topLeft, Alignment.topRight, t)!,
          end: Alignment.lerp(Alignment.bottomRight, Alignment.bottomLeft, t)!,
          colors: [
            DesignTokens.ambientGradientPrimary.colors[0],
            Color.lerp(
              DesignTokens.ambientGradientPrimary.colors[1],
              accent.withValues(alpha: 0.08 * widget.intensity),
              t * 0.5,
            )!,
            Color.lerp(
              DesignTokens.ambientGradientPrimary.colors[2],
              accent.withValues(alpha: 0.05 * widget.intensity),
              t * 0.3,
            )!,
            DesignTokens.ambientGradientPrimary.colors[3],
          ],
          stops: DesignTokens.ambientGradientPrimary.stops,
        );

        return Container(
          decoration: BoxDecoration(gradient: gradient),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// A glass button with hover/tap states.
class GlassButton extends StatefulWidget {
  const GlassButton({
    super.key,
    required this.child,
    this.onPressed,
    this.padding = const EdgeInsets.symmetric(
      horizontal: DesignTokens.spaceLg,
      vertical: DesignTokens.spaceMd,
    ),
    this.borderRadius = DesignTokens.radiusMd,
    this.accentColor,
    this.variant = GlassButtonVariant.primary,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? accentColor;
  final GlassButtonVariant variant;

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

enum GlassButtonVariant {
  primary,
  secondary,
  ghost,
}

class _GlassButtonState extends State<GlassButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _hovering = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: DesignTokens.animFast,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateState(bool hover, bool press) {
    setState(() {
      _hovering = hover;
      _pressed = press;
    });
    if (hover || press) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = widget.accentColor ?? theme.colorScheme.primary;
    final isEnabled = widget.onPressed != null;

    double opacity;
    double borderOpacity;
    Color? bgColor;
    Color textColor;

    switch (widget.variant) {
      case GlassButtonVariant.primary:
        opacity = isEnabled
            ? (_pressed ? 0.3 : _hovering ? 0.2 : 0.12)
            : 0.06;
        borderOpacity = isEnabled
            ? (_pressed ? 0.4 : _hovering ? 0.3 : 0.15)
            : 0.08;
        bgColor = accent.withValues(alpha: opacity);
        textColor = theme.colorScheme.onPrimary;
        break;
      case GlassButtonVariant.secondary:
        opacity = isEnabled
            ? (_pressed ? 0.2 : _hovering ? 0.14 : 0.08)
            : 0.04;
        borderOpacity = isEnabled
            ? (_pressed ? 0.25 : _hovering ? 0.18 : 0.1)
            : 0.06;
        bgColor = Colors.white.withValues(alpha: opacity);
        textColor = theme.colorScheme.onSurface;
        break;
      case GlassButtonVariant.ghost:
        opacity = isEnabled
            ? (_pressed ? 0.1 : _hovering ? 0.06 : 0.0)
            : 0.0;
        borderOpacity = 0.0;
        bgColor = opacity > 0 ? Colors.white.withValues(alpha: opacity) : null;
        textColor = isEnabled ? accent : theme.colorScheme.onSurfaceVariant;
        break;
    }

    return MouseRegion(
      onEnter: (_) => _updateState(true, false),
      onExit: (_) => _updateState(false, false),
      child: GestureDetector(
        onTapDown: isEnabled ? (_) => _updateState(true, true) : null,
        onTapUp: isEnabled ? (_) => _updateState(true, false) : null,
        onTapCancel: isEnabled ? () => _updateState(true, false) : null,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: DesignTokens.animFast,
          curve: DesignTokens.curveStandard,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: borderOpacity > 0
                ? Border.all(
                    color: accent.withValues(alpha: borderOpacity),
                    width: 1,
                  )
                : null,
            boxShadow: _pressed || _hovering
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: DefaultTextStyle(
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// A glass icon button.
class GlassIconButton extends StatefulWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 40,
    this.iconSize = 20,
    this.accentColor,
    this.variant = GlassButtonVariant.ghost,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double iconSize;
  final Color? accentColor;
  final GlassButtonVariant variant;

  @override
  State<GlassIconButton> createState() => _GlassIconButtonState();
}

class _GlassIconButtonState extends State<GlassIconButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _hovering = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: DesignTokens.animFast,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateState(bool hover, bool press) {
    setState(() {
      _hovering = hover;
      _pressed = press;
    });
    if (hover || press) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = widget.accentColor ?? theme.colorScheme.primary;
    final isEnabled = widget.onPressed != null;

    double opacity;
    double borderOpacity;

    switch (widget.variant) {
      case GlassButtonVariant.primary:
        opacity = isEnabled
            ? (_pressed ? 0.3 : _hovering ? 0.2 : 0.12)
            : 0.06;
        borderOpacity = isEnabled
            ? (_pressed ? 0.4 : _hovering ? 0.3 : 0.15)
            : 0.08;
        break;
      case GlassButtonVariant.secondary:
        opacity = isEnabled
            ? (_pressed ? 0.2 : _hovering ? 0.14 : 0.08)
            : 0.04;
        borderOpacity = isEnabled
            ? (_pressed ? 0.25 : _hovering ? 0.18 : 0.1)
            : 0.06;
        break;
      case GlassButtonVariant.ghost:
        opacity = isEnabled
            ? (_pressed ? 0.1 : _hovering ? 0.06 : 0.0)
            : 0.0;
        borderOpacity = 0.0;
        break;
    }

    final bgColor = widget.variant == GlassButtonVariant.primary
        ? accent.withValues(alpha: opacity)
        : Colors.white.withValues(alpha: opacity);

    final iconColor = isEnabled
        ? (widget.variant == GlassButtonVariant.primary
            ? theme.colorScheme.onPrimary
            : theme.colorScheme.onSurface)
        : theme.colorScheme.onSurfaceVariant;

    final button = AnimatedContainer(
      duration: DesignTokens.animFast,
      curve: DesignTokens.curveStandard,
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
        border: borderOpacity > 0
            ? Border.all(
                color: accent.withValues(alpha: borderOpacity),
                width: 1,
              )
            : null,
        boxShadow: _pressed || _hovering
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Icon(
        widget.icon,
        size: widget.iconSize,
        color: iconColor,
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(
        message: widget.tooltip!,
        child: MouseRegion(
          onEnter: (_) => _updateState(true, false),
          onExit: (_) => _updateState(false, false),
          child: GestureDetector(
            onTapDown: isEnabled ? (_) => _updateState(true, true) : null,
            onTapUp: isEnabled ? (_) => _updateState(true, false) : null,
            onTapCancel: isEnabled ? () => _updateState(true, false) : null,
            onTap: widget.onPressed,
            child: button,
          ),
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => _updateState(true, false),
      onExit: (_) => _updateState(false, false),
      child: GestureDetector(
        onTapDown: isEnabled ? (_) => _updateState(true, true) : null,
        onTapUp: isEnabled ? (_) => _updateState(true, false) : null,
        onTapCancel: isEnabled ? () => _updateState(true, false) : null,
        onTap: widget.onPressed,
        child: button,
      ),
    );
  }
}

/// Prefer-reduced-motion aware animation wrapper.
class ReducedMotionAware extends StatelessWidget {
  const ReducedMotionAware({
    super.key,
    required this.child,
    this.animate = true,
    this.duration = DesignTokens.animDefault,
    this.curve = DesignTokens.curveStandard,
  });

  final Widget child;
  final bool animate;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final reduceMotion = mediaQuery.disableAnimations;

    if (!animate || reduceMotion) {
      return child;
    }

    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: curve,
      switchOutCurve: curve,
      child: child,
    );
  }
}
