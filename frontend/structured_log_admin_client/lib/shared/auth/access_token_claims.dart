import 'dart:convert';

/// The `preferred_username` an access token carries, or `null` if it carries
/// none.
///
/// **This is not verification.** The signature is not checked and must not be
/// — the server is the only thing that may decide whether a token is good, and
/// this client has no key to check it with. The claim is read for one purpose:
/// putting a name on the screen that says who is signed in. A forged token
/// would show a wrong name to whoever forged it, and nothing else.
///
/// Lives here rather than in a JWT package: two claims, read once per screen,
/// against a dependency that would bring key handling with it.
String? usernameFromAccessToken(String accessToken) {
  final payload = _payloadOf(accessToken);
  final username = payload?['preferred_username'];
  return username is String && username.isNotEmpty ? username : null;
}

/// Whether the token claims `admin` at global scope.
///
/// **This decides what to offer, never what to allow**, and the difference is
/// the whole reason reading an unverified claim is legitimate here. The audit
/// section is hidden from a reader whose token does not carry this, so the
/// application does not advertise a screen that would answer 403; the authority
/// is the server, which re-derives the caller's roles on every request and
/// refuses regardless of what the token says
/// (`specs/admin-client-audit-log`).
///
/// A forged token therefore buys a nav item and an error message.
///
/// One consequence worth stating: the claim is a snapshot taken when the token
/// was issued. A role revoked mid-session leaves the menu item in place until
/// the access token is renewed — the screen behind it starts answering 403
/// immediately, which is the part that matters.
bool isGlobalAdminFromAccessToken(String accessToken) {
  final roles = _payloadOf(accessToken)?['roles'];
  if (roles is! List) return false;

  return roles.any(
    (role) =>
        role is Map &&
        role['role'] == 'admin' &&
        role['scope_type'] == 'global',
  );
}

/// The token's payload, or `null` when this client cannot read it.
///
/// A token this client cannot parse is still a token the server may accept, so
/// nothing throws: what is lost is a name on a screen and a menu item, not the
/// session.
Map<String, dynamic>? _payloadOf(String accessToken) {
  final segments = accessToken.split('.');
  if (segments.length != 3) return null;
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
    );
    return payload is Map<String, dynamic> ? payload : null;
  } on FormatException {
    return null;
  }
}
