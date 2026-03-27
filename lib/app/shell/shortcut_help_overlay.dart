import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/color_tokens.dart';
import '../theme/spacing.dart';
import '../shortcuts.dart';

/// Shows a keyboard shortcut help overlay.
Future<void> showShortcutHelp(BuildContext context) {
  return showDialog(
    context: context,
    barrierColor: GloamColors.overlay,
    builder: (ctx) => Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: GloamColors.bgSurface,
            borderRadius: BorderRadius.circular(GloamSpacing.radiusLg),
            border: Border.all(color: GloamColors.border),
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
                  color: GloamColors.textPrimary,
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
                            color: GloamColors.textTertiary,
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
                                color: GloamColors.textSecondary,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: GloamColors.bgElevated,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: GloamColors.border),
                            ),
                            child: Text(
                              keys,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                color: GloamColors.textTertiary,
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
                    color: GloamColors.textTertiary,
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
