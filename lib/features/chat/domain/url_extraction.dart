final _urlRegex = RegExp(
  r'https?://[^\s<>\[\]()]+',
  caseSensitive: false,
);

Iterable<String> extractUrls(String body) sync* {
  for (final match in _urlRegex.allMatches(body)) {
    yield match.group(0)!;
  }
}
