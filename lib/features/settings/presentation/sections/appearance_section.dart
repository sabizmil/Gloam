import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/theme_preferences.dart';
import '../../../../app/theme/theme_variants.dart';
import '../widgets/settings_tile.dart';

class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(themePreferencesProvider);
    final notifier = ref.read(themePreferencesProvider.notifier);
    final g = context.gloam;

    // Map slider 0..1 to font scale 0.85..1.25
    final sliderValue = (prefs.fontScale - 0.85) / (1.25 - 0.85);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SettingsSectionHeader('theme'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _ThemeCard(
                label: 'gloam dark',
                bgColor: const Color(0xFF080F0A),
                accentColor: prefs.accentColor.base,
                isSelected: prefs.variant == ThemeVariant.gloamDark,
                onTap: () => notifier.setVariant(ThemeVariant.gloamDark),
              ),
              const SizedBox(width: 12),
              _ThemeCard(
                label: 'midnight',
                bgColor: const Color(0xFF0A0F14),
                accentColor: prefs.accentColor.base,
                isSelected: prefs.variant == ThemeVariant.midnight,
                onTap: () => notifier.setVariant(ThemeVariant.midnight),
              ),
              const SizedBox(width: 12),
              _ThemeCard(
                label: 'dawn',
                bgColor: const Color(0xFFF5F5F0),
                accentColor: prefs.accentColor.base,
                isSelected: prefs.variant == ThemeVariant.dawn,
                onTap: () => notifier.setVariant(ThemeVariant.dawn),
              ),
            ],
          ),
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
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            height: 80,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
              border: Border.all(
                color: isSelected ? g.accent : g.border,
                width: isSelected ? 2 : 1,
              ),
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(
                  color: accentColor, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 4),
                Text(label, style: GoogleFonts.jetBrainsMono(
                  fontSize: 9,
                  color: isSelected ? accentColor : g.textTertiary,
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
