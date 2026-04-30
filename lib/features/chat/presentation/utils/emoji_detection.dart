/// Emoji detection for jumbo-render and inline-bump treatments.
///
/// Identifies whether a chat message is "emoji-only" (per Slack/iMessage
/// pattern — only emoji graphemes + whitespace, no other text) and counts
/// the emoji graphemes so the renderer can pick a jumbo size.
///
/// Counts both unicode emoji and Matrix custom emoji (`<img data-mx-emoticon>`
/// in formatted_body HTML).
library;

import 'package:characters/characters.dart';

/// Result of classifying a message body for emoji-rendering decisions.
class EmojiClassification {
  const EmojiClassification({
    required this.isEmojiOnly,
    required this.emojiCount,
  });

  final bool isEmojiOnly;
  final int emojiCount;

  static const empty = EmojiClassification(isEmojiOnly: false, emojiCount: 0);
}

/// Inspects the message and decides whether it should jumbo-render.
///
/// Prefers [formattedHtml] when present (so we can count `<img data-mx-emoticon>`
/// custom emoji), falling back to [plainText].
EmojiClassification classifyMessage({
  String? plainText,
  String? formattedHtml,
}) {
  if (formattedHtml != null && formattedHtml.isNotEmpty) {
    return _classifyHtml(formattedHtml);
  }
  if (plainText != null && plainText.isNotEmpty) {
    return _classifyPlain(plainText);
  }
  return EmojiClassification.empty;
}

/// Matches `<img data-mx-emoticon ...>` (Matrix custom emoji) — order of
/// attributes is irrelevant; presence of `data-mx-emoticon` is the signal.
final _customEmojiRegex = RegExp(
  r'<img\b[^>]*\bdata-mx-emoticon\b[^>]*>',
  caseSensitive: false,
);

/// Matches any HTML tag for stripping after we've counted custom emoji.
final _anyTagRegex = RegExp(r'<[^>]+>');

/// Decodes a small set of common HTML entities so things like &amp;
/// don't get counted as non-emoji text noise.
String _decodeEntities(String s) {
  return s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ');
}

EmojiClassification _classifyHtml(String html) {
  final customCount = _customEmojiRegex.allMatches(html).length;
  // Strip all tags (including the custom emoji ones we already counted).
  final stripped = _decodeEntities(html.replaceAll(_anyTagRegex, ''));
  final plain = _classifyPlain(stripped);

  final totalCount = plain.emojiCount + customCount;
  // Plain side considered emoji-only iff its non-whitespace was all emoji.
  // If there are no plain emojis but there are custom ones, we still need
  // the plain text to be empty/whitespace-only to call the message emoji-only.
  final plainSideClean = plain.isEmojiOnly ||
      stripped.characters.where((g) => g.trim().isNotEmpty).isEmpty;

  return EmojiClassification(
    isEmojiOnly: plainSideClean && totalCount > 0,
    emojiCount: totalCount,
  );
}

EmojiClassification _classifyPlain(String text) {
  var emojiCount = 0;
  var nonEmojiNonWhitespace = 0;
  for (final grapheme in text.characters) {
    if (grapheme.trim().isEmpty) continue;
    if (_isEmojiGrapheme(grapheme)) {
      emojiCount++;
    } else {
      nonEmojiNonWhitespace++;
    }
  }
  return EmojiClassification(
    isEmojiOnly: nonEmojiNonWhitespace == 0 && emojiCount > 0,
    emojiCount: emojiCount,
  );
}

/// Returns true if the grapheme cluster contains at least one codepoint
/// commonly used to render emoji glyphs.
///
/// Pragmatic ranges — covers the vast majority of emojis users send. Skips
/// the rare property-only edge cases (dingbats with text default presentation
/// without VS-16, etc.) in favor of simplicity.
bool _isEmojiGrapheme(String grapheme) {
  for (final rune in grapheme.runes) {
    // Variation selector — forces emoji presentation on otherwise-text chars.
    if (rune == 0xFE0F) return true;
    // Combining keycap (e.g. 1️⃣).
    if (rune == 0x20E3) return true;
    // Zero-width joiner (joins emoji graphemes like 👨‍👩‍👧) only counts as
    // emoji if paired with an emoji elsewhere in the cluster — handled by
    // the surrounding ranges below.
    // Misc technical (⌘, ⏰).
    if (rune >= 0x2300 && rune <= 0x23FF) return true;
    // Misc symbols (☀, ☂, ★).
    if (rune >= 0x2600 && rune <= 0x26FF) return true;
    // Dingbats (✂, ✈, ✨).
    if (rune >= 0x2700 && rune <= 0x27BF) return true;
    // Misc symbols and arrows (⬛, ⬜, ⭐).
    if (rune >= 0x2B00 && rune <= 0x2BFF) return true;
    // Enclosed alphanumeric supplement (regional indicators / flag halves).
    if (rune >= 0x1F100 && rune <= 0x1F1FF) return true;
    // Big block: emoticons, transport, supplemental symbols, faces, etc.
    if (rune >= 0x1F000 && rune <= 0x1FFFF) return true;
  }
  return false;
}

/// True if a single grapheme should be rendered with the inline emoji bump
/// when surrounded by normal text. Exported for the TextSpan walker.
bool isEmojiGrapheme(String grapheme) => _isEmojiGrapheme(grapheme);
