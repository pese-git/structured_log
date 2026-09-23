import 'dart:convert';

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

/// The shortest signing secret the server will start with, in UTF-8 bytes.
///
/// Access tokens are signed with HMAC-SHA256, whose output is 256 bits, and a
/// key shorter than that bounds the signature's strength by the key rather
/// than by the algorithm — at which point a single captured token is enough to
/// search for the key offline and then mint an `admin` one. Counted in bytes,
/// not characters, because bytes are what the HMAC is keyed with and what
/// entropy is measured in.
///
/// Not configurable on purpose: a floor an operator can lower is a floor that
/// gets lowered.
const minJwtSecretBytes = 32;

/// What is wrong with [secret] as the value of `jwt-secret`, or `null` if
/// nothing is. Shaped for `ParamSpec.validator`, the same way
/// `passwordPolicyMessage` is (`auth/hashing.dart`).
///
/// The offending value never appears in the returned sentence. The resolver
/// prints it to the console and it can end up in a deployment log or a support
/// ticket; a message that quoted the secret would carry it there.
String? jwtSecretPolicyMessage(String secret) {
  if (utf8.encode(secret).length >= minJwtSecretBytes) return null;
  return 'The signing secret must be at least $minJwtSecretBytes bytes '
      'in UTF-8. Generate one with `openssl rand -base64 48`.';
}
