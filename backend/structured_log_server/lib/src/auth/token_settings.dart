/// What signs and names the tokens this server issues and accepts.
///
/// A value object rather than two `String`s so the container can bind it by
/// type: `resolve<String>()` would need a name for each, and a name is a string
/// nobody checks.
class TokenSettings {
  final String signingSecret;
  final String issuer;

  const TokenSettings({required this.signingSecret, required this.issuer});
}
