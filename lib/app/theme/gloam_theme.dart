import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'color_tokens.dart';
import 'spacing.dart';

/// Builds the Gloam [ThemeData]. Dark-mode-first — this is the native state.
ThemeData buildGloamTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: GloamColors.bg,
    canvasColor: GloamColors.bgSurface,

    colorScheme: const ColorScheme.dark(
      surface: GloamColors.bg,
      onSurface: GloamColors.textPrimary,
      primary: GloamColors.accent,
      onPrimary: GloamColors.bg,
      secondary: GloamColors.accentDim,
      onSecondary: GloamColors.accentBright,
      error: GloamColors.danger,
      onError: GloamColors.textPrimary,
      outline: GloamColors.border,
      outlineVariant: GloamColors.borderSubtle,
      surfaceContainerHighest: GloamColors.bgElevated,
      surfaceContainerHigh: GloamColors.bgSurface,
    ),

    textTheme: TextTheme(
      displayLarge: GoogleFonts.spectral(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        height: 1.2,
        color: GloamColors.textPrimary,
      ),
      displayMedium: GoogleFonts.spectral(
        fontSize: 22,
        fontWeight: FontWeight.w300,
        fontStyle: FontStyle.italic,
        height: 1.25,
        color: GloamColors.accent,
      ),
      displaySmall: GoogleFonts.spectral(
        fontSize: 18,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: GloamColors.textPrimary,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: GloamColors.textPrimary,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: GloamColors.textPrimary,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: GloamColors.textSecondary,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: GloamColors.textPrimary,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: GloamColors.textPrimary,
      ),
      labelSmall: GoogleFonts.jetBrainsMono(
        fontSize: 10,
        fontWeight: FontWeight.w400,
        height: 1.3,
        letterSpacing: 1.2,
        color: GloamColors.textTertiary,
      ),
    ),

    dividerTheme: const DividerThemeData(
      color: GloamColors.border,
      thickness: 1,
      space: 0,
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: GloamColors.bg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
        borderSide: const BorderSide(color: GloamColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
        borderSide: const BorderSide(color: GloamColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
        borderSide: const BorderSide(color: GloamColors.accent),
      ),
      hintStyle: GoogleFonts.inter(
        fontSize: 14,
        color: GloamColors.textTertiary,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: GloamColors.accent,
        foregroundColor: GloamColors.bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: GoogleFonts.jetBrainsMono(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: GloamColors.textSecondary,
        side: const BorderSide(color: GloamColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: GoogleFonts.jetBrainsMono(
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      ),
    ),

    iconTheme: const IconThemeData(
      color: GloamColors.textSecondary,
      size: 20,
    ),

    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(GloamColors.borderSubtle),
      radius: const Radius.circular(2),
      thickness: WidgetStateProperty.all(4),
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: GloamColors.bgElevated,
        borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
        border: Border.all(color: GloamColors.border),
      ),
      textStyle: GoogleFonts.inter(
        fontSize: 12,
        color: GloamColors.textPrimary,
      ),
    ),
  );
}
