/// Parsed Matrix ID input. When [homeserver] is null, the caller should
/// fall back to a default (e.g. `matrix.org`).
class ParsedMxid {
  const ParsedMxid({required this.localpart, this.homeserver});
  final String localpart;
  final String? homeserver;

  bool get hasHomeserver => homeserver != null;
  bool get isValid => localpart.isNotEmpty;
}

/// Parse a user-supplied Matrix ID into localpart + homeserver.
///
/// Accepts (in preference order):
/// - `@localpart:server.xyz` — canonical Matrix form
/// - `localpart:server.xyz` — Matrix form without leading `@`
/// - `localpart@server.xyz` — email-style (MSC4143)
/// - `localpart` — no separator; [homeserver] is null so the caller can
///   apply a default like `matrix.org`
///
/// Whitespace is trimmed. The server portion is lowercased (DNS is
/// case-insensitive). Localpart case is preserved — Matrix localparts are
/// case-sensitive per spec.
///
/// If the input is empty or starts with a separator (no localpart), the
/// returned [ParsedMxid] has [isValid] == false.
ParsedMxid parseMxid(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const ParsedMxid(localpart: '');

  final stripped =
      trimmed.startsWith('@') ? trimmed.substring(1) : trimmed;
  if (stripped.isEmpty || stripped.startsWith(':') || stripped.startsWith('@')) {
    return const ParsedMxid(localpart: '');
  }

  // Prefer `:` as the separator (true MXID form). lastIndexOf so multi-@
  // localparts like `foo@bar:server.com` survive.
  final colonIdx = stripped.lastIndexOf(':');
  if (colonIdx > 0 && colonIdx < stripped.length - 1) {
    return ParsedMxid(
      localpart: stripped.substring(0, colonIdx),
      homeserver: stripped.substring(colonIdx + 1).toLowerCase(),
    );
  }

  // Email-style fallback.
  final atIdx = stripped.lastIndexOf('@');
  if (atIdx > 0 && atIdx < stripped.length - 1) {
    return ParsedMxid(
      localpart: stripped.substring(0, atIdx),
      homeserver: stripped.substring(atIdx + 1).toLowerCase(),
    );
  }

  return ParsedMxid(localpart: stripped);
}
