/// The access/refresh pair `POST /v1/auth/token` returns.
///
/// Deliberately not a `freezed` model: it is stored and read by the token
/// storage rather than parsed from an arbitrary response body, and keeping it
/// free of generated code means the storage layer compiles before codegen has
/// ever run.
class TokenPair {
  final String accessToken;
  final String refreshToken;

  const TokenPair({required this.accessToken, required this.refreshToken});

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
