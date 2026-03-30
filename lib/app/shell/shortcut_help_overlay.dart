import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/gloam_theme_ext.dart';
import '../theme/spacing.dart';
import '../shortcuts.dart';

/// Shows a keyboard shortcut help overlay.
Future<void> showShortcutHelp(BuildContext context) {
  return showDialog(
    context: context,
    barrierColor: context.gloam.overlay,
    builder: (ctx) => Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: context.gloam.bgSurface,
            borderRadius: BorderRadius.circular(GloamSpacing.radiusLg),
            border: Border.all(color: context.gloam.border),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0A1A0E).withAlpha(128),
                blurRadius: 60,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'keyboard shortcuts',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: context.gloam.textPrimary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 20),
              ...shortcutHelpEntries.map((entry) {
                final label = entry.$1;
                final keys = entry.$2;
                final category = entry.$3;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (category != null) ...[
                      if (category != 'navigation')
                        const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '// $category',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            color: context.gloam.textTertiary,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: context.gloam.textSecondary,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: context.gloam.bgElevated,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: context.gloam.border),
                            ),
                            child: Text(
                              keys,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                color: context.gloam.textTertiary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  'press esc to close',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: context.gloam.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
