import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';

import '../storage/database.dart';
import 'claims.dart';
import 'hashing.dart';

enum TokenErrorCode { invalidGrant, invalidRequest, unsupportedGrantType }

/// An RFC 6749 §5.2-shaped failure from `POST`/`DELETE /v1/auth/token`.
/// [reason] carries the one non-standard extension this API defines on top
/// of RFC 6749 (`email_not_verified` — not produced yet in Stage 1, which
/// has no email-verification flow).
class TokenError {
  final TokenErrorCode code;
  final String? reason;

  const TokenError(this.code, {this.reason});
}

/// A freshly issued (or rotated) access/refresh token pair
/// (`log-server-auth`, RFC 6749 §5.1).
class TokenPair {
  final String accessToken;
  final String refreshToken;
  final Duration accessTokenTtl;
  final Duration refreshTokenTtl;

  const TokenPair({
    required this.accessToken,
    required this.refreshToken,
    required this.accessTokenTtl,
    required this.refreshTokenTtl,
  });
}

/// Implements `POST`/`DELETE /v1/auth/token`'s business logic
/// (`log-server-auth`) independent of HTTP framing — the route handler
/// parses the form-encoded request and renders [TokenPair]/[TokenError]
/// into the wire shapes RFC 6749 requires.
///
/// Stage 1 slice: `grant_type=password` skips the `email_verified_at`
/// check (`log-server-email-verification` isn't built yet — no user in
/// Stage 1 has an email in the first place, `design.md` "Delivery Phases").
class TokenService {
  final StructuredLogDatabase _db;
  final ClaimsResolver _claims;
  final SecretKey _signingKey;
  final String _issuer;
  final Duration accessTokenTtl;
  final Duration refreshTokenTtl;

  TokenService(
    this._db,
    this._claims, {
    required String signingSecret,
    required String issuer,
    this.accessTokenTtl = const Duration(minutes: 15),
    this.refreshTokenTtl = const Duration(days: 30),
  })  : _signingKey = SecretKey(signingSecret),
        _issuer = issuer;

  Future<Either<TokenError, TokenPair>> passwordGrant({
    required String username,
    required String password,
  }) async {
    final user = await (_db.select(
      _db.users,
    )..where((t) => t.username.equals(username)))
        .getSingleOrNull();

    if (user == null ||
        !user.isActive ||
        !verifyPassword(password, user.passwordHash)) {
      return left(const TokenError(TokenErrorCode.invalidGrant));
    }

    return right(await _issuePair(user.id, user.username));
  }

  Future<Either<TokenError, TokenPair>> refreshTokenGrant(
    String presentedToken,
  ) async {
    final hash = hashToken(presentedToken);
    final stored = await (_db.select(
      _db.refreshTokens,
    )..where((t) => t.tokenHash.equals(hash)))
        .getSingleOrNull();

    if (stored == null) {
      return left(const TokenError(TokenErrorCode.invalidGrant));
    }

    if (stored.revokedAt != null) {
      // Reuse of an already-revoked refresh token: treat as a compromise
      // signal and revoke the whole chain, not just this one token.
      await _revokeAllForUser(stored.userId);
      return left(const TokenError(TokenErrorCode.invalidGrant));
    }

    if (stored.expiresAt.isBefore(DateTime.now())) {
      return left(const TokenError(TokenErrorCode.invalidGrant));
    }

    final user = await (_db.select(
      _db.users,
    )..where((t) => t.id.equals(stored.userId)))
        .getSingle();
    if (!user.isActive) {
      return left(const TokenError(TokenErrorCode.invalidGrant));
    }

    await (_db.update(
      _db.refreshTokens,
    )..where((t) => t.id.equals(stored.id)))
        .write(
      RefreshTokensCompanion(revokedAt: Value(DateTime.now())),
    );

    return right(await _issuePair(user.id, user.username));
  }

  /// `DELETE /v1/auth/token` — always succeeds regardless of whether
  /// [presentedToken] was valid, already revoked, or never existed
  /// (RFC 7009 §2.2, anti-enumeration).
  Future<void> revoke(String presentedToken) async {
    final hash = hashToken(presentedToken);
    await (_db.update(_db.refreshTokens)
          ..where((t) => t.tokenHash.equals(hash) & t.revokedAt.isNull()))
        .write(RefreshTokensCompanion(revokedAt: Value(DateTime.now())));
  }

  Future<void> _revokeAllForUser(int userId) {
    return (_db.update(_db.refreshTokens)
          ..where((t) => t.userId.equals(userId) & t.revokedAt.isNull()))
        .write(RefreshTokensCompanion(revokedAt: Value(DateTime.now())));
  }

  Future<TokenPair> _issuePair(int userId, String username) async {
    final claims = await _claims.resolve(userId);
    final accessToken = _signAccessToken(userId, username, claims);

    final refreshTokenPlain = generateRandomToken();
    await _db.into(_db.refreshTokens).insert(
          RefreshTokensCompanion.insert(
            userId: userId,
            tokenHash: hashToken(refreshTokenPlain),
            expiresAt: DateTime.now().add(refreshTokenTtl),
          ),
        );

    return TokenPair(
      accessToken: accessToken,
      refreshToken: refreshTokenPlain,
      accessTokenTtl: accessTokenTtl,
      refreshTokenTtl: refreshTokenTtl,
    );
  }

  String _signAccessToken(int userId, String username, TokenClaims claims) {
    final jwt = JWT({
      'preferred_username': username,
      'tv': claims.tokenVersion,
      'roles': claims.roles
          .map(
            (r) => {
              'role': r.role.name,
              'scope_type': r.scopeType.name,
              'scope_id': r.scopeId,
            },
          )
          .toList(),
    },
        subject: '$userId',
        issuer: _issuer,
        jwtId: generateRandomToken(bytes: 16));

    return jwt.sign(_signingKey, expiresIn: accessTokenTtl);
  }
}
