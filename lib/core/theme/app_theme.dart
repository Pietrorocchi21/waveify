import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// The design tokens of the app, mirroring \src/app/globals.css\.
class AppColors {
  AppColors._();

  // --- Light (kept for compatibility) ---
  static const Color lightCanvas = Color(0xFFE4E4E7);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightPrimary = Color(0xFFF5F5F7);
  static const Color lightElevated = Color(0xFFE6E6EB);
  static const Color lightPanel = Color(0xFFDEDEE3);
  static const Color lightOverlay = Color(0xF5F5F5F7);
  static const Color lightToolbox = Color(0x0A000000);
  static const Color lightToolboxActive = Color(0x14000000);
  static const Color lightBorderPrimary = Color(0xFFE4E4E7);
  static const Color lightBorderSecondary = Color(0xFFD4D4D8);
  static const Color lightBorderTertiary = Color(0xFFA1A1AA);
  static const Color lightTextPrimary = Color(0xFF18181B);
  static const Color lightTextSecondary = Color(0xA618181B);
  static const Color lightTextTertiary = Color(0x7318181B);
  static const Color lightButtonBg = Color(0xFF18181B);
  static const Color lightButtonText = Color(0xFFFFFFFF);

  // --- Dark - WAVEIFY nocturnal palette ---
  static const Color darkCanvas = DesignTokens.baseCanvas; // Near black
  static const Color darkSurface = DesignTokens.baseSurface; // Charcoal
  static const Color darkPrimary = DesignTokens.baseSurface; // Primary bg
  static const Color darkElevated = DesignTokens.baseElevated; // Elevated
  static const Color darkPanel = DesignTokens.basePanel; // Panel/card
  static const Color darkOverlay = DesignTokens.baseOverlay; // Modal overlay
  static const Color darkToolbox = Color(0x0AFFFFFF);
  static const Color darkToolboxActive = Color(0x17FFFFFF);
  static const Color darkBorderPrimary =
      DesignTokens.baseBorderPrimary; // Subtle
  static const Color darkBorderSecondary =
      DesignTokens.baseBorderSecondary; // Medium
  static const Color darkBorderTertiary =
      DesignTokens.baseBorderTertiary; // Strong
  static const Color darkTextPrimary = DesignTokens.baseTextPrimary;
  static const Color darkTextSecondary = DesignTokens.baseTextSecondary;
  static const Color darkTextTertiary = DesignTokens.baseTextTertiary;
  static const Color darkButtonBg = Color(0xFFF4F4F4);
  static const Color darkButtonText = Color(0xFF000000);

  // --- Accents ---
  static const Color lightAccent = Color(0xFF9BBEFA);
  static const Color darkAccent = Color(0xFF9BBEFA);
  static const Color lightAccentSecondary = Color(0xFFFF5C5C);
  static const Color darkAccentSecondary = Color(0xFFC3B5F6);
  static const Color lightAccentWarning = Color(0xFFD97706);
  static const Color darkAccentWarning = Color(0xFFFFDE9E);
}

/// The 13 branding variants of the app.
enum AccentVariant {
  defaultVariant('default', 'logo-default.svg', Color(0xFF9BBEFA)),
  spotify('spotify', 'logo-spotify.svg', Color(0xFF1DB954)),
  discord('discord', 'logo-discord.svg', Color(0xFF5865F2)),
  telegram('telegram', 'logo-telegram.svg', Color(0xFF26A5E4)),
  aurora('aurora', 'logo-aurora.svg', Color(0xFF22D3EE)),
  sunset('sunset', 'logo-sunset.svg', Color(0xFFFB923C)),
  ocean('ocean', 'logo-ocean.svg', Color(0xFF2563EB)),
  forest('forest', 'logo-forest.svg', Color(0xFF059669)),
  berry('berry', 'logo-berry.svg', Color(0xFF7C3AED)),
  carbon('carbon', 'logo-carbon.svg', Color(0xFF52525B)),
  pixel('pixel', 'logo-pixel.svg', Color(0xFF22C55E)),
  scanlines('scanlines', 'logo-scanlines.svg', Color(0xFF38BDF8)),
  vhs('vhs', 'logo-vhs.svg', Color(0xFF00FFFF));

  const AccentVariant(this.id, this.logoAsset, this.accentColor);

  final String id;
  final String logoAsset;
  final Color accentColor;

  static AccentVariant fromId(String? id) {
    return AccentVariant.values.firstWhere(
      (v) => v.id == id,
      orElse: () => AccentVariant.defaultVariant,
    );
  }
}

