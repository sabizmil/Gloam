import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart' as md;
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;
import 'package:markdown/markdown.dart' as md_ast;
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/gloam_color_extension.dart';
import '../../../../app/theme/gloam_theme_ext.dart';
import '../../../../data/syntax_themes.dart';
import '../utils/emoji_detection.dart';
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

    // Slack/Discord-style forgiveness: when the user wraps content in ``` but
    // the content itself contains backticks, CommonMark rejects the fence and
    // collapses everything into a paragraph of inline code (dropping line
    // breaks). Detect that case and render a code block ourselves.
    final forced = _extractForcedFence();
    if (forced != null) {
      return _buildForcedCodeBlock(colors, forced.$1, forced.$2);
    }

    // Jumbo emoji-only branch — must run before code-fence detection above
    // already cleared, but after, so legitimate code fences still win.
    final classification = classifyMessage(
      plainText: text,
      formattedHtml: formattedBody,
    );
    final jumbo = GloamMessageStyles.jumboSizeFor(classification.emojiCount);
    if (classification.isEmojiOnly && jumbo != null) {
      return _buildJumboBody(colors, jumbo);
    }

    if (formattedBody != null && formattedBody!.isNotEmpty) {
      return _buildHtmlBody(colors);
    }

    return _buildMarkdownBody(colors);
  }

  // ── Jumbo emoji-only path ─────────────────────────────────────────────

  /// Renders an emoji-only message at jumbo size. Routes through HtmlWidget
  /// when there's a formatted body so custom emoji (`<img data-mx-emoticon>`)
  /// are rendered alongside unicode glyphs at the same scaled size.
  Widget _buildJumboBody(GloamColorExtension colors, double size) {
    final fb = formattedBody;
    if (fb != null && fb.isNotEmpty) {
      // Strip wrapper paragraphs so the row sits flush — keeps spacing tight.
      final stripped = fb.replaceAll(_mxReplyRegex, '').trim();
      return HtmlWidget(
        stripped,
        textStyle: TextStyle(
          fontSize: size,
          height: 1.2,
          color: colors.textPrimary,
        ),
        customWidgetBuilder: (element) {
          if (element.localName == 'img' &&
              element.attributes.containsKey('data-mx-emoticon')) {
            return _renderCustomEmoji(element, size);
          }
          return null;
        },
        renderMode: RenderMode.column,
      );
    }
    return Text(
      text.trim(),
      style: TextStyle(
        fontSize: size,
        height: 1.2,
        color: colors.textPrimary,
      ),
    );
  }

  /// Renders a Matrix custom emoji (`<img data-mx-emoticon>`) at the given
  /// pixel size. Matrix `mxc://` URIs aren't fetchable directly — they'd
  /// typically be resolved via the homeserver. For now we honor the `src`
  /// attribute as-is (some clients put http(s) thumbnails there).
  static Widget _renderCustomEmoji(dom.Element element, double size) {
    final src = element.attributes['src'];
    final alt = element.attributes['alt'] ?? '';
    if (src == null || src.startsWith('mxc://')) {
      // Fall back to alt text — better than a broken image glyph.
      return Text(alt, style: TextStyle(fontSize: size));
    }
    return SizedBox(
      width: size,
      height: size,
      child: Image.network(
        src,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            Text(alt, style: TextStyle(fontSize: size)),
      ),
    );
  }

  /// Returns `(content, language)` if the message is a triple-backtick-wrapped
  /// multi-line block. Extracts from the plain-text [text] body because the
  /// Matrix SDK's `convertLinebreaksToBr` mangles newlines inside `<pre>` tags
  /// that carry attributes (e.g. `data-metadata`) — so the HTML path can't be
  /// trusted to preserve line breaks.
  (String, String?)? _extractForcedFence() {
    final trimmed = text.trim();
    if (!trimmed.startsWith('```') || !trimmed.endsWith('```')) return null;
    if (trimmed.length < 7) return null;
    if (!trimmed.contains('\n')) return null;

    // If the formatted body contains multiple <pre> blocks, the user used
    // explicit fences correctly — don't flatten them into one.
    final fb = formattedBody ?? '';
    if (RegExp(r'<pre').allMatches(fb).length > 1) return null;

    var inner = trimmed.substring(3, trimmed.length - 3);
    String? language;
    final firstNl = inner.indexOf('\n');
    if (firstNl > 0 && firstNl < 20) {
      final firstLine = inner.substring(0, firstNl).trim();
      if (_isLanguageToken(firstLine)) {
        language = firstLine;
        inner = inner.substring(firstNl + 1);
      }
    }
    if (inner.startsWith('\n')) inner = inner.substring(1);
    return (inner.trimRight(), language);
  }

  Widget _buildForcedCodeBlock(
    GloamColorExtension colors,
    String code,
    String? language,
  ) {
    final themeId = syntaxThemeId ?? defaultSyntaxTheme;
    final theme = getSyntaxTheme(themeId);
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

  // ── HTML path (primary) ───────────────────────────────────────────────

  /// Strip the Matrix reply fallback (`<mx-reply>…</mx-reply>`) from HTML.
  /// The reply pill widget already renders reply context above the body.
  static final _mxReplyRegex = RegExp(
    r'<mx-reply>.*?</mx-reply>',
    dotAll: true,
  );

  /// Matrix clients wrap `$…$` inline LaTeX as
  /// `<span data-mx-maths="…"><code>…</code></span>`. We don't render math —
  /// unwrap to literal `$…$` text so `$9/$10` stays as-is.
  static final _inlineLatexRegex = RegExp(
    r'<span[^>]*data-mx-maths[^>]*>\s*<code>(.*?)</code>\s*</span>',
    dotAll: true,
  );

  /// Block LaTeX: `<div data-mx-maths="…"><pre><code>…</code></pre></div>`.
  static final _blockLatexRegex = RegExp(
    r'<div[^>]*data-mx-maths[^>]*>\s*<pre>\s*<code>(.*?)</code>\s*</pre>\s*</div>',
    dotAll: true,
  );

  Widget _buildHtmlBody(GloamColorExtension colors) {
    final themeId = syntaxThemeId ?? defaultSyntaxTheme;
    var html = formattedBody!.replaceAll(_mxReplyRegex, '').trimLeft();
    html = html.replaceAllMapped(
      _blockLatexRegex,
      (m) => r'$$' + (m.group(1) ?? '') + r'$$',
    );
    html = html.replaceAllMapped(
      _inlineLatexRegex,
      (m) => r'$' + (m.group(1) ?? '') + r'$',
    );
    // Bump inline unicode emoji glyphs above body 14pt so they're legible.
    // Skips text inside <pre>, <code>, and tag attributes.
    html = _bumpInlineEmojisInHtml(html, GloamMessageStyles.emojiInlineSize);

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

      // Slack/Discord-style forgiveness: CommonMark treats everything after
      // the opening ``` on line 1 as the info string (language +
      // data-metadata). When that "info" is really prose — either the block
      // has no body, or the language token isn't a valid language
      // identifier — fold it back into the code content as the first line.
      final metadata = element.attributes['data-metadata'];
      final hasMetadata = metadata != null && metadata.isNotEmpty;
      if (code.isEmpty || !_isLanguageToken(language)) {
        final parts = [
          if (language != null && language.isNotEmpty) language,
          if (hasMetadata) metadata,
        ];
        if (parts.isNotEmpty) {
          final firstLine = parts.join(' ');
          code = code.isEmpty ? firstLine : '$firstLine\n$code';
          language = null;
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

    // ── Custom emoji inline: <img data-mx-emoticon …> ──────────────────
    // Jumbo path is handled separately in _buildJumboBody; this branch
    // sizes inline custom emoji above the default img size for legibility.
    if (element.localName == 'img' &&
        element.attributes.containsKey('data-mx-emoticon')) {
      return _renderCustomEmoji(element, GloamMessageStyles.emojiCustomInlineSize);
    }

    return null;
  }

  /// Wraps each emoji grapheme in a `<span>` with the bumped font size,
  /// while leaving HTML tags and `<pre>`/`<code>` content untouched.
  static String _bumpInlineEmojisInHtml(String html, double size) {
    // Match either a code block (whole thing) or any single tag.
    final segmentRe = RegExp(
      r'<(pre|code)\b[^>]*>.*?</\1>|<[^>]+>',
      dotAll: true,
      caseSensitive: false,
    );
    final out = StringBuffer();
    var pos = 0;
    for (final m in segmentRe.allMatches(html)) {
      out.write(_wrapEmojisInPlainText(html.substring(pos, m.start), size));
      out.write(m.group(0));
      pos = m.end;
    }
    out.write(_wrapEmojisInPlainText(html.substring(pos), size));
    return out.toString();
  }

  static String _wrapEmojisInPlainText(String text, double size) {
    if (text.isEmpty) return text;
    final out = StringBuffer();
    for (final g in text.characters) {
      if (isEmojiGrapheme(g)) {
        out
          ..write('<span style="font-size: ')
          ..write(size)
          ..write('px;">')
          ..write(g)
          ..write('</span>');
      } else {
        out.write(g);
      }
    }
    return out.toString();
  }

  /// Whether [token] looks like a programming-language identifier (short,
  /// alphanumeric start). Used to decide when an info string is really code.
  static bool _isLanguageToken(String? token) {
    if (token == null || token.isEmpty) return false;
    if (token.length > 20) return false;
    return RegExp(r'^[a-zA-Z][\w+-]*$').hasMatch(token);
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
    var code = element.textContent.trimRight();

    String? language;
    if (element.children != null) {
      for (final child in element.children!) {
        if (child is md_ast.Element && child.tag == 'code') {
          language = child.attributes['class']?.replaceFirst('language-', '');
          break;
        }
      }
    }

    // Slack/Discord-style forgiveness: when the info string was really prose
    // (empty body, or the "language" isn't a valid language token), fold it
    // back into the content as the first line.
    final metadata = element.attributes['data-metadata'];
    final hasMetadata = metadata != null && metadata.isNotEmpty;
    if (code.isEmpty || !MarkdownBody._isLanguageToken(language)) {
      final parts = [
        if (language != null && language.isNotEmpty) language,
        if (hasMetadata) metadata,
      ];
      if (parts.isNotEmpty) {
        final firstLine = parts.join(' ');
        code = code.isEmpty ? firstLine : '$firstLine\n$code';
        language = null;
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
