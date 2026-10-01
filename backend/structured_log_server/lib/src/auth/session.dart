import 'package:drift/drift.dart';

import '../storage/database.dart';

/// Why a refresh token was revoked — stored in `refresh_tokens.revoked_reason`
/// as [wire].
///
/// The distinction exists for one decision: whether presenting the token again
/// is a theft signal (`TokenService.refreshTokenGrant`). Only [rotated] is.
/// A rotated token has a live successor, so a second presentation means two
/// parties hold the same session. Every other reason ended the session
/// deliberately, and the client presenting it afterwards is simply one that
/// has not heard yet — a device swept by somebody's password change renewing
/// on its own schedule. Treating that as theft revoked the whole account,
/// including the session that had just changed the password.
///
/// The others are distinguished from each other only for whoever reads the
/// table after an incident; nothing branches on which one it was.
enum RevocationReason {
  /// Spent by `grant_type=refresh_token`, which issued its successor.
  rotated('rotated'),

  /// `DELETE /v1/auth/token`.
  signedOut('signed_out'),

  /// Swept by the account's own `POST /v1/auth/change-password`.
  passwordChanged('password_changed'),

  /// Swept by a password an administrator set (`PATCH /v1/users/:id`).
  passwordReset('password_reset'),

  /// Swept by `POST /v1/users/:id/block`.
  blocked('blocked'),

  /// Swept by account deletion (`delete_user.dart`).
  deleted('deleted'),

  /// Swept by reuse detection itself. Not a theft signal on a second
  /// presentation either: the theft was already answered, and answering it
  /// again would only sign out whoever logged in afresh since.
  reuseDetected('reuse_detected');

  const RevocationReason(this.wire);

  final String wire;

  /// Whether presenting a token revoked with [wire] again means someone else
  /// holds the session.
  ///
  /// `null` — revoked before schema version 3 — answers yes, as every revoked
  /// token did then. The alternative would quietly drop reuse detection for
  /// tokens rotated shortly before an upgrade; keeping it costs, for at most
  /// one refresh-token lifetime, the old behaviour this enum exists to end.
  /// An unrecognised value also answers yes: this build refuses a database
  /// from a newer schema, so one can only be a writer that got it wrong, and
  /// the mistake should fail towards detection.
  static bool signalsReuse(String? wire) =>
      wire == null ||
      wire == rotated.wire ||
      !values.any((reason) => reason.wire == wire);
}

/// Revokes every currently-valid refresh token belonging to [userId], except
/// the one whose hash is [exceptTokenHash], and answers how many it revoked.
///
/// Sparing one is what `POST /v1/auth/change-password` needs: the account is
/// signing every other device out, and the device asking is not one of them.
/// It can only be named by hash, because that is all storage holds — the
/// caller presents the token itself and hashes it on the way in
/// (`hashing.dart`'s `hashToken`). A hash nobody holds spares nothing, which
/// is the safe way round: a caller that cannot identify its own session gets
/// the sweep applied to itself as well, rather than a sweep that quietly
/// skipped somebody.
///
/// Already-revoked rows are left exactly as they are — `revoked_at` is the
/// moment a token died, and a later sweep has no business rewriting it — and
/// are not counted. [reason] is recorded on each row it revokes.
Future<int> revokeRefreshTokensExcept(
  StructuredLogDatabase db,
  int userId, {
  required RevocationReason reason,
  String? exceptTokenHash,
}) {
  final statement = db.update(db.refreshTokens)
    ..where((t) {
      final live = t.userId.equals(userId) & t.revokedAt.isNull();
      // `equals(...).not()`, not `isNotValue(...)`: the latter builds drift's
      // null-safe `IS NOT <value>`, which SQLite accepts and PostgreSQL
      // refuses outright — there `IS NOT` takes only NULL/TRUE/FALSE, so the
      // statement dies as `42601: syntax error at or near "$3"` before it
      // compares anything. `token_hash` is NOT NULL, so the null-safety the
      // longer form buys is over a case the column cannot be in.
      return exceptTokenHash == null
          ? live
          : live & t.tokenHash.equals(exceptTokenHash).not();
    });
  return statement.write(
    RefreshTokensCompanion(
      revokedAt: Value(DateTime.now()),
      revokedReason: Value(reason.wire),
    ),
  );
}

/// Revokes every currently-valid refresh token belonging to [userId] —
/// the shared half of "kill this account's session" that blocking (4.5),
/// deletion (`delete_user.dart`) and an admin-set password (`PATCH
/// /v1/users/:id`) all need, alongside incrementing `token_version`
/// (`rbac/token_version.dart`) to invalidate access tokens already issued.
///
/// The no-survivors case of [revokeRefreshTokensExcept]. Kept as its own name
/// because that is what these three callers mean: none of them is the device
/// being spared, and none of them has a token to spare it by.
///
/// Reuse detection (`TokenService.refreshTokenGrant`) sweeps through here
/// too, as [RevocationReason.reuseDetected].
Future<void> revokeAllRefreshTokens(
  StructuredLogDatabase db,
  int userId, {
  required RevocationReason reason,
}) {
  return revokeRefreshTokensExcept(db, userId, reason: reason);
}
