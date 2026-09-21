import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:drift/drift.dart';
import 'package:fpdart/fpdart.dart';

import '../audit/audit_action.dart';
import '../audit/audit_writer.dart';
import '../storage/database.dart';
import 'claims.dart';
import 'hashing.dart';

enum TokenErrorCode { invalidGrant, invalidRequest, unsupportedGrantType }

/// Why a `grant_type=password` attempt was refused — for the audit record, and
/// for nothing else.
///
/// **This never leaves the service.** Every one of these gets the same
/// `invalid_grant` with the same description, because saying which applied
/// would answer questions the caller did not earn the right to ask: whether an
/// account exists, whether it is blocked, whether it was deleted.
/// `TokenError.reason` is rendered onto the wire, so the reason deliberately
/// does not travel in it — one careless line there turns this endpoint into an
/// account-enumeration oracle.
enum LoginFailure {
  unknownUser('unknown_user'),
  invalidPassword('invalid_password'),
  blocked('blocked'),
  deleted('deleted');

  const LoginFailure(this.wire);

  final String wire;
}

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
  final AuditWriter _audit;
  final SecretKey _signingKey;
  final String _issuer;
  final Duration accessTokenTtl;
  final Duration refreshTokenTtl;

  TokenService(
    this._db,
    this._claims,
    this._audit, {
    required String signingSecret,
    required String issuer,
    this.accessTokenTtl = const Duration(minutes: 15),
    this.refreshTokenTtl = const Duration(days: 30),
  }) : _signingKey = SecretKey(signingSecret),
       _issuer = issuer;

  /// The audit record is written here rather than by the route handler, and
  /// that is why [clientIp]/[userAgent] are parameters: the handler has
  /// neither the user id — the actor of a success and of a known-account
  /// failure — nor the reason, and the only way to hand it the reason would be
  /// through `TokenError`, which goes on the wire.
  Future<Either<TokenError, TokenPair>> passwordGrant({
    required String username,
    required String password,
    required String clientIp,
    String? userAgent,
  }) async {
    final user = await (_db.select(
      _db.users,
    )..where((t) => t.username.equals(username))).getSingleOrNull();

    // bcrypt runs whatever the account's state, against a dummy hash when there
    // is no usable one: skipping it for an unknown, blocked or deleted account
    // would make the response time say which case this was.
    final passwordOk = await verifyPasswordAsync(
      password,
      user?.passwordHash ?? await dummyPasswordHash,
    );
    final failure = _reasonToRefuse(user, passwordOk);
    if (failure != null) {
      await _audit.write(
        action: AuditAction.authLoginFailed,
        targetType: AuditTargetType.user,
        // Null for an account that does not exist: the honest record of an
        // attempt with nobody behind it.
        actorUserId: user?.id,
        targetId: user?.id,
        metadata: {
          'reason': failure.wire,
          'client_ip': clientIp,
          'user_agent': userAgent,
          // The submitted string is never stored. A username matching no
          // account is regularly a password typed into the wrong box, and the
          // journal outlives the mistake (`specs/log-server-audit`).
          if (failure == LoginFailure.unknownUser) 'unknown_user': true,
        },
      );
      return left(const TokenError(TokenErrorCode.invalidGrant));
    }

    final pair = await _issuePair(user!.id, user.username);
    await _audit.write(
      action: AuditAction.authLoginSucceeded,
      targetType: AuditTargetType.user,
      actorUserId: user.id,
      targetId: user.id,
      metadata: {'client_ip': clientIp, 'user_agent': userAgent},
    );
    return right(pair);
  }

  /// Which refusal applies, or `null` when the credentials are good.
  ///
  /// Split out of the one collapsed condition this used to be, because the
  /// audit record has to say which — and splitting it surfaced that
  /// `deleted_at` was never consulted at all. Nothing sets that column yet, so
  /// the branch is unreachable today. It is here because the alternative is
  /// remembering to add it exactly when account deletion lands, at which point
  /// a row with `deleted_at` set and `is_active` still true would
  /// authenticate.
  static LoginFailure? _reasonToRefuse(User? user, bool passwordOk) {
    if (user == null) return LoginFailure.unknownUser;
    if (user.deletedAt != null) return LoginFailure.deleted;
    if (!user.isActive) return LoginFailure.blocked;
    if (!passwordOk) return LoginFailure.invalidPassword;
    return null;
  }

  /// Deliberately silent in the audit log. A client renewing its session is
  /// not an event — it is the same session continuing, and one record per
  /// renewal would bury the logins that are (`specs/log-server-audit`).
  Future<Either<TokenError, TokenPair>> refreshTokenGrant(
    String presentedToken,
  ) async {
    final hash = hashToken(presentedToken);
    final stored = await (_db.select(
      _db.refreshTokens,
    )..where((t) => t.tokenHash.equals(hash))).getSingleOrNull();

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
    )..where((t) => t.id.equals(stored.userId))).getSingle();
    if (!user.isActive) {
      return left(const TokenError(TokenErrorCode.invalidGrant));
    }

    // Claim the token and issue its successor as one step. Checking
    // `revoked_at` above and revoking here as two steps leaves a window in
    // which two concurrent requests with the same token both pass the check and
    // both get a live pair — two descendants of one token, which is exactly
    // what reuse detection exists to prevent. The conditional update is what
    // decides who wins; the transaction keeps the winner's new token from being
    // written after the loser's sweep below.
    final pair = await _db.transaction(() async {
      final claimed =
          await (_db.update(_db.refreshTokens)
                ..where((t) => t.id.equals(stored.id) & t.revokedAt.isNull()))
              .write(RefreshTokensCompanion(revokedAt: Value(DateTime.now())));
      if (claimed == 0) return null;
      return _issuePair(user.id, user.username);
    });
    if (pair == null) {
      // Somebody else presented this token first: the same signal as
      // presenting one already revoked.
      await _revokeAllForUser(stored.userId);
      return left(const TokenError(TokenErrorCode.invalidGrant));
    }
    return right(pair);
  }

  /// `DELETE /v1/auth/token` — always succeeds regardless of whether
  /// [presentedToken] was valid, already revoked, or never existed
  /// (RFC 7009 §2.2, anti-enumeration).
  /// The audit record does not follow the response: a token that was never
  /// live is not someone logging out, and recording one would put an event in
  /// the journal that never happened. What keeps a caller from learning which
  /// case they hit is the sameness of the *response*, not of the journal
  /// (`specs/log-server-audit`).
  Future<void> revoke(
    String presentedToken, {
    required String clientIp,
    String? userAgent,
  }) async {
    final hash = hashToken(presentedToken);
    final stored =
        await (_db.select(_db.refreshTokens)
              ..where((t) => t.tokenHash.equals(hash) & t.revokedAt.isNull()))
            .getSingleOrNull();
    if (stored == null) return;

    await (_db.update(_db.refreshTokens)..where((t) => t.id.equals(stored.id)))
        .write(RefreshTokensCompanion(revokedAt: Value(DateTime.now())));

    await _audit.write(
      action: AuditAction.authLoggedOut,
      targetType: AuditTargetType.user,
      actorUserId: stored.userId,
      targetId: stored.userId,
      metadata: {'client_ip': clientIp, 'user_agent': userAgent},
    );
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
    await _db
        .into(_db.refreshTokens)
        .insert(
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
    final jwt = JWT(
      {
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
      jwtId: generateRandomToken(bytes: 16),
    );

    return jwt.sign(_signingKey, expiresIn: accessTokenTtl);
  }
}