/// Corner radii, mirroring the \--radius-*\ custom properties.
class AppRadii {
  AppRadii._();

  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 10;
  static const double xl = 12;
  static const double xxl = 14;
  static const double xxxl = 16;
  static const double full = 999;
}

/// Builds the Material theme for the app.
class AppTheme {
  AppTheme._();

  static ThemeData light(AccentVariant accent) {
    return _build(
      brightness: Brightness.light,
      canvas: AppColors.lightCanvas,
      surface: AppColors.lightSurface,
      primaryBg: AppColors.lightPrimary,
      elevated: AppColors.lightElevated,
      panel: AppColors.lightPanel,
      overlay: AppColors.lightOverlay,
      toolbox: AppColors.lightToolbox,
      toolboxActive: AppColors.lightToolboxActive,
      borderPrimary: AppColors.lightBorderPrimary,
      borderSecondary: AppColors.lightBorderSecondary,
      borderTertiary: AppColors.lightBorderTertiary,
      textPrimary: AppColors.lightTextPrimary,
      textSecondary: AppColors.lightTextSecondary,
      textTertiary: AppColors.lightTextTertiary,
      accent: accent.accentColor,
      accentSecondary: AppColors.lightAccentSecondary,
      warning: AppColors.lightAccentWarning,
      buttonBg: AppColors.lightButtonBg,
      buttonText: AppColors.lightButtonText,
    );
  }

  static ThemeData dark(AccentVariant accent) {
    return _build(
      brightness: Brightness.dark,
      canvas: AppColors.darkCanvas,
      surface: AppColors.darkSurface,
      primaryBg: AppColors.darkPrimary,
      elevated: AppColors.darkElevated,
      panel: AppColors.darkPanel,
      overlay: AppColors.darkOverlay,
      toolbox: AppColors.darkToolbox,
      toolboxActive: AppColors.darkToolboxActive,
      borderPrimary: AppColors.darkBorderPrimary,
      borderSecondary: AppColors.darkBorderSecondary,
      borderTertiary: AppColors.darkBorderTertiary,
      textPrimary: AppColors.darkTextPrimary,
      textSecondary: AppColors.darkTextSecondary,
      textTertiary: AppColors.darkTextTertiary,
      accent: accent.accentColor,
      accentSecondary: AppColors.darkAccentSecondary,
      warning: AppColors.darkAccentWarning,
      buttonBg: AppColors.darkButtonBg,
      buttonText: AppColors.darkButtonText,
    );
  }

