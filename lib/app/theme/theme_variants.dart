import 'dart:ui';

import 'gloam_color_extension.dart';

/// The twelve visual theme variants.
enum ThemeVariant {
  obsidian,
  gloamDark,
  midnight,
  ember,
  moss,
  dusk,
  storm,
  copper,
  dawn,
  frost,
  sand,
  slate,
}

/// Whether a theme variant uses light mode (light text on dark bg = false).
bool isLightTheme(ThemeVariant variant) {
  return variant == ThemeVariant.dawn ||
      variant == ThemeVariant.frost ||
      variant == ThemeVariant.sand ||
      variant == ThemeVariant.slate;
}

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

/// Shared semantic colors across all themes.
const _danger = Color(0xFFC45C5C);
const _warning = Color(0xFFC4A35C);
const _info = Color(0xFF5C8AC4);

/// Resolve the full color extension from a variant + accent combination.
GloamColorExtension resolveColors(ThemeVariant variant, AccentColor accent) {
  return switch (variant) {
    // ── Dark themes ──

    // Obsidian: true OLED black — maximum contrast, subtle cool purple tint
    ThemeVariant.obsidian => GloamColorExtension(
        bg: const Color(0xFF000000),
        bgSurface: const Color(0xFF06060A),
        bgElevated: const Color(0xFF0E0E14),
        border: const Color(0xFF1C1C26),
        borderSubtle: const Color(0xFF12121A),
        textPrimary: const Color(0xFFE0E0EA),
        textSecondary: const Color(0xFF7A7A8C),
        textTertiary: const Color(0xFF46464E),
        accent: accent.base,
        accentBright: accent.bright,
        accentDim: accent.dim,
        danger: _danger,
        warning: _warning,
        info: _info,
        online: accent.base,
        overlay: const Color(0xCC000000),
      ),

    // Gloam Dark: our signature — dark with green undertones (UNCHANGED)
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
        danger: _danger,
        warning: _warning,
        info: _info,
        online: accent.base,
        overlay: const Color(0xCC0D1610),
      ),

    // Midnight: deep navy blue — clearly blue, not just dark
    ThemeVariant.midnight => GloamColorExtension(
        bg: const Color(0xFF08101E),
        bgSurface: const Color(0xFF0E1828),
        bgElevated: const Color(0xFF162238),
        border: const Color(0xFF223050),
        borderSubtle: const Color(0xFF1A2840),
        textPrimary: const Color(0xFFD0D8E8),
        textSecondary: const Color(0xFF6880A8),
        textTertiary: const Color(0xFF3E5078),
        accent: accent.base,
        accentBright: accent.bright,
        accentDim: accent.dim,
        danger: _danger,
        warning: _warning,
        info: _info,
        online: accent.base,
        overlay: const Color(0xCC0E1828),
      ),

    // Ember: warm dark brown/red — cozy fireplace glow
    ThemeVariant.ember => GloamColorExtension(
        bg: const Color(0xFF140C08),
        bgSurface: const Color(0xFF1E1410),
        bgElevated: const Color(0xFF2C1E18),
        border: const Color(0xFF3E2C22),
        borderSubtle: const Color(0xFF30221A),
        textPrimary: const Color(0xFFE0D0C4),
        textSecondary: const Color(0xFF9A7868),
        textTertiary: const Color(0xFF6A5040),
        accent: accent.base,
        accentBright: accent.bright,
        accentDim: accent.dim,
        danger: _danger,
        warning: _warning,
        info: _info,
        online: accent.base,
        overlay: const Color(0xCC1E1410),
      ),

    // Moss: saturated deep forest green — clearly green
    ThemeVariant.moss => GloamColorExtension(
        bg: const Color(0xFF081408),
        bgSurface: const Color(0xFF0E2010),
        bgElevated: const Color(0xFF162E18),
        border: const Color(0xFF224022),
        borderSubtle: const Color(0xFF1A3018),
        textPrimary: const Color(0xFFC4E0C4),
        textSecondary: const Color(0xFF68A068),
        textTertiary: const Color(0xFF3E6A3E),
        accent: accent.base,
        accentBright: accent.bright,
        accentDim: accent.dim,
        danger: _danger,
        warning: _warning,
        info: _info,
        online: accent.base,
        overlay: const Color(0xCC0E2010),
      ),

    // ── Medium-dark themes ──

    // Dusk: deep saturated purple — clearly purple, evening sky
    ThemeVariant.dusk => GloamColorExtension(
        bg: const Color(0xFF120E20),
        bgSurface: const Color(0xFF1A1430),
        bgElevated: const Color(0xFF241E40),
        border: const Color(0xFF342E54),
        borderSubtle: const Color(0xFF2A2448),
        textPrimary: const Color(0xFFD4CCE8),
        textSecondary: const Color(0xFF8878B0),
        textTertiary: const Color(0xFF5A4E7A),
        accent: accent.base,
        accentBright: accent.bright,
        accentDim: accent.dim,
        danger: _danger,
        warning: _warning,
        info: _info,
        online: accent.base,
        overlay: const Color(0xCC1A1430),
      ),

    // Storm: steel blue-gray — overcast sky, noticeably lighter
    ThemeVariant.storm => GloamColorExtension(
        bg: const Color(0xFF141C24),
        bgSurface: const Color(0xFF1C2630),
        bgElevated: const Color(0xFF26323E),
        border: const Color(0xFF344050),
        borderSubtle: const Color(0xFF2C3844),
        textPrimary: const Color(0xFFD4DCE4),
        textSecondary: const Color(0xFF7890A4),
        textTertiary: const Color(0xFF506474),
        accent: accent.base,
        accentBright: accent.bright,
        accentDim: accent.dim,
        danger: _danger,
        warning: _warning,
        info: _info,
        online: accent.base,
        overlay: const Color(0xCC1C2630),
      ),

    // Copper: rich warm leather brown — clearly warm, medium brightness
    ThemeVariant.copper => GloamColorExtension(
        bg: const Color(0xFF1A1208),
        bgSurface: const Color(0xFF261C10),
        bgElevated: const Color(0xFF34281C),
        border: const Color(0xFF483A2A),
        borderSubtle: const Color(0xFF3C3020),
        textPrimary: const Color(0xFFE4D8C8),
        textSecondary: const Color(0xFFA08868),
        textTertiary: const Color(0xFF6E5C44),
        accent: accent.base,
        accentBright: accent.bright,
        accentDim: accent.dim,
        danger: _danger,
        warning: _warning,
        info: _info,
        online: accent.base,
        overlay: const Color(0xCC261C10),
      ),

    // ── Light themes ──

    // Dawn: warm off-white with green tint (UNCHANGED)
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
        danger: _danger,
        warning: _warning,
        info: _info,
        online: accent.base,
        overlay: const Color(0xCCE8EDE9),
      ),

    // Frost: icy cool blue-white — crisp winter morning
    ThemeVariant.frost => GloamColorExtension(
        bg: const Color(0xFFE8F0FA),
        bgSurface: const Color(0xFFD8E4F0),
        bgElevated: const Color(0xFFF4F8FF),
        border: const Color(0xFFB0C4D8),
        borderSubtle: const Color(0xFFC8D8E8),
        textPrimary: const Color(0xFF142030),
        textSecondary: const Color(0xFF4A6080),
        textTertiary: const Color(0xFF8098B0),
        accent: accent.base,
        accentBright: accent.bright,
        accentDim: accent.dim,
        danger: _danger,
        warning: _warning,
        info: _info,
        online: accent.base,
        overlay: const Color(0xCCD8E4F0),
      ),

    // Sand: warm golden beige — desert/parchment
    ThemeVariant.sand => GloamColorExtension(
        bg: const Color(0xFFF0E4D0),
        bgSurface: const Color(0xFFE4D8C0),
        bgElevated: const Color(0xFFFAF4EA),
        border: const Color(0xFFC8B898),
        borderSubtle: const Color(0xFFD8CCAE),
        textPrimary: const Color(0xFF2A2010),
        textSecondary: const Color(0xFF6A5838),
        textTertiary: const Color(0xFF9A8868),
        accent: accent.base,
        accentBright: accent.bright,
        accentDim: accent.dim,
        danger: _danger,
        warning: _warning,
        info: _info,
        online: accent.base,
        overlay: const Color(0xCCE4D8C0),
      ),

    // Slate: cool neutral gray — clean, no color tint
    ThemeVariant.slate => GloamColorExtension(
        bg: const Color(0xFFE0E0E4),
        bgSurface: const Color(0xFFD0D0D6),
        bgElevated: const Color(0xFFEEEEF0),
        border: const Color(0xFFB0B0B8),
        borderSubtle: const Color(0xFFC4C4CA),
        textPrimary: const Color(0xFF1A1A20),
        textSecondary: const Color(0xFF505058),
        textTertiary: const Color(0xFF88888E),
        accent: accent.base,
        accentBright: accent.bright,
        accentDim: accent.dim,
        danger: _danger,
        warning: _warning,
        info: _info,
        online: accent.base,
        overlay: const Color(0xCCD0D0D6),
      ),
  };
}
