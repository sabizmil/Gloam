import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/color_tokens.dart';
import '../../../../app/theme/spacing.dart';
import '../widgets/settings_tile.dart';

class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context) {
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
                accentColor: GloamColors.accent,
                isSelected: true,
              ),
              const SizedBox(width: 12),
              _ThemeCard(
                label: 'midnight',
                bgColor: const Color(0xFF0A0F14),
                accentColor: const Color(0xFF5C8AC4),
                isSelected: false,
              ),
              const SizedBox(width: 12),
              _ThemeCard(
                label: 'dawn',
                bgColor: const Color(0xFFF5F5F0),
                accentColor: const Color(0xFF2D5A3D),
                isSelected: false,
              ),
            ],
          ),
        ),

        const SettingsSectionHeader('density'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _DensityChip(label: 'compact', isSelected: false),
              const SizedBox(width: 8),
              _DensityChip(label: 'comfortable', isSelected: true),
              const SizedBox(width: 8),
              _DensityChip(label: 'spacious', isSelected: false),
            ],
          ),
        ),

        const SettingsSectionHeader('accent color'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _AccentDot(color: GloamColors.accent, isSelected: true),
              _AccentDot(color: const Color(0xFF5C8AC4)),
              _AccentDot(color: const Color(0xFFC45C8A)),
              _AccentDot(color: const Color(0xFFC4A35C)),
              _AccentDot(color: const Color(0xFF8A5CC4)),
              _AccentDot(color: const Color(0xFF5CC4C4)),
            ],
          ),
        ),

        const SettingsSectionHeader('font size'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Text('A', style: GoogleFonts.inter(fontSize: 12, color: GloamColors.textTertiary)),
              const SizedBox(width: 12),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: GloamColors.accent,
                    inactiveTrackColor: GloamColors.bgElevated,
                    thumbColor: GloamColors.accent,
                    overlayColor: GloamColors.accentDim.withValues(alpha: 0.2),
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    value: 0.5,
                    onChanged: (_) {},
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text('A', style: GoogleFonts.inter(fontSize: 18, color: GloamColors.textTertiary)),
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
  });

  final String label;
  final Color bgColor;
  final Color accentColor;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(GloamSpacing.radiusMd),
          border: Border.all(
            color: isSelected ? GloamColors.accent : GloamColors.border,
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
              color: isSelected ? accentColor : GloamColors.textTertiary,
            )),
          ],
        ),
      ),
    );
  }
}

class _DensityChip extends StatelessWidget {
  const _DensityChip({required this.label, this.isSelected = false});
  final String label;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected ? GloamColors.accentDim : null,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isSelected ? GloamColors.accent : GloamColors.border,
        ),
      ),
      child: Text(label, style: GoogleFonts.jetBrainsMono(
        fontSize: 11,
        color: isSelected ? GloamColors.accent : GloamColors.textSecondary,
      )),
    );
  }
}

class _AccentDot extends StatelessWidget {
  const _AccentDot({required this.color, this.isSelected = false});
  final Color color;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected
              ? Border.all(color: GloamColors.textPrimary, width: 2)
              : null,
        ),
      ),
    );
  }
}
