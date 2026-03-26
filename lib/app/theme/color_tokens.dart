import 'dart:ui';

/// Gloam color system — green-tinted neutrals, atmospheric dark palette.
///
/// All neutrals are shifted toward desaturated olive/sage. Darkness is
/// the native state; light emerges from it.
abstract final class GloamColors {
  // Backgrounds
  static const bg = Color(0xFF080F0A);
  static const bgSurface = Color(0xFF0D1610);
  static const bgElevated = Color(0xFF121E16);

  // Borders
  static const border = Color(0xFF1A2B1E);
  static const borderSubtle = Color(0xFF132019);

  // Text
  static const textPrimary = Color(0xFFC8DCCB);
  static const textSecondary = Color(0xFF6B8A70);
  static const textTertiary = Color(0xFF3D5C42);

  // Accent
  static const accent = Color(0xFF7DB88A);
  static const accentBright = Color(0xFFA3D4AB);
  static const accentDim = Color(0xFF3D7A4A);

  // Semantic
  static const danger = Color(0xFFC45C5C);
  static const warning = Color(0xFFC4A35C);
  static const info = Color(0xFF5C8AC4);
  static const online = Color(0xFF7DB88A);

  // Special
  static const overlay = Color(0xCC0D1610); // 80% opacity bg-surface
}
