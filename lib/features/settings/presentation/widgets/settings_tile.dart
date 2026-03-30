import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_theme_ext.dart';

/// Standard settings row: icon + label + trailing (value text, toggle, chevron).
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    this.icon,
    required this.label,
    this.value,
    this.trailing,
    this.onTap,
    this.danger = false,
  });

  final IconData? icon;
  final String label;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? context.gloam.danger : context.gloam.textPrimary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: context.gloam.bgElevated,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: danger ? context.gloam.danger : context.gloam.textSecondary),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(fontSize: 14, color: color),
                ),
              ),
              if (value != null)
                Text(
                  value!,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    color: context.gloam.textTertiary,
                  ),
                ),
              if (trailing != null) trailing!,
              if (onTap != null && trailing == null && value == null)
                Icon(Icons.chevron_right, size: 16, color: context.gloam.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// `// SECTION HEADER` in the settings panel.
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
      child: Text(
        '// $text',
        style: GoogleFonts.jetBrainsMono(
          fontSize: 10,
          color: context.gloam.textTertiary,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