  static ThemeData _build({
    required Brightness brightness,
    required Color canvas,
    required Color surface,
    required Color primaryBg,
    required Color elevated,
    required Color panel,
    required Color overlay,
    required Color toolbox,
    required Color toolboxActive,
    required Color borderPrimary,
    required Color borderSecondary,
    required Color borderTertiary,
    required Color textPrimary,
    required Color textSecondary,
    required Color textTertiary,
    required Color accent,
    required Color accentSecondary,
    required Color warning,
    required Color buttonBg,
    required Color buttonText,
  }) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary:
          ThemeData.estimateBrightnessForColor(accent) == Brightness.light
          ? const Color(0xFF101521)
          : Colors.white,
      secondary: accentSecondary,
      onSecondary: buttonText,
      error: const Color(0xFFEF4444),
      onError: Colors.white,
      surface: surface,
      onSurfaceVariant: textSecondary,
      surfaceContainerLow: primaryBg,
      surfaceContainer: elevated,
      surfaceContainerHigh: panel,
      onSurface: textPrimary,
      surfaceContainerHighest: panel,
      outline: borderSecondary,
      outlineVariant: borderPrimary,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      splashFactory: InkSparkle.splashFactory,
    );

    // Custom text theme with WAVEIFY type hierarchy
    final textTheme = base.textTheme
        .apply(bodyColor: textPrimary, displayColor: textPrimary)
        .copyWith(
          displayLarge: DesignTokens.textDisplayLarge.copyWith(
            color: textPrimary,
          ),
          displayMedium: DesignTokens.textDisplayMedium.copyWith(
            color: textPrimary,
          ),
          displaySmall: DesignTokens.textDisplaySmall.copyWith(
            color: textPrimary,
          ),
          headlineLarge: DesignTokens.textHeadlineLarge.copyWith(
            color: textPrimary,
          ),
          headlineMedium: DesignTokens.textHeadlineMedium.copyWith(
            color: textPrimary,
          ),
          headlineSmall: DesignTokens.textHeadlineSmall.copyWith(
            color: textPrimary,
          ),
          titleLarge: DesignTokens.textTitleLarge.copyWith(color: textPrimary),
          titleMedium: DesignTokens.textTitleMedium.copyWith(
            color: textPrimary,
          ),
          titleSmall: DesignTokens.textTitleSmall.copyWith(color: textPrimary),
          bodyLarge: DesignTokens.textBodyLarge.copyWith(color: textPrimary),
          bodyMedium: DesignTokens.textBodyMedium.copyWith(
            color: textSecondary,
          ),
          bodySmall: DesignTokens.textBodySmall.copyWith(color: textTertiary),
          labelLarge: DesignTokens.textLabelLarge.copyWith(color: textPrimary),
          labelMedium: DesignTokens.textLabelMedium.copyWith(
            color: textSecondary,
          ),
          labelSmall: DesignTokens.textLabelSmall.copyWith(color: textTertiary),
        );

    return base.copyWith(
      textTheme: textTheme.apply(fontFamily: 'Roboto'),
      dividerColor: borderPrimary,
      iconTheme: IconThemeData(color: textSecondary),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleMedium?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: textSecondary,
        textColor: textPrimary,
        selectedColor: accent,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceLg,
          vertical: DesignTokens.spaceXs,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: elevated.withValues(alpha: 0.5),
        hintStyle: TextStyle(color: textTertiary),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceMd,
          vertical: DesignTokens.spaceMd,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          borderSide: BorderSide(color: borderSecondary),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          borderSide: BorderSide(color: borderSecondary),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: colorScheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceXl,
            vertical: DesignTokens.spaceMd,
          ),
          textStyle: DesignTokens.textLabelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceMd,
            vertical: DesignTokens.spaceSm,
          ),
          textStyle: DesignTokens.textLabelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: BorderSide(color: borderSecondary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceLg,
            vertical: DesignTokens.spaceMd,
          ),
          textStyle: DesignTokens.textLabelLarge,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: toolboxActive,
        thumbColor: accent,
        overlayColor: accent.withValues(alpha: 0.16),
        trackHeight: 4,
        trackShape: const RoundedRectSliderTrackShape(),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: elevated,
        side: BorderSide(color: borderPrimary),
        labelStyle: TextStyle(color: textSecondary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceMd,
          vertical: DesignTokens.spaceXs,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusXxl),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(DesignTokens.radiusXxl),
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: accent.withValues(alpha: 0.12),
        selectedIconTheme: IconThemeData(color: accent),
        unselectedIconTheme: IconThemeData(color: textTertiary),
        selectedLabelTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
        unselectedLabelTextStyle: TextStyle(color: textTertiary, fontSize: 11),
        labelType: NavigationRailLabelType.all,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: accent.withValues(alpha: 0.12),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              color: textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            );
          }
          return TextStyle(color: textTertiary, fontSize: 11);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: accent, size: 24);
          }
          return IconThemeData(color: textTertiary, size: 24);
        }),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: toolboxActive,
        circularTrackColor: toolboxActive,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: textPrimary,
        unselectedLabelColor: textTertiary,
        indicatorColor: accent,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: DesignTokens.textLabelLarge,
        unselectedLabelStyle: DesignTokens.textLabelLarge,
        dividerColor: Colors.transparent,
      ),
    );
  }
}

/// Extension giving access to the semantic colours of the current theme.
extension ThemeTokens on ThemeData {
  Color get canvas => scaffoldBackgroundColor;

  Color get toolbox => brightness == Brightness.dark
      ? AppColors.darkToolbox
      : AppColors.lightToolbox;

  Color get toolboxActive => brightness == Brightness.dark
      ? AppColors.darkToolboxActive
      : AppColors.lightToolboxActive;

  Color get borderTertiary => brightness == Brightness.dark
      ? AppColors.darkBorderTertiary
      : AppColors.lightBorderTertiary;

  Color get textSecondary => brightness == Brightness.dark
      ? AppColors.darkTextSecondary
      : AppColors.lightTextSecondary;

  Color get textTertiary => brightness == Brightness.dark
      ? AppColors.darkTextTertiary
      : AppColors.lightTextTertiary;

  Color get warning => brightness == Brightness.dark
      ? AppColors.darkAccentWarning
      : AppColors.lightAccentWarning;

  // Glass-aware surface colors
  Color get glassSurface => brightness == Brightness.dark
      ? AppColors.darkSurface.withValues(alpha: DesignTokens.glassOpacityLight)
      : AppColors.lightSurface.withValues(
          alpha: DesignTokens.glassOpacityLight,
        );

  Color get glassSurfaceStrong => brightness == Brightness.dark
      ? AppColors.darkSurface.withValues(alpha: DesignTokens.glassOpacityStrong)
      : AppColors.lightSurface.withValues(
          alpha: DesignTokens.glassOpacityStrong,
        );
}
