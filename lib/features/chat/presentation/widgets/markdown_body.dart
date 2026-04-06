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
/// When [formattedBody] contains `matrix.to` mention links, renders them
/// as styled inline mention pills.
class MarkdownBody extends StatelessWidget {
  const MarkdownBody({
    super.key,
    required this.text,
    this.formattedBody,
    this.selfUserId,
    this.onMentionTap,
  });

  final String text;
  final String? formattedBody;

  /// Current user's Matrix ID — used to highlight self-mentions.
  final String? selfUserId;

  /// Called when a mention pill is tapped with the user's Matrix ID.
  final void Function(String userId)? onMentionTap;

  /// Extract mention mappings from formattedBody: displayName → userId.
  /// Keys are display names WITHOUT the `@` prefix.
  Map<String, String> _extractMentions() {
    final fb = formattedBody;
    if (fb == null) return {};
    final mentionRegex = RegExp(
      r'<a\s+href="https://matrix\.to/#/([@!#][^"]+)"[^>]*>([^<]+)</a>',
    );
    final mentions = <String, String>{};
    for (final match in mentionRegex.allMatches(fb)) {
      final userId = match.group(1)!;
      var displayName = match.group(2)!;
      // Strip leading @ — the pill text often includes it (e.g. "@Alice")
      if (displayName.startsWith('@')) {
        displayName = displayName.substring(1);
      }
      mentions[displayName] = Uri.decodeComponent(userId);
    }
    return mentions;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.gloam;
    // Check for code blocks first
    if (text.contains('```')) {
      return _buildWithCodeBlocks(colors, text);
    }

    final mentions = _extractMentions();
    return SelectableText.rich(
      _parseInline(colors, text, mentions: mentions),
      style: GoogleFonts.inter(
        fontSize: 14,
        color: colors.textPrimary,
        height: 1.5,
      ),
    );
  }

  Widget _buildWithCodeBlocks(GloamColorExtension colors, String input) {
    final mentions = _extractMentions();
    final parts = <Widget>[];
    final codeBlockRegex = RegExp(r'```(\w*)\n?([\s\S]*?)```');
    var lastEnd = 0;

    for (final match in codeBlockRegex.allMatches(input)) {
      // Text before code block
      if (match.start > lastEnd) {
        final before = input.substring(lastEnd, match.start).trim();
        if (before.isNotEmpty) {
          parts.add(SelectableText.rich(
            _parseInline(colors, before, mentions: mentions),
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
          _parseInline(colors, after, mentions: mentions),
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

  TextSpan _parseInline(
    GloamColorExtension colors,
    String input, {
    Map<String, String> mentions = const {},
  }) {
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
      // Plain text before this match — may contain mentions
      if (match.start > lastEnd) {
        _addTextWithMentions(
            spans, colors, input.substring(lastEnd, match.start), mentions);
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

    // Remaining plain text — may contain mentions
    if (lastEnd < input.length) {
      _addTextWithMentions(
          spans, colors, input.substring(lastEnd), mentions);
    }

    return TextSpan(children: spans);
  }

  /// Scans plain text for mention display names and renders them as styled spans.
  void _addTextWithMentions(
    List<InlineSpan> spans,
    GloamColorExtension colors,
    String text,
    Map<String, String> mentions,
  ) {
    if (mentions.isEmpty) {
      // No mentions from formattedBody — still highlight @room and bare @word patterns
      _addBareAtMentions(spans, colors, text);
      return;
    }

    // Build a regex that matches any known mention display name prefixed with @
    final escaped = mentions.keys.map(RegExp.escape).toList();
    // Also match @room
    escaped.add('room');
    final mentionRegex = RegExp(
      '(@(?:${escaped.join('|')}))(?=\\s|\$|[.,;:!?)])',
      caseSensitive: false,
    );

    var lastEnd = 0;
    for (final match in mentionRegex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }

      final mentionText = match.group(1)!;
      final displayName = mentionText.substring(1); // strip @
      final userId = mentions[displayName];
      final isSelf = userId == selfUserId;
      final isRoom = displayName.toLowerCase() == 'room';

      spans.add(_buildMentionSpan(
        colors, mentionText, userId, isSelf: isSelf, isRoom: isRoom,
      ));

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }
  }

  /// Fallback: style bare @word patterns when no formattedBody mentions exist.
  /// Catches @room and any @username that looks like a mention.
  void _addBareAtMentions(
    List<InlineSpan> spans,
    GloamColorExtension colors,
    String text,
  ) {
    // Match @word or @[bracketed name] at word boundary
    final bareRegex = RegExp(r'(@(?:\[[^\]]+\]|\w+))');
    var lastEnd = 0;
    for (final match in bareRegex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      final mentionText = match.group(1)!;
      final isRoom = mentionText.toLowerCase() == '@room';
      spans.add(_buildMentionSpan(
        colors, mentionText, null, isRoom: isRoom,
      ));
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    } else if (lastEnd == 0) {
      spans.add(TextSpan(text: text));
    }
  }

  /// Build a clickable mention span with pointer cursor.
  WidgetSpan _buildMentionSpan(
    GloamColorExtension colors,
    String mentionText,
    String? userId, {
    bool isSelf = false,
    bool isRoom = false,
  }) {
    final tappable = userId != null && onMentionTap != null && !isRoom;
    final color = isRoom ? colors.warning : colors.accentBright;

    Widget child = Text(
      mentionText,
      style: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: color,
        height: 1.5,
      ),
    );

    if (isSelf) {
      child = Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: colors.accent.withAlpha(38),
          borderRadius: BorderRadius.circular(3),
        ),
        child: child,
      );
    }

    if (tappable) {
      child = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => onMentionTap!(userId),
          child: child,
        ),
      );
    }

    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: child,
    );
  }
}
