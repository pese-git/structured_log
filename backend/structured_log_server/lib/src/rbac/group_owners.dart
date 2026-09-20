import 'package:drift/drift.dart';

import '../storage/database.dart';

/// Who is an owner of [groupId], directly or through a team.
///
/// An owner grant can be made to a user or to a team (`subject_type`), and a
/// team's owner grant makes every current member an owner. Counting only the
/// direct grants — as the guards did before teams could hold roles — sees a
/// group as ownerless when its only owner is a team, and as having a second
/// owner when the "other" owner is the same person listed twice.
Future<Set<int>> effectiveOwnerIds(
  StructuredLogDatabase db,
  int groupId,
) async {
  final grants = await (db.select(db.roleAssignments)
        ..where(
          (t) =>
              t.role.equals('owner') &
              t.scopeType.equals('group') &
              t.scopeId.equals(groupId),
        ))
      .get();

  final owners = <int>{};
  final teamIds = <int>[];
  for (final grant in grants) {
    if (grant.subjectType == 'user') {
      owners.add(grant.subjectId);
    } else {
      teamIds.add(grant.subjectId);
    }
  }
  if (teamIds.isNotEmpty) {
    final members = await (db.selectOnly(db.teamMembers)
          ..addColumns([db.teamMembers.userId])
          ..where(db.teamMembers.teamId.isIn(teamIds)))
        .map((row) => row.read(db.teamMembers.userId)!)
        .get();
    owners.addAll(members);
  }
  return owners;
}

/// Every group [userId] is an owner of — by a grant of their own, or by
/// belonging to a team that holds one.
Future<Set<int>> groupIdsOwnedBy(StructuredLogDatabase db, int userId) async {
  final direct = await (db.selectOnly(db.roleAssignments)
        ..addColumns([db.roleAssignments.scopeId])
        ..where(
          db.roleAssignments.subjectType.equals('user') &
              db.roleAssignments.subjectId.equals(userId) &
              db.roleAssignments.role.equals('owner') &
              db.roleAssignments.scopeType.equals('group'),
        ))
      .map((row) => row.read(db.roleAssignments.scopeId)!)
      .get();

  final teamIds = await (db.selectOnly(db.teamMembers)
        ..addColumns([db.teamMembers.teamId])
        ..where(db.teamMembers.userId.equals(userId)))
      .map((row) => row.read(db.teamMembers.teamId)!)
      .get();
  final viaTeams = teamIds.isEmpty
      ? const <int>[]
      : await (db.selectOnly(db.roleAssignments)
            ..addColumns([db.roleAssignments.scopeId])
            ..where(
              db.roleAssignments.subjectType.equals('team') &
                  db.roleAssignments.subjectId.isIn(teamIds) &
                  db.roleAssignments.role.equals('owner') &
                  db.roleAssignments.scopeType.equals('group'),
            ))
          .map((row) => row.read(db.roleAssignments.scopeId)!)
          .get();

  return {...direct, ...viaTeams};
}

/// The groups [teamId] holds an owner grant on.
Future<Set<int>> groupIdsOwnedByTeam(
  StructuredLogDatabase db,
  int teamId,
) async {
  final rows = await (db.selectOnly(db.roleAssignments)
        ..addColumns([db.roleAssignments.scopeId])
        ..where(
          db.roleAssignments.subjectType.equals('team') &
              db.roleAssignments.subjectId.equals(teamId) &
              db.roleAssignments.role.equals('owner') &
              db.roleAssignments.scopeType.equals('group'),
        ))
      .map((row) => row.read(db.roleAssignments.scopeId)!)
      .get();
  return rows.toSet();
}

/// Groups that a change would leave with no owner at all.
class SoleOwnerConflict implements Exception {
  final List<Group> groups;

  const SoleOwnerConflict(this.groups);

  @override
  String toString() =>
      'SoleOwnerConflict(${groups.map((g) => g.id).join(', ')})';
}

/// Runs [mutate] and refuses it — by throwing [SoleOwnerConflict] — if it left
/// any of [groupIds] with no owner that had one before (decision 27: a group
/// never ends up ownerless through an ordinary action).
///
/// Must be called inside the caller's transaction: the throw is what rolls the
/// mutation back, together with whatever else the transaction wrote. A group
/// that had no owner to begin with (an administrator made it and nobody was
/// named) is not the change's doing and does not block it.
///
/// Apply-then-check rather than predicting: which grants and memberships
/// still make someone an owner after the change is exactly the question
/// [effectiveOwnerIds] answers, and answering it once, on the real result, is
/// less to get wrong than working out each action's effect by hand.
Future<void> preservingGroupOwners(
  StructuredLogDatabase db,
  Iterable<int> groupIds,
  Future<void> Function() mutate,
) async {
  final ids = groupIds.toSet();
  if (ids.isEmpty) return mutate();

  final hadOwner = <int>{
    for (final id in ids)
      if ((await effectiveOwnerIds(db, id)).isNotEmpty) id,
  };
  await mutate();

  final orphaned = <int>[
    for (final id in hadOwner)
      if ((await effectiveOwnerIds(db, id)).isEmpty) id,
  ];
  if (orphaned.isEmpty) return;
  throw SoleOwnerConflict(
    await (db.select(db.groups)..where((t) => t.id.isIn(orphaned))).get(),
  );
}
