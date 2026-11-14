import 'package:flutter/material.dart';

/// Extended design tokens for the iBaila-inspired WAVEIFY redesign.
/// Centralizes colors, spacing, radii, shadows, glass effects, and animation durations.
class DesignTokens {
  DesignTokens._();

  // ===========================================================================
  // BASE COLORS - Dark atmospheric palette (near-black, charcoal, midnight blue)
  // ===========================================================================
  static const Color _baseCanvas = Color(0xFF030306);
  static const Color _baseSurface = Color(0xFF0A0A12);
  static const Color _baseElevated = Color(0xFF11111A);
  static const Color _basePanel = Color(0xFF16161F);
  static const Color _baseOverlay = Color(0xCC030306);

  static const Color _baseTextPrimary = Color(0xFFFFFFFF);
  static const Color _baseTextSecondary = Color(0xB3FFFFFF);
  static const Color _baseTextTertiary = Color(0x73FFFFFF);
  static const Color _baseTextQuaternary = Color(0x4DFFFFFF);

  static const Color _baseBorderPrimary = Color(0xFF1E1E2A);
  static const Color _baseBorderSecondary = Color(0xFF2A2A3A);
  static const Color _baseBorderTertiary = Color(0xFF3A3A4A);

  // ===========================================================================
  // AMBIENT GRADIENTS
  // ===========================================================================
  static const LinearGradient ambientGradientPrimary = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF030306),
      Color(0xFF0A0A12),
      Color(0xFF0D0D16),
      Color(0xFF080810),
    ],
    stops: [0.0, 0.35, 0.7, 1.0],
  );

  static const LinearGradient ambientGradientSecondary = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF05050C),
      Color(0xFF0A0A14),
      Color(0xFF0F0F1A),
      Color(0xFF080810),
    ],
    stops: [0.0, 0.4, 0.8, 1.0],
  );

  static LinearGradient accentGradient(Color accent, {double opacity = 0.15}) {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        accent.withValues(alpha: opacity * 0.6),
        accent.withValues(alpha: opacity * 0.3),
        accent.withValues(alpha: opacity * 0.1),
        Colors.transparent,
      ],
      stops: const [0.0, 0.3, 0.6, 1.0],
    );
  }

  static RadialGradient coverGlow(Color accent, {double radius = 0.8}) {
    return RadialGradient(
      center: Alignment.center,
      radius: radius,
      colors: [
        accent.withValues(alpha: 0.25),
        accent.withValues(alpha: 0.12),
        accent.withValues(alpha: 0.04),
        Colors.transparent,
      ],
      stops: const [0.0, 0.35, 0.7, 1.0],
    );
  }

  // ===========================================================================
  // GLASSMORPHISM TOKENS
  // ===========================================================================
  static const double glassOpacitySubtle = 0.06;
  static const double glassOpacityLight = 0.10;
  static const double glassOpacityMedium = 0.16;
  static const double glassOpacityStrong = 0.22;
  static const double glassOpacityOverlay = 0.35;

  static const double glassBorderSubtle = 0.04;
  static const double glassBorderDefault = 0.08;
  static const double glassBorderStrong = 0.14;

  static const double glassBlurSubtle = 8.0;
  static const double glassBlurDefault = 16.0;
  static const double glassBlurStrong = 24.0;
  static const double glassBlurOverlay = 32.0;

  static const double glassDimSubtle = 0.08;
  static const double glassDimDefault = 0.18;
  static const double glassDimStrong = 0.28;
  static const double glassDimOverlay = 0.45;

  // ===========================================================================
  // SPACING SYSTEM
  // ===========================================================================
  static const double spaceXxs = 2;
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 20;
  static const double spaceXxl = 24;
  static const double spaceXxxl = 32;
  static const double spaceHuge = 48;
  static const double spaceMassive = 64;

  // ===========================================================================
  // BORDER RADII
  // ===========================================================================
  static const double radiusXs = 6;
  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 18;
  static const double radiusXl = 22;
  static const double radiusXxl = 28;
  static const double radiusFull = 999;

  // ===========================================================================
  // SHADOWS
  // ===========================================================================
  static List<BoxShadow> shadowSubtle = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.15),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> shadowDefault = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.2),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.1),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];

  static List<BoxShadow> shadowElevated = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.3),
      blurRadius: 28,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.15),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> shadowPlayer = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.4),
      blurRadius: 40,
      offset: const Offset(0, -4),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.2),
      blurRadius: 12,
      offset: const Offset(0, -1),
    ),
  ];

  static List<BoxShadow> shadowCoverGlow(Color accent) {
    return [
      BoxShadow(
        color: accent.withValues(alpha: 0.25),
        blurRadius: 32,
        offset: const Offset(0, 8),
        spreadRadius: -4,
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.35),
        blurRadius: 24,
        offset: const Offset(0, 12),
      ),
    ];
  }

  // ===========================================================================
  // ANIMATION DURATIONS
  // ===========================================================================
  static const Duration animInstant = Duration(milliseconds: 80);
  static const Duration animFast = Duration(milliseconds: 160);
  static const Duration animDefault = Duration(milliseconds: 240);
  static const Duration animSlow = Duration(milliseconds: 360);
  static const Duration animSlowest = Duration(milliseconds: 500);
  static const Duration animAmbient = Duration(seconds: 8);

  // ===========================================================================
  // ANIMATION CURVES
  // ===========================================================================
  static const Curve curveStandard = Curves.easeOutCubic;
  static const Curve curveEmphasized = Curves.easeOutExpo;
  static const Curve curveSpring = Curves.elasticOut;
  static const Curve curveAmbient = Curves.linear;

  // ===========================================================================
  // TYPOGRAPHY SCALE
  // ===========================================================================
  static const TextStyle textDisplayLarge = TextStyle(
    fontSize: 56,
    fontWeight: FontWeight.w800,
    height: 1.1,
    letterSpacing: -1.5,
  );

  static const TextStyle textDisplayMedium = TextStyle(
    fontSize: 44,
    fontWeight: FontWeight.w700,
    height: 1.15,
    letterSpacing: -1.0,
  );

  static const TextStyle textDisplaySmall = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.5,
  );

  static const TextStyle textHeadlineLarge = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.3,
  );

  static const TextStyle textHeadlineMedium = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: -0.1,
  );

  static const TextStyle textHeadlineSmall = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.35,
  );

  static const TextStyle textTitleLarge = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static const TextStyle textTitleMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.45,
  );

  static const TextStyle textTitleSmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.5,
  );

  static const TextStyle textBodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const TextStyle textBodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const TextStyle textBodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const TextStyle textLabelLarge = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.4,
    letterSpacing: 0.1,
  );

  static const TextStyle textLabelMedium = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.4,
    letterSpacing: 0.2,
  );

  static const TextStyle textLabelSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.4,
    letterSpacing: 0.3,
  );

  // ===========================================================================
  // PLAYER SPECIFIC DIMENSIONS
  // ===========================================================================
  static const double miniPlayerHeight = 80;
  static const double miniPlayerHeightCollapsed = 64;
  static const double fullscreenArtworkSize = 320;
  static const double mobileArtworkSize = 280;

  // ===========================================================================
  // CAROUSEL DEPTH
  // ===========================================================================
  static const double carouselItemScale = 0.82;
  static const double carouselItemOpacity = 0.55;
  static const double carouselSpacing = 24;
  static const double carouselPerspective = 0.0015;
}

