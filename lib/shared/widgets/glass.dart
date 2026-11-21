import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import 'common.dart';

/// Clipped blur only on important surfaces. The opaque tint remains readable
/// when accessibility requests reduced transparency or blur is disabled.
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
  final double opacity, blur, dim, borderOpacity, borderRadius;
  final Color? borderColor;
  final List<BoxShadow>? shadows;
  final VoidCallback? onTap;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final solid = MediaQuery.maybeOf(context)?.highContrast ?? false;
    final dark = theme.brightness == Brightness.dark;
    final radius = BorderRadius.circular(borderRadius);
    Widget surface = Material(
      color: (dark ? const Color(0xFF151C2B) : Colors.white).withValues(
        alpha: solid ? 1 : (0.55 + opacity + dim * 0.2).clamp(0, 1),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color:
              borderColor ??
              (dark ? Colors.white : Colors.black).withValues(
                alpha: borderOpacity,
              ),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
      ),
    );
    if (blur > 0 && !solid) {
      surface = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: surface,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: shadows),
      child: ClipRRect(
        borderRadius: radius,
        clipBehavior: clipBehavior,
        child: surface,
      ),
    );
  }
}

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
  Widget build(BuildContext context) => GlassPanel(
    // Lists/cards use tint without a costly backdrop filter per row.
    blur: 0,
    dim: 0,
    opacity: selected ? 0.22 : 0,
    borderColor: selected
        ? (accentColor ?? Theme.of(context).colorScheme.primary).withValues(
            alpha: 0.3,
          )
        : null,
    padding: padding,
    onTap: onTap,
    child: child,
  );
}

class GlassPlayerBar extends StatelessWidget {
  const GlassPlayerBar({
    super.key,
    required this.child,
    this.accentColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  });
  final Widget child;
  final Color? accentColor;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => GlassPanel(
    blur: DesignTokens.glassBlurStrong,
    opacity: 0.18,
    dim: 0.2,
    borderRadius: DesignTokens.radiusXxl,
    shadows: DesignTokens.shadowPlayer,
    padding: padding,
    child: child,
  );
}

class GlassSheet extends StatelessWidget {
  const GlassSheet({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.maxHeight,
    this.borderRadius = DesignTokens.radiusXxl,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? maxHeight;
  final double borderRadius;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: maxHeight ?? MediaQuery.sizeOf(context).height * 0.85,
      child: GlassPanel(
        opacity: 0.35,
        blur: 24,
        padding: padding,
        borderRadius: borderRadius,
        child: child,
      ),
    ),
  );
}

class GlassSidebar extends StatelessWidget {
  const GlassSidebar({
    super.key,
    required this.child,
    this.width = 208,
    this.accentColor,
  });
  final Widget child;
  final double width;
  final Color? accentColor;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: GlassPanel(
      blur: 0,
      opacity: 0,
      dim: 0,
      borderRadius: 22,
      child: child,
    ),
  );
}

class GlassCover extends StatelessWidget {
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
  final double? size, width, height;
  final double borderRadius;
  final Color? accentColor;
  final bool showGlow;
  final BoxFit fit;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: showGlow
          ? DesignTokens.shadowCoverGlow(
              accentColor ?? Theme.of(context).colorScheme.primary,
            )
          : null,
    ),
    child: CoverImage(
      url: url,
      width: width ?? size,
      height: height ?? size,
      size: size,
      borderRadius: borderRadius,
      fit: fit,
    ),
  );
}

/// Static radial light avoids perpetual GPU work and never implies beat sync.
/// Only a track/palette change animates, respecting Flutter's reduced motion.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({
    super.key,
    required this.child,
    this.accentColor,
    this.intensity = 1,
  });
  final Widget child;
  final Color? accentColor;
  final double intensity;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = accentColor ?? theme.colorScheme.primary;
    final dark = theme.brightness == Brightness.dark;
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedContainer(
      duration: reduced ? Duration.zero : DesignTokens.animSlowest,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        gradient: RadialGradient(
          center: const Alignment(0.15, -0.15),
          radius: 1.1,
          colors: [
            Color.alphaBlend(
              accent.withValues(alpha: (dark ? 0.29 : 0.08) * intensity),
              theme.scaffoldBackgroundColor,
            ),
            theme.scaffoldBackgroundColor,
          ],
        ),
      ),
      child: child,
    );
  }
}

enum GlassButtonVariant { primary, secondary, ghost }

class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.child,
    this.onPressed,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = accentColor ?? theme.colorScheme.primary;
    final primary = variant == GlassButtonVariant.primary;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: padding,
        foregroundColor: primary
            ? theme.colorScheme.onPrimary
            : theme.colorScheme.onSurface,
        backgroundColor: primary
            ? accent
            : variant == GlassButtonVariant.secondary
            ? theme.colorScheme.onSurface.withValues(alpha: 0.08)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
      child: child,
    );
  }
}

class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 44,
    this.iconSize = 22,
    this.accentColor,
    this.variant = GlassButtonVariant.ghost,
  });
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size, iconSize;
  final Color? accentColor;
  final GlassButtonVariant variant;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = variant == GlassButtonVariant.primary;
    final accent = accentColor ?? theme.colorScheme.primary;
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: iconSize),
      style: IconButton.styleFrom(
        minimumSize: Size(size < 48 ? 48 : size, size < 48 ? 48 : size),
        foregroundColor: primary
            ? theme.colorScheme.onPrimary
            : theme.colorScheme.onSurface,
        backgroundColor: primary
            ? accent
            : variant == GlassButtonVariant.secondary
            ? accent.withValues(alpha: 0.16)
            : Colors.transparent,
        focusColor: accent.withValues(alpha: 0.3),
        hoverColor: accent.withValues(alpha: 0.14),
      ),
    );
  }
}

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
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: !animate || MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : duration,
    switchInCurve: curve,
    switchOutCurve: curve,
    child: child,
  );
}
