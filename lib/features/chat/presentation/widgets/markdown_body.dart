import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart' as md;
import 'package:markdown/markdown.dart' as md_ast;
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/gloam_color_extension.dart';
import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../data/syntax_themes.dart';
import 'selectable_highlight.dart';

/// Renders message text with full Markdown support via flutter_markdown.
///
/// Supports headings, tables, blockquotes, lists, horizontal rules,
/// fenced code blocks with syntax highlighting, and inline formatting.
///
/// When [formattedBody] contains `matrix.to` mention links, those are
/// handled via the onTapLink callback.
class MarkdownBody extends StatelessWidget {
  const MarkdownBody({
    super.key,
    required this.text,
    this.formattedBody,
    this.selfUserId,
    this.onMentionTap,
    this.syntaxThemeId,
    this.selectable = true,
  });

  final String text;
  final String? formattedBody;
  final String? selfUserId;
  final void Function(String userId)? onMentionTap;
  final String? syntaxThemeId;
  /// Set to false when wrapped in a SelectionArea (e.g. file preview modal).
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    final themeId = syntaxThemeId ?? defaultSyntaxTheme;

    return md.MarkdownBody(
      data: text,
      selectable: selectable,
      softLineBreak: true,
      onTapLink: (text, href, title) {
        if (href == null) return;
        // Mention links
        if (href.startsWith('https://matrix.to/#/@')) {
          final userId = Uri.decodeComponent(
            href.replaceFirst('https://matrix.to/#/', ''),
          );
          onMentionTap?.call(userId);
          return;
        }
        launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
      },
      styleSheet: _buildStyleSheet(colors),
      builders: {
        'pre': _CodeBlockBuilder(syntaxThemeId: themeId, colors: colors),
      },
    );
  }

  static md.MarkdownStyleSheet _buildStyleSheet(GloamColorExtension colors) {
    return md.MarkdownStyleSheet(
      // Body text
      p: GoogleFonts.inter(
        fontSize: 14,
        color: colors.textPrimary,
        height: 1.5,
      ),
      // Headings
      h1: GoogleFonts.inter(
        fontSize: 22, fontWeight: FontWeight.w700,
        color: colors.textPrimary, height: 1.4,
      ),
      h2: GoogleFonts.inter(
        fontSize: 19, fontWeight: FontWeight.w600,
        color: colors.textPrimary, height: 1.4,
      ),
      h3: GoogleFonts.inter(
        fontSize: 16, fontWeight: FontWeight.w600,
        color: colors.textPrimary, height: 1.4,
      ),
      h4: GoogleFonts.inter(
        fontSize: 14, fontWeight: FontWeight.w600,
        color: colors.textPrimary, height: 1.4,
      ),
      // Inline
      strong: const TextStyle(fontWeight: FontWeight.w600),
      em: const TextStyle(fontStyle: FontStyle.italic),
      del: const TextStyle(decoration: TextDecoration.lineThrough),
      // Links
      a: TextStyle(
        color: colors.accent,
        decoration: TextDecoration.underline,
        decorationColor: colors.accentDim,
      ),
      // Inline code
      code: GoogleFonts.jetBrainsMono(
        fontSize: 13,
        color: colors.accentBright,
        backgroundColor: colors.bg,
      ),
      // Code blocks — fallback styling (overridden by builder for syntax highlight)
      codeblockDecoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
        border: Border.all(color: colors.borderSubtle),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      // Blockquotes
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: colors.accent, width: 3),
        ),
      ),
      blockquotePadding: const EdgeInsets.only(left: 12),
      blockquote: GoogleFonts.inter(
        fontSize: 14, color: colors.textSecondary,
        fontStyle: FontStyle.italic, height: 1.5,
      ),
      // Lists
      listBullet: GoogleFonts.inter(fontSize: 14, color: colors.textSecondary),
      // Horizontal rule
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.borderSubtle, width: 1)),
      ),
      // Tables
      tableHead: GoogleFonts.inter(
        fontSize: 13, fontWeight: FontWeight.w600, color: colors.textPrimary,
      ),
      tableBody: GoogleFonts.inter(fontSize: 13, color: colors.textPrimary),
      tableBorder: TableBorder.all(color: colors.borderSubtle, width: 1),
      tableCellsPadding: const EdgeInsets.all(8),
    );
  }
}

/// Custom builder for fenced code blocks with syntax highlighting.
class _CodeBlockBuilder extends md.MarkdownElementBuilder {
  _CodeBlockBuilder({required this.syntaxThemeId, required this.colors});

  final String syntaxThemeId;
  final GloamColorExtension colors;

  @override
  Widget? visitElementAfter(element, TextStyle? preferredStyle) {
    final code = element.textContent.trimRight();

    // Try to extract language from child <code> element's class attribute
    String? language;
    if (element.children != null) {
      for (final child in element.children!) {
        if (child is md_ast.Element && child.tag == 'code') {
          language = child.attributes['class']?.replaceFirst('language-', '');
          break;
        }
      }
    }

    final theme = getSyntaxTheme(syntaxThemeId);

    return ClipRRect(
      borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: colors.borderSubtle),
          borderRadius: BorderRadius.circular(GloamSpacing.radiusSm),
        ),
        child: SelectableHighlightView(
          code,
          language: language ?? 'plaintext',
          theme: theme,
          padding: const EdgeInsets.all(12),
          textStyle: GoogleFonts.jetBrainsMono(fontSize: 13, height: 1.5),
        ),
      ),
    );
  }
}
