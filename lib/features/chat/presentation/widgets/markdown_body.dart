import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/gloam_color_extension.dart';
import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';

/// Renders message text with basic inline formatting.
///
/// Parses a subset of Markdown inline syntax:
/// **bold**, *italic*, ~~strikethrough~~, `inline code`,
/// [links](url), and ```code blocks```.
///
/// For Phase 1 this is a lightweight custom parser. We can migrate to
/// flutter_markdown or a full HTML renderer for formatted_body later.
class MarkdownBody extends StatelessWidget {
  const MarkdownBody({
    super.key,
    required this.text,
    this.formattedBody,
  });

  final String text;
  final String? formattedBody;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    // Check for code blocks first
    if (text.contains('```')) {
      return _buildWithCodeBlocks(colors, text);
    }

    return SelectableText.rich(
      _parseInline(colors, text),
      style: GoogleFonts.inter(
        fontSize: 14,
        color: colors.textPrimary,
        height: 1.5,
      ),
    );
  }

  Widget _buildWithCodeBlocks(GloamColorExtension colors, String input) {
    final parts = <Widget>[];
    final codeBlockRegex = RegExp(r'```(\w*)\n?([\s\S]*?)```');
    var lastEnd = 0;

    for (final match in codeBlockRegex.allMatches(input)) {
      // Text before code block
      if (match.start > lastEnd) {
        final before = input.substring(lastEnd, match.start).trim();
        if (before.isNotEmpty) {
          parts.add(SelectableText.rich(
            _parseInline(colors, before),
            style: GoogleFonts.inter(
              fontSize: 14,
              color: colors.textPrimary,
              height: 1.5,
            ),
          ));
        }
      }

      // Code block
      final code = match.group(2) ?? '';
      parts.add(Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: SelectableText(
          code.trim(),
          style: GoogleFonts.jetBrainsMono(
            fontSize: 13,
            color: colors.textPrimary,
            height: 1.5,
          ),
        ),
      ));

      lastEnd = match.end;
    }

    // Text after last code block
    if (lastEnd < input.length) {
      final after = input.substring(lastEnd).trim();
      if (after.isNotEmpty) {
        parts.add(SelectableText.rich(
          _parseInline(colors, after),
          style: GoogleFonts.inter(
            fontSize: 14,
            color: colors.textPrimary,
            height: 1.5,
          ),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: parts,
    );
  }

  TextSpan _parseInline(GloamColorExtension colors, String input) {
    final spans = <InlineSpan>[];
    final regex = RegExp(
      r'(\*\*(.+?)\*\*)'       // **bold**
      r'|(\*(.+?)\*)'           // *italic*
      r'|(~~(.+?)~~)'           // ~~strikethrough~~
      r'|(`(.+?)`)'             // `inline code`
      r'|(\[(.+?)\]\((.+?)\))', // [link](url)
    );

    var lastEnd = 0;
    for (final match in regex.allMatches(input)) {
      // Plain text before this match
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: input.substring(lastEnd, match.start)));
      }

      if (match.group(2) != null) {
        // Bold
        spans.add(TextSpan(
          text: match.group(2),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ));
      } else if (match.group(4) != null) {
        // Italic
        spans.add(TextSpan(
          text: match.group(4),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      } else if (match.group(6) != null) {
        // Strikethrough
        spans.add(TextSpan(
          text: match.group(6),
          style: const TextStyle(decoration: TextDecoration.lineThrough),
        ));
      } else if (match.group(8) != null) {
        // Inline code
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: colors.bg,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: colors.borderSubtle),
            ),
            child: Text(
              match.group(8)!,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                color: colors.accentBright,
              ),
            ),
          ),
        ));
      } else if (match.group(10) != null) {
        // Link
        spans.add(TextSpan(
          text: match.group(10),
          style: TextStyle(
            color: colors.accent,
            decoration: TextDecoration.underline,
            decorationColor: colors.accentDim,
          ),
        ));
      }

      lastEnd = match.end;
    }

    // Remaining plain text
    if (lastEnd < input.length) {
      spans.add(TextSpan(text: input.substring(lastEnd)));
    }

    return TextSpan(children: spans);
  }
}
