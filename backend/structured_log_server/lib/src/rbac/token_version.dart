import 'package:drift/drift.dart';

import '../storage/database.dart';

/// Atomically increments `User.token_version` for [userId] — the mechanism
/// `log-server-auth` relies on for immediate revocation of already-issued
/// access tokens (their `tv` claim stops matching). Called on any event
/// that must invalidate a single user's outstanding tokens: a direct
/// `RoleAssignment` change, a team-membership change (`5.3` — adding or
/// removing *one* member affects only that member, not the rest of the
/// team, `design.md` decision 10), deactivation, password change.
Future<void> incrementTokenVersion(StructuredLogDatabase db, int userId) {
  return (db.update(db.users)..where((t) => t.id.equals(userId))).write(
    UsersCompanion.custom(
        tokenVersion: db.users.tokenVersion + const Constant(1)),
  );
}

/// Atomically increments `User.token_version` for every *current* member of
/// [teamId], in one bulk `UPDATE` rather than a loop of single increments —
/// the cascading case `design.md` decision 10 reserves for a team-scoped
/// `RoleAssignment` being created or revoked (`5.6`, full version): that one
/// change affects every member's effective roles at once, unlike a
/// membership change (`5.3`, [incrementTokenVersion]), which affects only
/// the member who joined or left. A no-op for an empty team — `UPDATE ...
/// WHERE id IN ()` is either invalid or a no-op depending on the SQL
/// dialect, and an explicit early return says so rather than relying on
/// that.
Future<void> incrementTokenVersionsForTeam(
  StructuredLogDatabase db,
  int teamId,
) async {
  final memberIds = await (db.selectOnly(db.teamMembers)
        ..addColumns([db.teamMembers.userId])
        ..where(db.teamMembers.teamId.equals(teamId)))
      .map((row) => row.read(db.teamMembers.userId)!)
      .get();
  if (memberIds.isEmpty) return;

  await (db.update(db.users)..where((t) => t.id.isIn(memberIds))).write(
    UsersCompanion.custom(
        tokenVersion: db.users.tokenVersion + const Constant(1)),
  );
}
