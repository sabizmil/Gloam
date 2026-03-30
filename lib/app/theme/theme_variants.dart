import 'dart:ui';

import 'gloam_color_extension.dart';

/// The three visual theme variants.
enum ThemeVariant { gloamDark, midnight, dawn }

/// The six accent color options.
enum AccentColor {
  green(Color(0xFF7DB88A), Color(0xFFA3D4AB), Color(0xFF3D7A4A)),
  blue(Color(0xFF5C8AC4), Color(0xFF89B0DB), Color(0xFF3A5F8A)),
  pink(Color(0xFFC45C8A), Color(0xFFDB89B0), Color(0xFF8A3A5F)),
  gold(Color(0xFFC4A35C), Color(0xFFDBC489), Color(0xFF8A7A3A)),
  purple(Color(0xFF8A5CC4), Color(0xFFB089DB), Color(0xFF5F3A8A)),
  teal(Color(0xFF5CC4C4), Color(0xFF89DBDB), Color(0xFF3A8A8A));

  const AccentColor(this.base, this.bright, this.dim);
  final Color base;
  final Color bright;
  final Color dim;
}

/// UI density modes.
enum DensityMode { compact, comfortable, spacious }

/// Resolve the full color extension from a variant + accent combination.
GloamColorExtension resolveColors(ThemeVariant variant, AccentColor accent) {
  return switch (variant) {
    ThemeVariant.gloamDark => GloamColorExtension(
        bg: const Color(0xFF080F0A),
        bgSurface: const Color(0xFF0D1610),
        bgElevated: const Color(0xFF121E16),
        border: const Color(0xFF1A2B1E),
        borderSubtle: const Color(0xFF132019),
        textPrimary: const Color(0xFFC8DCCB),
        textSecondary: const Color(0xFF6B8A70),
        textTertiary: const Color(0xFF3D5C42),
        accent: accent.base,
        accentBright: accent.bright,
        accentDim: accent.dim,
        danger: const Color(0xFFC45C5C),
        warning: const Color(0xFFC4A35C),
        info: const Color(0xFF5C8AC4),
        online: accent.base,
        overlay: const Color(0xCC0D1610),
      ),
    ThemeVariant.midnight => GloamColorExtension(
        bg: const Color(0xFF0A0F14),
        bgSurface: const Color(0xFF0F1520),
        bgElevated: const Color(0xFF152030),
        border: const Color(0xFF1A2540),
        borderSubtle: const Color(0xFF121D35),
        textPrimary: const Color(0xFFC8D4E0),
        textSecondary: const Color(0xFF6B7D9A),
        textTertiary: const Color(0xFF3D4F6A),
        accent: accent.base,
        accentBright: accent.bright,
        accentDim: accent.dim,
        danger: const Color(0xFFC45C5C),
        warning: const Color(0xFFC4A35C),
        info: const Color(0xFF5C8AC4),
        online: accent.base,
        overlay: const Color(0xCC0F1520),
      ),
    ThemeVariant.dawn => GloamColorExtension(
        bg: const Color(0xFFF5F5F0),
        bgSurface: const Color(0xFFE8EDE9),
        bgElevated: const Color(0xFFFFFFFF),
        border: const Color(0xFFC8D4CA),
        borderSubtle: const Color(0xFFDCE4DD),
        textPrimary: const Color(0xFF1A2B1E),
        textSecondary: const Color(0xFF5A7A5F),
        textTertiary: const Color(0xFF8FA894),
        accent: accent.base,
        accentBright: accent.bright,
        accentDim: accent.dim,
        danger: const Color(0xFFC45C5C),
        warning: const Color(0xFFC4A35C),
        info: const Color(0xFF5C8AC4),
        online: accent.base,
        overlay: const Color(0xCCE8EDE9),
      ),
  };
}
