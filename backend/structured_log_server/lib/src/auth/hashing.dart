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

/// Prefix every project secret key carries, distinguishing it from an access
/// token in the `Authorization: Bearer <...>` header both schemes share
/// (`log-server-auth`). A JWT is base64url of a JSON object, so it always
/// starts with `eyJ` — the two can never collide.
///
/// Secondary benefit, not the reason for it: a leaked key is recognizable on
/// sight and to secret scanners, the way `ghp_`/`sk-`/`AKIA` are.
const projectSecretKeyPrefix = 'slk_';

/// Generates a project secret key: [projectSecretKeyPrefix] followed by
/// [generateRandomToken]'s output. The prefix is part of the key's value —
/// clients send it verbatim, and [hashToken] hashes it along with the rest,
/// so nothing needs to strip it before lookup.
///
/// Refresh tokens keep using bare [generateRandomToken]: they never travel in
/// `Authorization` (they're a form field of `POST /v1/auth/token`), so there
/// is nothing to tell them apart from.
String generateProjectSecretKey() {
  return '$projectSecretKeyPrefix${generateRandomToken()}';
}

/// Hashes a high-entropy random secret (project secret key, refresh token)
/// with plain SHA-256 — unlike [hashPassword], these values aren't
/// vulnerable to offline dictionary attacks, so a fast cryptographic hash is
/// enough to keep the plaintext out of storage (`design.md` decision 11).
String hashToken(String token) {
  return sha256.convert(utf8.encode(token)).toString();
}
