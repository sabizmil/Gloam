import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'spacing.dart';
import 'theme_preferences.dart';
import 'theme_variants.dart';

/// Builds the Gloam [ThemeData] from user preferences.
/// When [prefs] is null, defaults to gloam dark / green / comfortable / 1.0x.
ThemeData buildGloamTheme({ThemePreferences? prefs}) {
  final p = prefs ?? const ThemePreferences();
  final colors = resolveColors(p.variant, p.accentColor);
  final isDark = !isLightTheme(p.variant);

  final visualDensity = switch (p.density) {
    DensityMode.compact => VisualDensity.compact,
    DensityMode.comfortable => VisualDensity.comfortable,
    DensityMode.spacious => const VisualDensity(horizontal: 2, vertical: 2),
  };

  final colorScheme = isDark
      ? ColorScheme.dark(
          surface: colors.bg,
          onSurface: colors.textPrimary,
          primary: colors.accent,
          onPrimary: colors.bg,
          secondary: colors.accentDim,
          onSecondary: colors.accentBright,
          error: colors.danger,
          onError: colors.textPrimary,
          outline: colors.border,
          outlineVariant: colors.borderSubtle,
          surfaceContainerHighest: colors.bgElevated,
          surfaceContainerHigh: colors.bgSurface,
        )
      : ColorScheme.light(
          surface: colors.bg,
          onSurface: colors.textPrimary,
          primary: colors.accent,
          onPrimary: colors.bg,
          secondary: colors.accentDim,
          onSecondary: colors.accentBright,
          error: colors.danger,
          onError: colors.textPrimary,
          outline: colors.border,
          outlineVariant: colors.borderSubtle,
          surfaceContainerHighest: colors.bgElevated,
          surfaceContainerHigh: colors.bgSurface,
        );

  return ThemeData(
    brightness: isDark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: colors.bg,
    canvasColor: colors.bgSurface,
    colorScheme: colorScheme,
    visualDensity: visualDensity,

    extensions: [colors],

    textTheme: TextTheme(
      displayLarge: GoogleFonts.spectral(
        fontSize: 28, fontWeight: FontWeight.w600, height: 1.2,
        color: colors.textPrimary,
      ),
      displayMedium: GoogleFonts.spectral(
        fontSize: 22, fontWeight: FontWeight.w300, fontStyle: FontStyle.italic,
        height: 1.25, color: colors.accent,
      ),
      displaySmall: GoogleFonts.spectral(
        fontSize: 18, fontWeight: FontWeight.w500, height: 1.3,
        color: colors.textPrimary,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 15, fontWeight: FontWeight.w400, height: 1.5,
        color: colors.textPrimary,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 13, fontWeight: FontWeight.w400, height: 1.45,
        color: colors.textPrimary,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 12, fontWeight: FontWeight.w400, height: 1.4,
        color: colors.textSecondary,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 15, fontWeight: FontWeight.w600, height: 1.3,
        color: colors.textPrimary,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 13, fontWeight: FontWeight.w500, height: 1.3,
        color: colors.textPrimary,
      ),
      labelSmall: GoogleFonts.jetBrainsMono(
        fontSize: 10, fontWeight: FontWeight.w400, height: 1.3,
        letterSpacing: 1.2, color: colors.textTertiary,
      ),
    ),

    dividerTheme: DividerThemeData(
      color: colors.border, thickness: 1, space: 0,
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.bg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
        borderSide: BorderSide(color: colors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
        borderSide: BorderSide(color: colors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
        borderSide: BorderSide(color: colors.accent),
      ),
      hintStyle: GoogleFonts.inter(fontSize: 14, color: colors.textTertiary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.accent,
        foregroundColor: colors.bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: GoogleFonts.jetBrainsMono(
          fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5,
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.textSecondary,
        side: BorderSide(color: colors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: GoogleFonts.jetBrainsMono(
          fontSize: 12, fontWeight: FontWeight.w400,
        ),
      ),
    ),

    iconTheme: IconThemeData(color: colors.textSecondary, size: 20),

    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(colors.borderSubtle),
      radius: const Radius.circular(2),
      thickness: WidgetStateProperty.all(4),
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.bgElevated,
        borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
        border: Border.all(color: colors.border),
      ),
      textStyle: GoogleFonts.inter(fontSize: 12, color: colors.textPrimary),
    ),
  );
}
