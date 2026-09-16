import 'package:drift/drift.dart';

import '../storage/database.dart';

/// Atomically increments `User.token_version` for [userId] — the mechanism
/// `log-server-auth` relies on for immediate revocation of already-issued
/// access tokens (their `tv` claim stops matching). Called on any event
/// that must invalidate a user's outstanding tokens: direct
/// `RoleAssignment`/team-membership changes, deactivation, password change.
///
/// Only the single-user case is implemented so far — Stage 1 has no
/// endpoint yet that mutates a team-scoped `RoleAssignment` or a team's
/// membership (`design.md` "Delivery Phases"), so the cascading bulk update
/// for every current member of a team has no caller yet and isn't built
/// ahead of it.
Future<void> incrementTokenVersion(StructuredLogDatabase db, int userId) {
  return (db.update(db.users)..where((t) => t.id.equals(userId))).write(
    UsersCompanion.custom(
        tokenVersion: db.users.tokenVersion + const Constant(1)),
  );
}
