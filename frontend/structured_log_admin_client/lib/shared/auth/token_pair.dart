/// The access/refresh pair `POST /v1/auth/token` returns.
///
/// Deliberately not a `freezed` model: it is stored and read by the token
/// storage rather than parsed from an arbitrary response body, and keeping it
/// free of generated code means the storage layer compiles before codegen has
/// ever run.
class TokenPair {
  final String accessToken;

  /// `null` when the server put the refresh token in an `HttpOnly` cookie —
  /// the browser holds it, and this page cannot read it even to store it.
  /// That is the point: the 30-day credential stops being reachable from
  /// script on this origin (`add-refresh-token-cookie`).
  ///
  /// So `null` here does not mean "no session". It means the half of the
  /// session that renews it is kept somewhere better, and a renewal sends no
  /// token at all — the cookie travels on its own.
  final String? refreshToken;

  const TokenPair({required this.accessToken, this.refreshToken});

  /// The pair to keep, out of what `POST /v1/auth/token` answered.
  ///
  /// The body carries `refresh_token` in both modes — that is what keeps
  /// non-browser callers working — so the client has to be told whether to
  /// hold on to it. [cookieSet] is the server's `refresh_token_cookie_set`,
  /// and it is the only thing that decides: the client is told the mode
  /// rather than configured with it, so the two cannot disagree
  /// (`add-refresh-token-cookie/design.md`, decision 2).
  ///
  /// Keeping the copy anyway would leave the change achieving nothing: the
  /// token would sit in browser storage exactly as before, cookie or no
  /// cookie.
  const TokenPair.fromGrant({
    required this.accessToken,
    required String refreshToken,
    required bool cookieSet,
  }) : refreshToken = cookieSet ? null : refreshToken;

  @override
  bool operator ==(Object other) =>
      other is TokenPair &&
      other.accessToken == accessToken &&
      other.refreshToken == refreshToken;

  @override
  int get hashCode => Object.hash(accessToken, refreshToken);

  /// Neither token is ever printed: a log line that carried one would hand a
  /// session to whoever reads the log (`log-server-audit`, decision 48).
  @override
  String toString() => 'TokenPair(access: <redacted>, refresh: <redacted>)';
}
