import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart' as md;
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;
import 'package:markdown/markdown.dart' as md_ast;
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/gloam_color_extension.dart';
import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../data/syntax_themes.dart';
import 'gloam_message_styles.dart';
import 'selectable_highlight.dart';
import 'spoiler_widget.dart';

/// Renders message text with full formatting support.
///
/// When [formattedBody] is present (Matrix `formatted_body` HTML), renders
/// via [HtmlWidget] for accurate cross-client fidelity. Falls back to
/// Markdown parsing of [text] when no formatted body is available.
///
/// Both paths produce pixel-identical output using shared style constants
/// from [GloamMessageStyles].
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

    if (formattedBody != null && formattedBody!.isNotEmpty) {
      return _buildHtmlBody(colors);
    }

    return _buildMarkdownBody(colors);
  }

  // ── HTML path (primary) ───────────────────────────────────────────────

  /// Strip the Matrix reply fallback (`<mx-reply>…</mx-reply>`) from HTML.
  /// The reply pill widget already renders reply context above the body.
  static final _mxReplyRegex = RegExp(
    r'<mx-reply>.*?</mx-reply>',
    dotAll: true,
  );

  Widget _buildHtmlBody(GloamColorExtension colors) {
    final themeId = syntaxThemeId ?? defaultSyntaxTheme;
    final html = formattedBody!.replaceAll(_mxReplyRegex, '').trimLeft();

    return HtmlWidget(
      html,
      textStyle: GloamMessageStyles.bodyStyle(colors),
      customStylesBuilder: (element) => _htmlStyles(element, colors),
      customWidgetBuilder: (element) =>
          _htmlCustomWidget(element, colors, themeId),
      onTapUrl: (url) {
        if (url.startsWith('https://matrix.to/#/@')) {
          final userId = Uri.decodeComponent(
            url.replaceFirst('https://matrix.to/#/', ''),
          );
          onMentionTap?.call(userId);
          return true;
        }
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        return true;
      },
      renderMode: RenderMode.column,
    );
  }

  /// Maps HTML elements to CSS overrides for Gloam styling.
  static Map<String, String>? _htmlStyles(
    dom.Element element,
    GloamColorExtension c,
  ) {
    switch (element.localName) {
      // ── Headings ──────────────────────────────────────────────────────
      case 'h1':
        return {
          'font-size': '${GloamMessageStyles.h1FontSize}px',
          'font-weight': '700',
          'line-height': '${GloamMessageStyles.headingLineHeight}',
        };
      case 'h2':
        return {
          'font-size': '${GloamMessageStyles.h2FontSize}px',
          'font-weight': '600',
          'line-height': '${GloamMessageStyles.headingLineHeight}',
        };
      case 'h3':
        return {
          'font-size': '${GloamMessageStyles.h3FontSize}px',
          'font-weight': '600',
          'line-height': '${GloamMessageStyles.headingLineHeight}',
        };
      case 'h4':
        return {
          'font-size': '${GloamMessageStyles.h4FontSize}px',
          'font-weight': '600',
          'line-height': '${GloamMessageStyles.headingLineHeight}',
        };
      case 'h5':
        return {
          'font-size': '${GloamMessageStyles.h5FontSize}px',
          'font-weight': '600',
          'line-height': '${GloamMessageStyles.headingLineHeight}',
        };
      case 'h6':
        return {
          'font-size': '${GloamMessageStyles.h6FontSize}px',
          'font-weight': '600',
          'line-height': '${GloamMessageStyles.headingLineHeight}',
        };

      // ── Blockquote ────────────────────────────────────────────────────
      case 'blockquote':
        return {
          'border-left': '${GloamMessageStyles.blockquoteBorderWidth}px solid ${_hex(c.accent)}',
          'padding-left': '${GloamMessageStyles.blockquotePaddingLeft}px',
          'font-style': 'italic',
          'color': _hex(c.textSecondary),
          'margin': '0',
        };

      // ── Inline code (not inside <pre>) ────────────────────────────────
      case 'code':
        if (element.parent?.localName != 'pre') {
          return {
            'font-family': 'JetBrains Mono',
            'font-size': '${GloamMessageStyles.codeFontSize}px',
            'color': _hex(c.accentBright),
            'background-color': _hex(c.bg),
          };
        }
        return null;

      // ── Links ─────────────────────────────────────────────────────────
      case 'a':
        return {
          'color': _hex(c.accent),
          'text-decoration': 'underline',
        };

      // ── Strikethrough ─────────────────────────────────────────────────
      case 'del':
      case 'strike':
      case 's':
        return {'text-decoration': 'line-through'};

      // ── Underline ─────────────────────────────────────────────────────
      case 'u':
        return {'text-decoration': 'underline'};

      // ── Horizontal rule ───────────────────────────────────────────────
      case 'hr':
        return {
          'border-top': '1px solid ${_hex(c.borderSubtle)}',
          'margin': '8px 0',
        };

      // ── Tables ────────────────────────────────────────────────────────
      case 'table':
        return {'border': '1px solid ${_hex(c.borderSubtle)}'};
      case 'th':
        return {
          'font-size': '${GloamMessageStyles.tableFontSize}px',
          'font-weight': '600',
          'padding': '8px',
          'border': '1px solid ${_hex(c.borderSubtle)}',
        };
      case 'td':
        return {
          'font-size': '${GloamMessageStyles.tableFontSize}px',
          'padding': '8px',
          'border': '1px solid ${_hex(c.borderSubtle)}',
        };

      // ── Matrix custom colors (span/font with data-mx-color) ───────────
      case 'span':
      case 'font':
        final mxColor =
            element.attributes['data-mx-color'] ?? element.attributes['color'];
        final mxBgColor = element.attributes['data-mx-bg-color'];
        if (mxColor != null || mxBgColor != null) {
          return {
            if (mxColor != null) 'color': mxColor,
            if (mxBgColor != null) 'background-color': mxBgColor,
          };
        }
        return null;

      default:
        return null;
    }
  }

  /// Returns a custom widget for elements needing non-CSS rendering.
  static Widget? _htmlCustomWidget(
    dom.Element element,
    GloamColorExtension colors,
    String syntaxThemeId,
  ) {
    // ── Fenced code blocks: <pre><code class="language-x">…</code></pre> ──
    if (element.localName == 'pre') {
      String code = element.text;
      String? language;

      for (final child in element.children) {
        if (child.localName == 'code') {
          code = child.text;
          language = child.attributes['class']?.replaceFirst('language-', '');
          break;
        }
      }

      code = code.trimRight();
      final theme = getSyntaxTheme(syntaxThemeId);

      return ClipRRect(
        borderRadius: BorderRadius.circular(GloamMessageStyles.codeBlockRadius),
        child: Container(
          width: double.infinity,
          decoration: GloamMessageStyles.codeBlockDecoration(colors),
          child: SelectableHighlightView(
            code,
            language: language ?? 'plaintext',
            theme: theme,
            padding: GloamMessageStyles.codeBlockPadding,
            textStyle: GloamMessageStyles.codeBlockTextStyle(),
          ),
        ),
      );
    }

    // ── Spoilers: <span data-mx-spoiler="reason">…</span> ──────────────
    if (element.attributes.containsKey('data-mx-spoiler')) {
      final reason = element.attributes['data-mx-spoiler'];
      return SpoilerWidget(
        reason: reason,
        child: Text(element.text),
      );
    }

    return null;
  }

  /// Converts a [Color] to a CSS hex string (#RRGGBB).
  static String _hex(Color color) {
    final r = (color.r * 255).round().toRadixString(16).padLeft(2, '0');
    final g = (color.g * 255).round().toRadixString(16).padLeft(2, '0');
    final b = (color.b * 255).round().toRadixString(16).padLeft(2, '0');
    return '#$r$g$b';
  }

  // ── Markdown fallback path ────────────────────────────────────────────

  /// Strip Matrix reply fallback from plain text (lines starting with `> `
  /// after a `> <@user>` header). The reply pill handles this context.
  static final _plainReplyRegex = RegExp(
    r'^> <[^>]+>.*\n(> .*\n)*\n?',
    multiLine: true,
  );

  Widget _buildMarkdownBody(GloamColorExtension colors) {
    final themeId = syntaxThemeId ?? defaultSyntaxTheme;
    final data = text.replaceAll(_plainReplyRegex, '').trimLeft();

    return md.MarkdownBody(
      data: data,
      selectable: selectable,
      softLineBreak: true,
      onTapLink: (text, href, title) {
        if (href == null) return;
        if (href.startsWith('https://matrix.to/#/@')) {
          final userId = Uri.decodeComponent(
            href.replaceFirst('https://matrix.to/#/', ''),
          );
          onMentionTap?.call(userId);
          return;
        }
        launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
      },
      styleSheet: GloamMessageStyles.markdownSheet(colors),
      builders: {
        'pre': _CodeBlockBuilder(syntaxThemeId: themeId, colors: colors),
      },
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
      borderRadius: BorderRadius.circular(GloamMessageStyles.codeBlockRadius),
      child: Container(
        decoration: GloamMessageStyles.codeBlockDecoration(colors),
        child: SelectableHighlightView(
          code,
          language: language ?? 'plaintext',
          theme: theme,
          padding: GloamMessageStyles.codeBlockPadding,
          textStyle: GloamMessageStyles.codeBlockTextStyle(),
        ),
      ),
    );
  }
}
