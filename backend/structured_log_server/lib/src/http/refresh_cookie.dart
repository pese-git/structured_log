/// The refresh token as a cookie the page's own scripts cannot read.
///
/// Why this exists at all: the admin client is a web build, and there
/// `flutter_secure_storage` is `localStorage` with the decrypting key beside
/// the ciphertext. `HttpOnly` is the one place a browser will hold a secret
/// that a script on the same origin cannot reach, and the refresh token — 30
/// days, and enough on its own to reissue the session — is the credential
/// worth putting there (`add-refresh-token-cookie/design.md`).
///
/// The cookie never replaces the token in the response body. A caller that
/// keeps no cookies — curl, an operator's script, `packages/e2e` on the Dart
/// VM — reads the body exactly as before and never learns this module exists.
library;

/// Which callers get a `Set-Cookie` (`specs/log-server-config`).
enum RefreshCookieMode { auto, on, off }

/// The configured string, or [RefreshCookieMode.off] when nothing configured
/// it.
///
/// `off` for `null` rather than the operator-facing default `auto`: a handler
/// built without a `ServerConfig` is a route test, and `HttpSettings` promises
/// such a handler behaves as it did before the setting existed.
RefreshCookieMode refreshCookieModeOf(String? configured) =>
    switch (configured) {
      'auto' => RefreshCookieMode.auto,
      'on' => RefreshCookieMode.on,
      _ => RefreshCookieMode.off,
    };

/// The cookie's name. Prefixed like the rest of this server's externally
/// visible names, and distinct enough that [refreshCookieOf] matching it
/// exactly cannot collide with an application's own.
const refreshCookieName = 'structured_log_refresh';

/// The path both endpoints that need the cookie live under.
///
/// Deliberately `/v1/auth`, not `/v1/auth/token`: `POST /v1/auth/change-password`
/// identifies the caller's own session by the same token, and a narrower path
/// would leave it without one — keeping alive the client-side workaround this
/// change exists to remove.
const _cookiePath = '/v1/auth';

/// `SameSite=Strict` over `Lax`: nothing about this cookie should travel on a
/// navigation started by another site. `Secure` means a browser drops it over
/// plain HTTP — documented as the cost of turning this on
/// (`docs/operations/configuration.md`).
const _attributes = 'HttpOnly; Secure; SameSite=Strict; Path=$_cookiePath';

/// The `Set-Cookie` value carrying [token] for [maxAge].
String buildRefreshCookie(String token, {required Duration maxAge}) =>
    '$refreshCookieName=$token; $_attributes; Max-Age=${maxAge.inSeconds}';

/// The `Set-Cookie` value that removes it.
///
/// Same attributes, because a browser matches the cookie to delete by
/// name/path/domain — a `Max-Age=0` on a different path leaves the live one
/// exactly where it was.
String clearRefreshCookie() => '$refreshCookieName=; $_attributes; Max-Age=0';

/// The refresh token in a request's `Cookie` header, or `null`.
///
/// An empty value reads as `null` rather than as an empty token: a cleared
/// cookie comes back as `name=` until the browser drops it, and treating that
/// as a token would send the empty string to the hash lookup and answer
/// `invalid_grant` where `invalid_request` is what the caller deserves.
String? refreshCookieOf(String? header) {
  if (header == null || header.isEmpty) return null;
  for (final pair in header.split(';')) {
    final separator = pair.indexOf('=');
    if (separator < 0) continue;
    if (pair.substring(0, separator).trim() != refreshCookieName) continue;
    final value = pair.substring(separator + 1).trim();
    return value.isEmpty ? null : value;
  }
  return null;
}

/// Whether this response should carry the cookie.
///
/// `auto` asks one question: has the operator listed this `Origin` under
/// `cors-allowed-origins`? Listing it there *is* the declaration that it is
/// not the API's own origin, and `SameSite=Strict` would keep the cookie from
/// travelling there anyway.
///
/// What it deliberately does not do is compare the `Origin` to the server's
/// own host. Behind a reverse proxy the scheme and host the server sees are
/// not the ones the browser sent, so the comparison would have to trust
/// `X-Forwarded-*` — a second piece of proxy-dependent logic beside
/// `trustedProxyHops`, and another way to be wrong for free. Note also that a
/// same-origin `POST` carries an `Origin` header (Fetch sends one for
/// everything but `GET`/`HEAD`), so the header's presence says nothing by
/// itself; only its presence in the list does.
bool shouldSetRefreshCookie(
  RefreshCookieMode mode, {
  required String? origin,
  required Set<String> allowedOrigins,
}) => switch (mode) {
  RefreshCookieMode.off => false,
  RefreshCookieMode.on => true,
  RefreshCookieMode.auto => origin == null || !allowedOrigins.contains(origin),
};
