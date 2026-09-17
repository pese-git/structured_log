import 'package:drift/drift.dart';

import '../rbac/token_version.dart';
import '../storage/database.dart';
import 'session.dart';

/// Why [deleteUser] refused, or `null` on success.
enum DeleteUserFailure { cannotDeletePrimaryAdmin, soleGroupOwner }

/// The result of [deleteUser] — either it happened, or it was refused and
/// nothing changed.
class DeleteUserOutcome {
  final DeleteUserFailure? failure;

  /// Populated only when [failure] is [DeleteUserFailure.soleGroupOwner] —
  /// every group [deleteUser]'s target is the sole `owner` of.
  final List<Group> blockingGroups;

  const DeleteUserOutcome.success()
      : failure = null,
        blockingGroups = const [];

  const DeleteUserOutcome.failed(
    DeleteUserFailure this.failure, {
    this.blockingGroups = const [],
  });

  bool get isSuccess => failure == null;
}

/// The shared deletion logic behind both `DELETE /v1/users/me` (3.10a) and
/// `DELETE /v1/users/:id` (3.10b) — everything past "who is asking and which
/// audit action they write" is identical between them.
///
/// Runs the two guard checks (`docs/architecture/rbac-and-lifecycle.md`)
/// before touching anything, and performs the mutation as plain queries —
/// **not** wrapped in its own transaction. The caller is expected to call
/// this from inside a `db.transaction(...)` block that also writes the
/// `user.deleted` audit record, so a mutation that somehow rolls back never
/// leaves an audit record behind for something that didn't happen
/// (`specs/log-server-audit`, task 19.3). A refused attempt performs no
/// writes at all, so wrapping it in a transaction that never gets used is
/// harmless.
Future<DeleteUserOutcome> deleteUser(
  StructuredLogDatabase db,
  User target,
) async {
  // Identity-based, not count-based (decision 28): this exact account, full
  // stop — not "whoever is currently the last admin".
  if (target.isPrimaryAdmin) {
    return const DeleteUserOutcome.failed(
      DeleteUserFailure.cannotDeletePrimaryAdmin,
    );
  }

  final blockingGroups = await _groupsWhereSoleOwner(db, target.id);
  if (blockingGroups.isNotEmpty) {
    return DeleteUserOutcome.failed(
      DeleteUserFailure.soleGroupOwner,
      blockingGroups: blockingGroups,
    );
  }

  await (db.update(db.users)..where((t) => t.id.equals(target.id))).write(
    UsersCompanion(
      deletedAt: Value(DateTime.now()),
      isActive: const Value(false),
    ),
  );
  await revokeAllRefreshTokens(db, target.id);
  await incrementTokenVersion(db, target.id);
  await (db.delete(db.roleAssignments)
        ..where(
          (t) => t.subjectType.equals('user') & t.subjectId.equals(target.id),
        ))
      .go();
  await (db.delete(db.teamMembers)..where((t) => t.userId.equals(target.id)))
      .go();

  return const DeleteUserOutcome.success();
}

/// Every [Groups] row where [userId] is the only `owner` — the check that
/// stands between a deletion and leaving a group with no owner at all
/// (decision 27).
///
/// Direct `role_assignments` only: a team-scoped `owner` grant
/// (`subject_type: team`) isn't reachable yet — there is no endpoint that
/// creates a team or assigns it a role (`design.md` "Delivery Phases", Этап
/// 3 stops at 4.3a/5.6a, both `subject_type: user` only) — so no state this
/// server can currently produce needs it considered.
Future<List<Group>> _groupsWhereSoleOwner(
  StructuredLogDatabase db,
  int userId,
) async {
  final ownedGroupIds = await (db.selectOnly(db.roleAssignments)
        ..addColumns([db.roleAssignments.scopeId])
        ..where(
          db.roleAssignments.subjectType.equals('user') &
              db.roleAssignments.subjectId.equals(userId) &
              db.roleAssignments.role.equals('owner') &
              db.roleAssignments.scopeType.equals('group'),
        ))
      .map((row) => row.read(db.roleAssignments.scopeId)!)
      .get();
  if (ownedGroupIds.isEmpty) return const [];

  final sole = <int>[];
  for (final groupId in ownedGroupIds.toSet()) {
    final otherOwners = await (db.selectOnly(db.roleAssignments)
          ..addColumns([db.roleAssignments.id])
          ..where(
            db.roleAssignments.subjectType.equals('user') &
                db.roleAssignments.subjectId.equals(userId).not() &
                db.roleAssignments.role.equals('owner') &
                db.roleAssignments.scopeType.equals('group') &
                db.roleAssignments.scopeId.equals(groupId),
          )
          ..limit(1))
        .get();
    if (otherOwners.isEmpty) sole.add(groupId);
  }
  if (sole.isEmpty) return const [];

  return (db.select(db.groups)..where((t) => t.id.isIn(sole))).get();
}
