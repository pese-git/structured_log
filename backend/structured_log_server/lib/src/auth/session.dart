import 'package:drift/drift.dart';

import '../storage/database.dart';

/// Revokes every currently-valid refresh token belonging to [userId] —
/// the shared half of "kill this account's session" that blocking (4.5),
/// deletion (`delete_user.dart`) and an admin-set password (`PATCH
/// /v1/users/:id`) all need, alongside incrementing `token_version`
/// (`rbac/token_version.dart`) to invalidate access tokens already issued.
///
/// Mirrors `TokenService._revokeAllForUser`, which stays private to that
/// file (it is reached only from `grant_type=refresh_token` reuse
/// detection) — this is the copy the rest of the server calls.
Future<void> revokeAllRefreshTokens(StructuredLogDatabase db, int userId) {
  return (db.update(db.refreshTokens)
        ..where((t) => t.userId.equals(userId) & t.revokedAt.isNull()))
      .write(RefreshTokensCompanion(revokedAt: Value(DateTime.now())));
}
