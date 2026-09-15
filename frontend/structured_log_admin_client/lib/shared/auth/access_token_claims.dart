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
/// Lives here rather than in a JWT package: one claim, read once per screen,
/// against a dependency that would bring key handling with it.
String? usernameFromAccessToken(String accessToken) {
  final segments = accessToken.split('.');
  if (segments.length != 3) return null;
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
    );
    if (payload is! Map<String, dynamic>) return null;
    final username = payload['preferred_username'];
    return username is String && username.isNotEmpty ? username : null;
  } on FormatException {
    // A token this client cannot read is still a token the server may accept;
    // the name is the only thing lost.
    return null;
  }
}
