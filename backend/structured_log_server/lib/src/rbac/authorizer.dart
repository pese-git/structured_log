import 'package:drift/drift.dart';

import '../auth/identity_provider.dart';
import '../storage/database.dart';

/// Resolves a user's effective roles directly from `role_assignments`/
/// `team_members` — the single source of truth `log-server-rbac` requires,
/// independent of how the caller was authenticated. Used both when issuing
/// a token (`ClaimsResolver`, `lib/src/auth/claims.dart`) and as the
/// fallback authorization path when `VerifiedIdentity.roles == null`.
class Authorizer {
  final StructuredLogDatabase _db;

  Authorizer(this._db);

  /// Direct [RoleAssignments] of [userId], plus every [RoleAssignments]
  /// granted to a team [userId] currently belongs to.
  Future<List<EffectiveRole>> effectiveRoles(int userId) async {
    final direct =
        await (_db.select(_db.roleAssignments)..where(
              (t) => t.subjectType.equals('user') & t.subjectId.equals(userId),
            ))
            .get();

    final teamIds =
        await (_db.selectOnly(_db.teamMembers)
              ..addColumns([_db.teamMembers.teamId])
              ..where(_db.teamMembers.userId.equals(userId)))
            .map((row) => row.read(_db.teamMembers.teamId)!)
            .get();

    final viaTeams = teamIds.isEmpty
        ? <RoleAssignment>[]
        : await (_db.select(_db.roleAssignments)..where(
                (t) => t.subjectType.equals('team') & t.subjectId.isIn(teamIds),
              ))
              .get();

    return [
      ...direct,
      ...viaTeams,
    ].map(_toEffectiveRole).toList(growable: false);
  }

  EffectiveRole _toEffectiveRole(RoleAssignment row) {
    return EffectiveRole(
      role: Role.values.byName(row.role),
      scopeType: ScopeType.values.byName(row.scopeType),
      scopeId: row.scopeId,
    );
  }
}