/// Extension for easy access to design tokens in widgets
extension DesignTokensExt on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;

  double get glassOpacitySubtle => DesignTokens.glassOpacitySubtle;
  double get glassOpacityLight => DesignTokens.glassOpacityLight;
  double get glassOpacityMedium => DesignTokens.glassOpacityMedium;
  double get glassOpacityStrong => DesignTokens.glassOpacityStrong;
  double get glassOpacityOverlay => DesignTokens.glassOpacityOverlay;

  double get glassBlurDefault => DesignTokens.glassBlurDefault;
  double get glassBlurStrong => DesignTokens.glassBlurStrong;

  double get sXxs => DesignTokens.spaceXxs;
  double get sXs => DesignTokens.spaceXs;
  double get sSm => DesignTokens.spaceSm;
  double get sMd => DesignTokens.spaceMd;
  double get sLg => DesignTokens.spaceLg;
  double get sXl => DesignTokens.spaceXl;
  double get sXxl => DesignTokens.spaceXxl;
  double get sXxxl => DesignTokens.spaceXxxl;

  double get rSm => DesignTokens.radiusSm;
  double get rMd => DesignTokens.radiusMd;
  double get rLg => DesignTokens.radiusLg;
  double get rXl => DesignTokens.radiusXl;
  double get rXxl => DesignTokens.radiusXxl;
  double get rFull => DesignTokens.radiusFull;

  List<BoxShadow> get shadowSubtle => DesignTokens.shadowSubtle;
  List<BoxShadow> get shadowDefault => DesignTokens.shadowDefault;
  List<BoxShadow> get shadowElevated => DesignTokens.shadowElevated;
  List<BoxShadow> get shadowPlayer => DesignTokens.shadowPlayer;

  Duration get animFast => DesignTokens.animFast;
  Duration get animDefault => DesignTokens.animDefault;
  Duration get animSlow => DesignTokens.animSlow;
  Curve get curveStandard => DesignTokens.curveStandard;
  Curve get curveEmphasized => DesignTokens.curveEmphasized;
}
