import 'dart:convert';
import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';

/// Hashes a user's chosen [password] with `bcrypt` — an adaptive,
/// deliberately slow algorithm, appropriate for a low-entropy, human-chosen
/// secret (`design.md` decision 11).
String hashPassword(String password) {
  return BCrypt.hashpw(password, BCrypt.gensalt());
}

/// Returns whether [password] matches the previously hashed [hash]
/// (`hashPassword`).
bool verifyPassword(String password, String hash) {
  return BCrypt.checkpw(password, hash);
}

/// Generates a high-entropy, cryptographically random secret suitable for a
/// project secret key or a refresh token — never remembered by a human, so
/// no dictionary-resistance is needed (`design.md` decision 11). Encoded as
/// URL-safe base64 (no padding) so it's easy to embed in headers/URLs.
String generateRandomToken({int bytes = 32}) {
  final random = Random.secure();
  final values = List<int>.generate(bytes, (_) => random.nextInt(256));
  return base64UrlEncode(values).replaceAll('=', '');
}

/// Hashes a high-entropy random secret (project secret key, refresh token)
/// with plain SHA-256 — unlike [hashPassword], these values aren't
/// vulnerable to offline dictionary attacks, so a fast cryptographic hash is
/// enough to keep the plaintext out of storage (`design.md` decision 11).
String hashToken(String token) {
  return sha256.convert(utf8.encode(token)).toString();
}
