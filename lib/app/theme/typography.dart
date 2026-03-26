import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'color_tokens.dart';

/// Gloam type system — three font families, each with a distinct role.
///
/// - **Spectral**: Display headings, the Gloam wordmark, room names. Serif, literary.
/// - **Inter**: Message text, UI labels, body copy. Clean, readable.
/// - **JetBrains Mono**: Code, metadata, timestamps, section headers. Terminal feel.
abstract final class GloamTypography {
  // Display — Spectral (serif, atmospheric)
  static TextStyle get displayLarge => GoogleFonts.spectral(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: -0.5,
        color: GloamColors.textPrimary,
      );

  static TextStyle get displayMedium => GoogleFonts.spectral(
        fontSize: 22,
        fontWeight: FontWeight.w300,
        fontStyle: FontStyle.italic,
        height: 1.25,
        color: GloamColors.accent,
      );

  static TextStyle get displaySmall => GoogleFonts.spectral(
        fontSize: 18,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: GloamColors.textPrimary,
      );

  // Body — Inter (clean, readable)
  static TextStyle get bodyLarge => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: GloamColors.textPrimary,
      );

  static TextStyle get bodyMedium => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: GloamColors.textPrimary,
      );

  static TextStyle get bodySmall => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: GloamColors.textSecondary,
      );

  static TextStyle get labelLarge => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: GloamColors.textPrimary,
      );

  static TextStyle get labelMedium => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: GloamColors.textPrimary,
      );

  // Code / Metadata — JetBrains Mono (terminal feel)
  static TextStyle get mono => GoogleFonts.jetBrainsMono(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: GloamColors.textPrimary,
      );

  static TextStyle get monoSmall => GoogleFonts.jetBrainsMono(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        height: 1.3,
        color: GloamColors.textSecondary,
      );

  /// The `// SECTION HEADER` pattern — monospace, tertiary, letterspaced.
  static TextStyle get sectionHeader => GoogleFonts.jetBrainsMono(
        fontSize: 10,
        fontWeight: FontWeight.w400,
        height: 1.3,
        letterSpacing: 1.2,
        color: GloamColors.textTertiary,
      );

  /// Keyboard shortcut badge text.
  static TextStyle get kbd => GoogleFonts.jetBrainsMono(
        fontSize: 10,
        fontWeight: FontWeight.w400,
        color: GloamColors.textTertiary,
      );
}
