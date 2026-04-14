/// Escapes `$` characters outside fenced code blocks and inline code spans,
/// preventing the Matrix SDK's inline-LaTeX syntax (`$…$`) from matching.
/// The user-visible result is that `$` always renders as literal text.
///
/// Inside fenced (```…```) and inline (`…`) code, `$` is left alone —
/// backslash-escapes aren't processed there, so escaping would show a stray
/// backslash.
String escapeLatexDollars(String text) {
  final buf = StringBuffer();
  var i = 0;
  while (i < text.length) {
    final ch = text[i];

    // Fenced code block: ```…```
    if (ch == '`' && text.startsWith('```', i)) {
      final end = text.indexOf('```', i + 3);
      final stop = end == -1 ? text.length : end + 3;
      buf.write(text.substring(i, stop));
      i = stop;
      continue;
    }

    // Inline code: `…` (or ``…``, with N>=1 matching backticks).
    if (ch == '`') {
      var n = 0;
      while (i + n < text.length && text[i + n] == '`') {
        n++;
      }
      final closing = '`' * n;
      final end = text.indexOf(closing, i + n);
      final stop = end == -1 ? i + n : end + n;
      buf.write(text.substring(i, stop));
      i = stop;
      continue;
    }

    // Preserve any existing backslash-escape verbatim (don't double-escape).
    if (ch == r'\' && i + 1 < text.length) {
      buf.write(text.substring(i, i + 2));
      i += 2;
      continue;
    }

    if (ch == r'$') {
      buf.write(r'\$');
      i++;
      continue;
    }

    buf.write(ch);
    i++;
  }
  return buf.toString();
}
