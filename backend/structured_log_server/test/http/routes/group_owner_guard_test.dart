import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:structured_log_server/src/audit/audit_writer.dart';
import 'package:structured_log_server/src/auth/identity_provider.dart';
import 'package:structured_log_server/src/errors.dart';
import 'package:structured_log_server/src/http/routes/role_assignments_route.dart';
import 'package:structured_log_server/src/http/routes/teams_route.dart';
import 'package:structured_log_server/src/http/routes/users_route.dart';
import 'package:structured_log_server/src/rbac/authorizer.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

const _admin = [EffectiveRole(role: Role.admin, scopeType: ScopeType.global)];

/// A group must never end up with nobody in charge through an ordinary action
/// (decision 27) — and "in charge" is an owner grant held by a user *or by a
/// team the user belongs to*. These are the ways such a group can be made,
/// each against the case where it must still go through.
void main() {
  late StructuredLogDatabase db;
  late TeamRoutes teams;
  late RoleAssignmentRoutes grants;
  late UserRoutes users;
  late int groupId;
  late int teamId;

  setUp(() async {
    db = StructuredLogDatabase(
      NativeDatabase.memory(
        setup: (db) => db.execute('PRAGMA foreign_keys=ON;'),
      ),
    );
    final authorizer = Authorizer(db);
    final audit = AuditWriter(db);
    teams = TeamRoutes(db, authorizer, audit);
    grants = RoleAssignmentRoutes(db, authorizer, audit);
    users = UserRoutes(db, authorizer, audit);
    groupId = await db
        .into(db.groups)
        .insert(GroupsCompanion.insert(name: 'g'));
    teamId = await db
        .into(db.teams)
        .insert(TeamsCompanion.insert(groupId: groupId, name: 'owners'));
  });
  tearDown(() => db.close());

  Future<int> user(String name) => db
      .into(db.users)
      .insert(UsersCompanion.insert(username: name, passwordHash: 'x'));

  Future<void> join(int teamId, int userId) => db
      .into(db.teamMembers)
      .insert(TeamMembersCompanion.insert(teamId: teamId, userId: userId));

  Future<int> grantOwner({
    required String subjectType,
    required int subjectId,
  }) {
    return db
        .into(db.roleAssignments)
        .insert(
          RoleAssignmentsCompanion.insert(
            subjectType: subjectType,
            subjectId: subjectId,
            role: 'owner',
            scopeType: 'group',
            scopeId: Value(groupId),
          ),
        );
  }

  Matcher soleOwnerConflict() => throwsA(
    isA<ApiError>()
        .having((e) => e.statusCode, 'statusCode', 409)
        .having((e) => e.code, 'code', 'sole_group_owner')
        .having(
          (e) => (e.details?['blocking_groups'] as List).single,
          'the group named',
          containsPair('id', groupId),
        ),
  );

  Future<Object?> deleteUser(int id) => users.router.call(
    authenticatedRequest(
      'DELETE',
      'http://x/v1/users/$id',
      roles: _admin,
      // Not the target: deleting oneself is a different route.
      userId: 9999,
    ),
  );

  Future<Object?> removeMember(int teamId, int userId) => teams.router.call(
    authenticatedRequest(
      'DELETE',
      'http://x/v1/teams/$teamId/members/$userId',
      roles: _admin,
    ),
  );

  Future<Object?> revoke(int assignmentId) => grants.router.call(
    authenticatedRequest(
      'DELETE',
      'http://x/v1/role-assignments/$assignmentId',
      roles: _admin,
    ),
  );

  Future<int> memberCount() async =>
      (await db.select(db.teamMembers).get()).length;

  group('deleting an account', () {
    test('the only member of the owning team is the sole owner', () async {
      final alice = await user('alice');
      await join(teamId, alice);
      await grantOwner(subjectType: 'team', subjectId: teamId);

      await expectLater(deleteUser(alice), soleOwnerConflict());

      final row = await (db.select(
        db.users,
      )..where((t) => t.id.equals(alice))).getSingle();
      expect(row.deletedAt, isNull, reason: 'nothing was deleted');
    });

    test(
      'a direct owner is not the sole one when a team owns the group too',
      () async {
        final alice = await user('alice');
        final bob = await user('bob');
        await grantOwner(subjectType: 'user', subjectId: alice);
        await join(teamId, bob);
        await grantOwner(subjectType: 'team', subjectId: teamId);

        final response = await deleteUser(alice) as dynamic;
        expect(response.statusCode, 204);
      },
    );

    test(
      'nor is a team member, when another member keeps the team owning',
      () async {
        final alice = await user('alice');
        final bob = await user('bob');
        await join(teamId, alice);
        await join(teamId, bob);
        await grantOwner(subjectType: 'team', subjectId: teamId);

        final response = await deleteUser(alice) as dynamic;
        expect(response.statusCode, 204);
      },
    );

    test('a person who is owner twice over is still one owner', () async {
      // Directly and through the team: deleting them leaves nobody, and
      // counting grants rather than people would have said "two owners".
      final alice = await user('alice');
      await grantOwner(subjectType: 'user', subjectId: alice);
      await join(teamId, alice);
      await grantOwner(subjectType: 'team', subjectId: teamId);

      await expectLater(deleteUser(alice), soleOwnerConflict());
    });
  });

  group('removing a member from the owning team', () {
    test('the last member cannot be removed, and nothing changes', () async {
      final alice = await user('alice');
      await join(teamId, alice);
      await grantOwner(subjectType: 'team', subjectId: teamId);

      await expectLater(removeMember(teamId, alice), soleOwnerConflict());

      expect(await memberCount(), 1, reason: 'the membership survived');
      expect(
        (await auditRows(db)).where((r) => r.action == 'team.member_removed'),
        isEmpty,
        reason: 'a refused request leaves no record of having happened',
      );
    });

    test('a member can go while another keeps the team owning', () async {
      final alice = await user('alice');
      final bob = await user('bob');
      await join(teamId, alice);
      await join(teamId, bob);
      await grantOwner(subjectType: 'team', subjectId: teamId);

      final response = await removeMember(teamId, alice) as dynamic;
      expect(response.statusCode, 204);
    });

    test(
      'the last member can go when someone owns the group directly',
      () async {
        final alice = await user('alice');
        final bob = await user('bob');
        await join(teamId, alice);
        await grantOwner(subjectType: 'team', subjectId: teamId);
        await grantOwner(subjectType: 'user', subjectId: bob);

        final response = await removeMember(teamId, alice) as dynamic;
        expect(response.statusCode, 204);
      },
    );

    test('a team that owns nothing can lose any member', () async {
      final alice = await user('alice');
      await join(teamId, alice);

      final response = await removeMember(teamId, alice) as dynamic;
      expect(response.statusCode, 204);
    });
  });

  group('revoking an owner grant', () {
    test('the last direct owner grant cannot be revoked', () async {
      final alice = await user('alice');
      final grant = await grantOwner(subjectType: 'user', subjectId: alice);

      await expectLater(revoke(grant), soleOwnerConflict());

      expect(
        await db.select(db.roleAssignments).get(),
        hasLength(1),
        reason: 'the grant is still there',
      );
    });

    test(
      'the owning team\'s grant cannot be revoked if it is the only one',
      () async {
        final alice = await user('alice');
        await join(teamId, alice);
        final grant = await grantOwner(subjectType: 'team', subjectId: teamId);

        await expectLater(revoke(grant), soleOwnerConflict());
      },
    );

    test('a grant can go when another owner remains', () async {
      final alice = await user('alice');
      final bob = await user('bob');
      final grant = await grantOwner(subjectType: 'user', subjectId: alice);
      await grantOwner(subjectType: 'user', subjectId: bob);

      final response = await revoke(grant) as dynamic;
      expect(response.statusCode, 204);
    });

    test('a team grant can go when a direct owner remains', () async {
      final alice = await user('alice');
      final bob = await user('bob');
      await join(teamId, alice);
      final grant = await grantOwner(subjectType: 'team', subjectId: teamId);
      await grantOwner(subjectType: 'user', subjectId: bob);

      final response = await revoke(grant) as dynamic;
      expect(response.statusCode, 204);
    });

    test('a team grant with no members is not an owner to protect', () async {
      // The group already had nobody in charge; revoking a grant nobody holds
      // is not what left it that way.
      final grant = await grantOwner(subjectType: 'team', subjectId: teamId);

      final response = await revoke(grant) as dynamic;
      expect(response.statusCode, 204);
    });

    test('a non-owner grant is never held up by the rule', () async {
      final alice = await user('alice');
      final grant = await db
          .into(db.roleAssignments)
          .insert(
            RoleAssignmentsCompanion.insert(
              subjectType: 'user',
              subjectId: alice,
              role: 'user',
              scopeType: 'group',
              scopeId: Value(groupId),
            ),
          );

      final response = await revoke(grant) as dynamic;
      expect(response.statusCode, 204);
    });
  });

  group('adding a member', () {
    test(
      'two requests for the same pair at once are both 204, one member',
      () async {
        final alice = await user('alice');
        Future<Object?> add() => teams.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/teams/$teamId/members',
            roles: _admin,
            jsonBody: {'user_id': alice},
          ),
        );

        final results = await Future.wait([add(), add(), add()]);

        expect(results.map((r) => (r as dynamic).statusCode), [204, 204, 204]);
        expect(await memberCount(), 1);
        expect(
          (await auditRows(db)).where((r) => r.action == 'team.member_added'),
          hasLength(1),
          reason: 'the ones that found it already done wrote nothing',
        );
      },
    );
  });
}
