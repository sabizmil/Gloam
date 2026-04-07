import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/theme_preferences.dart';
import '../../../../app/theme/theme_variants.dart';
import '../../../../data/syntax_themes.dart';
import '../../../chat/presentation/widgets/markdown_body.dart';
import '../../../chat/presentation/widgets/selectable_highlight.dart';
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: controls
        Expanded(
          child: _AppearanceControls(prefs: prefs, notifier: notifier),
        ),

        // Divider
        Container(width: 1, color: g.border),

        // Right: live preview
        Expanded(
          child: _AppearancePreview(prefs: prefs),
        ),
      ],
    );
  }
}

// ── Controls (left pane) ──

class _AppearanceControls extends StatelessWidget {
  const _AppearanceControls({required this.prefs, required this.notifier});
  final ThemePreferences prefs;
  final ThemePreferencesNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final g = context.gloam;
    final sliderValue = (prefs.fontScale - 0.85) / (1.25 - 0.85);

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

        const SettingsSectionHeader('code theme'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: syntaxThemes.map((t) {
              final isSelected = prefs.syntaxThemeId == t.id;
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => notifier.setSyntaxTheme(t.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? g.accentDim : g.bgElevated,
                      borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
                      border: Border.all(
                        color: isSelected ? g.accent : g.border,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          t.isDark ? Icons.dark_mode : Icons.light_mode,
                          size: 12,
                          color: isSelected ? g.accentBright : g.textTertiary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          t.displayName,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            color: isSelected ? g.accentBright : g.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ── Live preview (right pane) ──

const _previewMarkdown = '''I've been looking at the **navigation patterns** in the `competitive analysis`. The space rail approach from Discord is the strongest model — but we should make it feel more... *atmospheric*.''';

const _previewReplyBody = 'Agreed @mara, check [this reference](https://example.com) for the tab pattern we discussed.';

const _previewCode = '''class Message {
  final String body;
  final DateTime timestamp;

  // Send to the Matrix server
  Future<void> send() async {
    await room.sendEvent({'body': body});
  }
}''';

class _AppearancePreview extends StatelessWidget {
  const _AppearancePreview({required this.prefs});
  final ThemePreferences prefs;

  @override
  Widget build(BuildContext context) {
    final g = context.gloam;
    final syntaxTheme = getSyntaxTheme(prefs.syntaxThemeId);

    return Container(
      color: g.bg,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Section label
          Text(
            '// preview',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10, color: g.textTertiary, letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 16),

          // Message 1 — with formatting
          _MockMessage(
            name: 'mara voss',
            time: '11:42 am',
            avatarColor: g.accentDim,
            child: MarkdownBody(
              text: _previewMarkdown,
              syntaxThemeId: prefs.syntaxThemeId,
            ),
          ),

          const SizedBox(height: 16),

          // Message 2 — with reply pill and mention
          _MockMessage(
            name: 'alex chen',
            time: '11:44 am',
            avatarColor: g.info.withAlpha(80),
            replyTo: 'mara voss',
            child: MarkdownBody(
              text: _previewReplyBody,
              syntaxThemeId: prefs.syntaxThemeId,
            ),
          ),

          const SizedBox(height: 16),

          // Code block preview
          _MockMessage(
            name: 'simon',
            time: '11:46 am',
            avatarColor: g.warning.withAlpha(80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Here\'s the implementation:',
                  style: GoogleFonts.inter(fontSize: 14, color: g.textPrimary, height: 1.5),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: g.borderSubtle),
                      borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
                    ),
                    child: SelectableHighlightView(
                      _previewCode,
                      language: 'dart',
                      theme: syntaxTheme,
                      padding: const EdgeInsets.all(12),
                      textStyle: GoogleFonts.jetBrainsMono(fontSize: 13, height: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Room list row preview
          Text(
            '// room list',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10, color: g.textTertiary, letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: g.bgElevated,
              borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
            ),
            child: Row(
              children: [
                Text('# ', style: GoogleFonts.jetBrainsMono(fontSize: 14, color: g.textTertiary)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('design', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: g.textPrimary)),
                      const SizedBox(height: 2),
                      Text('mara: I\'ve been looking at the nav...', style: GoogleFonts.inter(fontSize: 12, color: g.textTertiary), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: g.accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('3', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: g.bg)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mock message widget ──

class _MockMessage extends StatelessWidget {
  const _MockMessage({
    required this.name,
    required this.time,
    required this.avatarColor,
    required this.child,
    this.replyTo,
  });

  final String name;
  final String time;
  final Color avatarColor;
  final Widget child;
  final String? replyTo;

  @override
  Widget build(BuildContext context) {
    final g = context.gloam;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Avatar
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: avatarColor,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              name[0].toUpperCase(),
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: g.textPrimary),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name + time
              Row(
                children: [
                  Text(name, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: g.textPrimary)),
                  const SizedBox(width: 8),
                  Text(time, style: GoogleFonts.jetBrainsMono(fontSize: 10, color: g.textTertiary)),
                ],
              ),
              const SizedBox(height: 4),
              // Reply pill
              if (replyTo != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(Icons.reply, size: 12, color: g.textTertiary),
                      const SizedBox(width: 4),
                      Text('replying to $replyTo', style: GoogleFonts.inter(fontSize: 11, color: g.textTertiary)),
                    ],
                  ),
                ),
              // Content
              child,
            ],
          ),
        ),
      ],
    );
  }
}

// ── Shared control widgets ──

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
                  fontSize: 11, color: labelColor,
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
            border: Border.all(color: isSelected ? g.accent : g.border),
          ),
          child: Text(label, style: GoogleFonts.jetBrainsMono(
            fontSize: 11, color: isSelected ? g.accent : g.textSecondary,
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
              border: isSelected ? Border.all(color: g.textPrimary, width: 2) : null,
            ),
          ),
        ),
      ),
    );
  }
}
