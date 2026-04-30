import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart' as md;
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_color_extension.dart';
import '../../../../app/theme/spacing.dart';

/// Shared message text-style constants consumed by both the Markdown and
/// HTML rendering paths to guarantee pixel-perfect parity.
abstract final class GloamMessageStyles {
  // ── Body ──────────────────────────────────────────────────────────────
  static const bodyFontSize = 14.0;
  static const bodyLineHeight = 1.5;

  // ── Headings ──────────────────────────────────────────────────────────
  static const h1FontSize = 22.0;
  static const h1FontWeight = FontWeight.w700;
  static const h2FontSize = 19.0;
  static const h2FontWeight = FontWeight.w600;
  static const h3FontSize = 16.0;
  static const h3FontWeight = FontWeight.w600;
  static const h4FontSize = 14.0;
  static const h4FontWeight = FontWeight.w600;
  static const h5FontSize = 13.0;
  static const h5FontWeight = FontWeight.w600;
  static const h6FontSize = 12.0;
  static const h6FontWeight = FontWeight.w600;
  static const headingLineHeight = 1.4;

  // ── Code ──────────────────────────────────────────────────────────────
  static const codeFontSize = 13.0;
  static const codeBlockPadding = EdgeInsets.all(12);
  static const codeBlockRadius = GloamSpacing.radiusSm;

  // ── Emoji ─────────────────────────────────────────────────────────────
  static const emojiInlineSize = 18.0;
  static const emojiCustomInlineSize = 24.0;
  static const emojiJumboSize1 = 44.0;
  static const emojiJumboSize2 = 36.0;
  static const emojiJumboSize3 = 32.0;
  static const emojiReactionSize = 16.0;

  /// Pick the jumbo size for a given emoji count. Returns null when the
  /// count is outside the jumbo range (use inline sizing instead).
  static double? jumboSizeFor(int count) => switch (count) {
        1 => emojiJumboSize1,
        2 => emojiJumboSize2,
        3 => emojiJumboSize3,
        _ => null,
      };

  // ── Blockquote ────────────────────────────────────────────────────────
  static const blockquoteBorderWidth = 3.0;
  static const blockquotePaddingLeft = 12.0;

  // ── Tables ────────────────────────────────────────────────────────────
  static const tableFontSize = 13.0;
  static const tableCellPadding = EdgeInsets.all(8);

  // ── Helpers ───────────────────────────────────────────────────────────

  static TextStyle bodyStyle(GloamColorExtension c) => GoogleFonts.inter(
        fontSize: bodyFontSize,
        color: c.textPrimary,
        height: bodyLineHeight,
      );

  static TextStyle codeInlineStyle(GloamColorExtension c) =>
      GoogleFonts.jetBrainsMono(
        fontSize: codeFontSize,
        color: c.accentBright,
        backgroundColor: c.bg,
      );

  static TextStyle codeBlockTextStyle() =>
      GoogleFonts.jetBrainsMono(fontSize: codeFontSize, height: bodyLineHeight);

  static BoxDecoration codeBlockDecoration(GloamColorExtension c) =>
      BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(codeBlockRadius),
        border: Border.all(color: c.borderSubtle),
      );

  static BoxDecoration blockquoteDecoration(GloamColorExtension c) =>
      BoxDecoration(
        border: Border(
          left: BorderSide(color: c.accent, width: blockquoteBorderWidth),
        ),
      );

  static BoxDecoration hrDecoration(GloamColorExtension c) => BoxDecoration(
        border: Border(top: BorderSide(color: c.borderSubtle, width: 1)),
      );

  // ── Markdown path ────────────────────────────────────────────────────

  static md.MarkdownStyleSheet markdownSheet(GloamColorExtension c) {
    return md.MarkdownStyleSheet(
      p: bodyStyle(c),
      h1: GoogleFonts.inter(
        fontSize: h1FontSize, fontWeight: h1FontWeight,
        color: c.textPrimary, height: headingLineHeight,
      ),
      h2: GoogleFonts.inter(
        fontSize: h2FontSize, fontWeight: h2FontWeight,
        color: c.textPrimary, height: headingLineHeight,
      ),
      h3: GoogleFonts.inter(
        fontSize: h3FontSize, fontWeight: h3FontWeight,
        color: c.textPrimary, height: headingLineHeight,
      ),
      h4: GoogleFonts.inter(
        fontSize: h4FontSize, fontWeight: h4FontWeight,
        color: c.textPrimary, height: headingLineHeight,
      ),
      strong: const TextStyle(fontWeight: FontWeight.w600),
      em: const TextStyle(fontStyle: FontStyle.italic),
      del: const TextStyle(decoration: TextDecoration.lineThrough),
      a: TextStyle(
        color: c.accent,
        decoration: TextDecoration.underline,
        decorationColor: c.accentDim,
      ),
      code: codeInlineStyle(c),
      codeblockDecoration: codeBlockDecoration(c),
      codeblockPadding: codeBlockPadding,
      blockquoteDecoration: blockquoteDecoration(c),
      blockquotePadding: const EdgeInsets.only(left: blockquotePaddingLeft),
      blockquote: GoogleFonts.inter(
        fontSize: bodyFontSize, color: c.textSecondary,
        fontStyle: FontStyle.italic, height: bodyLineHeight,
      ),
      listBullet: GoogleFonts.inter(fontSize: bodyFontSize, color: c.textSecondary),
      horizontalRuleDecoration: hrDecoration(c),
      tableHead: GoogleFonts.inter(
        fontSize: tableFontSize, fontWeight: FontWeight.w600, color: c.textPrimary,
      ),
      tableBody: GoogleFonts.inter(fontSize: tableFontSize, color: c.textPrimary),
      tableBorder: TableBorder.all(color: c.borderSubtle, width: 1),
      tableCellsPadding: tableCellPadding,
    );
  }
}
