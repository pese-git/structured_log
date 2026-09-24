import 'package:drift/drift.dart';

import '../storage/database.dart';

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
/// are not counted.
Future<int> revokeRefreshTokensExcept(
  StructuredLogDatabase db,
  int userId, {
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
    RefreshTokensCompanion(revokedAt: Value(DateTime.now())),
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
/// Mirrors `TokenService._revokeAllForUser`, which stays private to that
/// file (it is reached only from `grant_type=refresh_token` reuse
/// detection) — this is the copy the rest of the server calls.
Future<void> revokeAllRefreshTokens(StructuredLogDatabase db, int userId) {
  return revokeRefreshTokensExcept(db, userId);
}
