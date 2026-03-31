import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/theme_preferences.dart';
import '../../../../app/theme/theme_variants.dart';
import '../widgets/settings_tile.dart';

/// Theme display names and preview bg colors for each variant.
const _themeInfo = <ThemeVariant, (String, Color)>{
  ThemeVariant.gloamDark: ('gloam dark', Color(0xFF080F0A)),
  ThemeVariant.midnight: ('midnight', Color(0xFF08101E)),
  ThemeVariant.ember: ('ember', Color(0xFF140C08)),
  ThemeVariant.slate: ('slate', Color(0xFFE0E0E4)),
  ThemeVariant.obsidian: ('obsidian', Color(0xFF000000)),
  ThemeVariant.moss: ('moss', Color(0xFF081408)),
  ThemeVariant.dusk: ('dusk', Color(0xFF120E20)),
  ThemeVariant.storm: ('storm', Color(0xFF141C24)),
  ThemeVariant.copper: ('copper', Color(0xFF1A1208)),
  ThemeVariant.dawn: ('dawn', Color(0xFFF5F5F0)),
  ThemeVariant.frost: ('frost', Color(0xFFE8F0FA)),
  ThemeVariant.sand: ('sand', Color(0xFFF0E4D0)),
};

class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(themePreferencesProvider);
    final notifier = ref.read(themePreferencesProvider.notifier);
    final g = context.gloam;

    // Map slider 0..1 to font scale 0.85..1.25
    final sliderValue = (prefs.fontScale - 0.85) / (1.25 - 0.85);

    // Build theme grid in rows of 4
    final variants = ThemeVariant.values;
    final themeRows = <Widget>[];
    for (var i = 0; i < variants.length; i += 4) {
      final row = <Widget>[];
      for (var j = i; j < i + 4 && j < variants.length; j++) {
        if (row.isNotEmpty) row.add(const SizedBox(width: 10));
        final v = variants[j];
        final info = _themeInfo[v]!;
        row.add(_ThemeCard(
          label: info.$1,
          bgColor: info.$2,
          accentColor: prefs.accentColor.base,
          isSelected: prefs.variant == v,
          onTap: () => notifier.setVariant(v),
        ));
      }
      if (themeRows.isNotEmpty) themeRows.add(const SizedBox(height: 10));
      themeRows.add(Row(children: row));
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SettingsSectionHeader('theme'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(children: themeRows),
        ),

        const SettingsSectionHeader('density'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _DensityChip(
                label: 'compact',
                isSelected: prefs.density == DensityMode.compact,
                onTap: () => notifier.setDensity(DensityMode.compact),
              ),
              const SizedBox(width: 8),
              _DensityChip(
                label: 'comfortable',
                isSelected: prefs.density == DensityMode.comfortable,
                onTap: () => notifier.setDensity(DensityMode.comfortable),
              ),
              const SizedBox(width: 8),
              _DensityChip(
                label: 'spacious',
                isSelected: prefs.density == DensityMode.spacious,
                onTap: () => notifier.setDensity(DensityMode.spacious),
              ),
            ],
          ),
        ),

        const SettingsSectionHeader('accent color'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              for (final accent in AccentColor.values)
                _AccentDot(
                  color: accent.base,
                  isSelected: prefs.accentColor == accent,
                  onTap: () => notifier.setAccentColor(accent),
                ),
            ],
          ),
        ),

        const SettingsSectionHeader('font size'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Text('A', style: GoogleFonts.inter(fontSize: 12, color: g.textTertiary)),
              const SizedBox(width: 12),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: g.accent,
                    inactiveTrackColor: g.bgElevated,
                    thumbColor: g.accent,
                    overlayColor: g.accentDim.withValues(alpha: 0.2),
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    value: sliderValue.clamp(0.0, 1.0),
                    onChanged: (v) {
                      final scale = 0.85 + v * (1.25 - 0.85);
                      notifier.setFontScale(scale);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text('A', style: GoogleFonts.inter(fontSize: 18, color: g.textTertiary)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.label,
    required this.bgColor,
    required this.accentColor,
    this.isSelected = false,
    this.onTap,
  });

  final String label;
  final Color bgColor;
  final Color accentColor;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.gloam;
    // Use contrasting label color based on bg brightness
    final isLight = bgColor.computeLuminance() > 0.3;
    final labelColor = isSelected
        ? accentColor
        : isLight
            ? const Color(0xFF8FA894)
            : g.textTertiary;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
              border: Border.all(
                color: isSelected ? g.accent : g.border,
                width: isSelected ? 2 : 1,
              ),
            ),
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 28, height: 3, decoration: BoxDecoration(
                  color: accentColor, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 3),
                Text(label, style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: labelColor,
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DensityChip extends StatelessWidget {
  const _DensityChip({required this.label, this.isSelected = false, this.onTap});
  final String label;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.gloam;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? g.accentDim : null,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? g.accent : g.border,
            ),
          ),
          child: Text(label, style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            color: isSelected ? g.accent : g.textSecondary,
          )),
        ),
      ),
    );
  }
}

class _AccentDot extends StatelessWidget {
  const _AccentDot({required this.color, this.isSelected = false, this.onTap});
  final Color color;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final g = context.gloam;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: isSelected
                  ? Border.all(color: g.textPrimary, width: 2)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
