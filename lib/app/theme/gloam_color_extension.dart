import 'dart:ui';

import 'package:flutter/material.dart';

/// Gloam's custom color tokens as a [ThemeExtension].
///
/// Provides all 16 design-system color tokens with smooth `lerp`
/// transitions when switching between theme variants.
class GloamColorExtension extends ThemeExtension<GloamColorExtension> {
  const GloamColorExtension({
    required this.bg,
    required this.bgSurface,
    required this.bgElevated,
    required this.border,
    required this.borderSubtle,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentBright,
    required this.accentDim,
    required this.danger,
    required this.warning,
    required this.info,
    required this.online,
    required this.overlay,
  });

  final Color bg;
  final Color bgSurface;
  final Color bgElevated;
  final Color border;
  final Color borderSubtle;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color accent;
  final Color accentBright;
  final Color accentDim;
  final Color danger;
  final Color warning;
  final Color info;
  final Color online;
  final Color overlay;

  @override
  GloamColorExtension copyWith({
    Color? bg,
    Color? bgSurface,
    Color? bgElevated,
    Color? border,
    Color? borderSubtle,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? accentBright,
    Color? accentDim,
    Color? danger,
    Color? warning,
    Color? info,
    Color? online,
    Color? overlay,
  }) {
    return GloamColorExtension(
      bg: bg ?? this.bg,
      bgSurface: bgSurface ?? this.bgSurface,
      bgElevated: bgElevated ?? this.bgElevated,
      border: border ?? this.border,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accent: accent ?? this.accent,
      accentBright: accentBright ?? this.accentBright,
      accentDim: accentDim ?? this.accentDim,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
      info: info ?? this.info,
      online: online ?? this.online,
      overlay: overlay ?? this.overlay,
    );
  }

  @override
  GloamColorExtension lerp(GloamColorExtension? other, double t) {
    if (other is! GloamColorExtension) return this;
    return GloamColorExtension(
      bg: Color.lerp(bg, other.bg, t)!,
      bgSurface: Color.lerp(bgSurface, other.bgSurface, t)!,
      bgElevated: Color.lerp(bgElevated, other.bgElevated, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentBright: Color.lerp(accentBright, other.accentBright, t)!,
      accentDim: Color.lerp(accentDim, other.accentDim, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
      online: Color.lerp(online, other.online, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
    );
  }
}
