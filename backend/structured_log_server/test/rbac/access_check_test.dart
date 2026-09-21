import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:structured_log_server/src/auth/identity_provider.dart';
import 'package:structured_log_server/src/rbac/access_check.dart';
import 'package:structured_log_server/src/rbac/authorizer.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

StructuredLogDatabase openInMemory() {
  return StructuredLogDatabase(
    NativeDatabase.memory(setup: (db) => db.execute('PRAGMA foreign_keys=ON;')),
  );
}

EffectiveRole global(Role role) =>
    EffectiveRole(role: role, scopeType: ScopeType.global);

EffectiveRole onGroup(Role role, int groupId) =>
    EffectiveRole(role: role, scopeType: ScopeType.group, scopeId: groupId);

EffectiveRole onProject(Role role, int projectId) =>
    EffectiveRole(role: role, scopeType: ScopeType.project, scopeId: projectId);

void main() {
  // These three functions decide every authorization outcome in the server:
  // each route resolves roles and then asks one of them (`design.md`
  // decision 4.4 — authorization lives inside handlers). The route tests
  // exercise them through their own endpoint's happy path; this covers the
  // grid directly, where a wrong answer is a privilege escalation rather
  // than a failing request.
  group('isGlobalAdmin', () {
    test('only a global-scoped admin qualifies', () {
      expect(isGlobalAdmin([global(Role.admin)]), isTrue);
      expect(isGlobalAdmin([global(Role.owner)]), isFalse);
      expect(isGlobalAdmin([global(Role.user)]), isFalse);
      expect(isGlobalAdmin([onGroup(Role.admin, 1)]), isFalse);
      expect(isGlobalAdmin([onProject(Role.admin, 1)]), isFalse);
      expect(isGlobalAdmin([]), isFalse);
    });
  });

  group('canRead', () {
    test('no roles grants nothing', () {
      expect(canRead([], targetType: ScopeType.group, targetId: 1), isFalse);
    });

    test('a global grant of any role covers everything', () {
      for (final role in Role.values) {
        expect(
          canRead([global(role)], targetType: ScopeType.group, targetId: 7),
          isTrue,
          reason: '$role on a group',
        );
        expect(
          canRead(
            [global(role)],
            targetType: ScopeType.project,
            targetId: 7,
            enclosingGroupId: 3,
          ),
          isTrue,
          reason: '$role on a project',
        );
      }
    });

    test('a group grant covers that group and no other', () {
      expect(
        canRead(
          [onGroup(Role.user, 1)],
          targetType: ScopeType.group,
          targetId: 1,
        ),
        isTrue,
      );
      expect(
        canRead(
          [onGroup(Role.user, 1)],
          targetType: ScopeType.group,
          targetId: 2,
        ),
        isFalse,
      );
    });

    test('a group grant reaches projects inside that group', () {
      expect(
        canRead(
          [onGroup(Role.user, 1)],
          targetType: ScopeType.project,
          targetId: 42,
          enclosingGroupId: 1,
        ),
        isTrue,
      );
      expect(
        canRead(
          [onGroup(Role.user, 1)],
          targetType: ScopeType.project,
          targetId: 42,
          enclosingGroupId: 2,
        ),
        isFalse,
        reason: 'a project of another group',
      );
    });

    test('a group grant does not reach a project of unknown parentage', () {
      // enclosingGroupId omitted: the caller failed to say which group the
      // project belongs to, and a group grant must not be assumed to cover
      // it. Silently granting here would turn a caller's oversight into
      // access.
      expect(
        canRead(
          [onGroup(Role.user, 1)],
          targetType: ScopeType.project,
          targetId: 42,
        ),
        isFalse,
      );
    });

    test('a project grant covers that project only', () {
      expect(
        canRead(
          [onProject(Role.user, 42)],
          targetType: ScopeType.project,
          targetId: 42,
          enclosingGroupId: 1,
        ),
        isTrue,
      );
      expect(
        canRead(
          [onProject(Role.user, 42)],
          targetType: ScopeType.project,
          targetId: 43,
          enclosingGroupId: 1,
        ),
        isFalse,
      );
    });

    test('a project grant does not widen to its group', () {
      expect(
        canRead(
          [onProject(Role.owner, 42)],
          targetType: ScopeType.group,
          targetId: 1,
        ),
        isFalse,
      );
    });

    test('any one covering role among several is enough', () {
      final roles = [onGroup(Role.user, 9), onProject(Role.user, 42)];
      expect(
        canRead(
          roles,
          targetType: ScopeType.project,
          targetId: 42,
          enclosingGroupId: 1,
        ),
        isTrue,
      );
    });
  });

  group('canWrite', () {
    test('user may read but not write, at every scope', () {
      expect(
        canRead([global(Role.user)], targetType: ScopeType.group, targetId: 1),
        isTrue,
      );
      expect(
        canWrite([global(Role.user)], targetType: ScopeType.group, targetId: 1),
        isFalse,
      );
      expect(
        canWrite(
          [onProject(Role.user, 42)],
          targetType: ScopeType.project,
          targetId: 42,
          enclosingGroupId: 1,
        ),
        isFalse,
      );
    });

    test('admin and owner may write', () {
      for (final role in [Role.admin, Role.owner]) {
        expect(
          canWrite([global(role)], targetType: ScopeType.group, targetId: 1),
          isTrue,
          reason: '$role',
        );
      }
    });

    test('scope still applies to a writing role', () {
      expect(
        canWrite(
          [onGroup(Role.owner, 1)],
          targetType: ScopeType.group,
          targetId: 2,
        ),
        isFalse,
      );
    });

    test('a writing role elsewhere does not authorize here', () {
      final roles = [onProject(Role.owner, 42), onGroup(Role.user, 1)];
      expect(
        canWrite(
          roles,
          targetType: ScopeType.project,
          targetId: 43,
          enclosingGroupId: 1,
        ),
        isFalse,
        reason: 'owner of another project, mere user of the group',
      );
    });
  });

  group('canReadRoleAssignmentsForScope', () {
    test('the same grid as canWrite — admin and owner, not user', () {
      expect(
        canReadRoleAssignmentsForScope(
          [global(Role.admin)],
          scopeType: ScopeType.group,
          scopeId: 1,
        ),
        isTrue,
      );
      expect(
        canReadRoleAssignmentsForScope(
          [onGroup(Role.owner, 1)],
          scopeType: ScopeType.group,
          scopeId: 1,
        ),
        isTrue,
      );
      expect(
        canReadRoleAssignmentsForScope(
          [onGroup(Role.user, 1)],
          scopeType: ScopeType.group,
          scopeId: 1,
        ),
        isFalse,
        reason: 'a mere member of the group, not its owner',
      );
    });

    test('an owner of the enclosing group covers the project too', () {
      expect(
        canReadRoleAssignmentsForScope(
          [onGroup(Role.owner, 1)],
          scopeType: ScopeType.project,
          scopeId: 42,
          enclosingGroupId: 1,
        ),
        isTrue,
      );
    });

    test('owner of a different group does not cover this one', () {
      expect(
        canReadRoleAssignmentsForScope(
          [onGroup(Role.owner, 2)],
          scopeType: ScopeType.group,
          scopeId: 1,
        ),
        isFalse,
      );
    });
  });

  group('canCreateOrRevokeRoleAssignment', () {
    test('admin may grant any role on any scope', () {
      for (final role in Role.values) {
        expect(
          canCreateOrRevokeRoleAssignment(
            [global(Role.admin)],
            targetRole: role,
            scopeType: ScopeType.global,
          ),
          isTrue,
          reason: '$role',
        );
      }
    });

    test('owner of group G may grant owner/user on group G', () {
      for (final role in [Role.owner, Role.user]) {
        expect(
          canCreateOrRevokeRoleAssignment(
            [onGroup(Role.owner, 1)],
            targetRole: role,
            scopeType: ScopeType.group,
            scopeId: 1,
          ),
          isTrue,
          reason: '$role',
        );
      }
    });

    test('owner of group G may grant owner/user on a project inside G', () {
      expect(
        canCreateOrRevokeRoleAssignment(
          [onGroup(Role.owner, 1)],
          targetRole: Role.user,
          scopeType: ScopeType.project,
          scopeId: 42,
          enclosingGroupId: 1,
        ),
        isTrue,
      );
    });

    test('owner cannot grant the admin role', () {
      expect(
        canCreateOrRevokeRoleAssignment(
          [onGroup(Role.owner, 1)],
          targetRole: Role.admin,
          scopeType: ScopeType.group,
          scopeId: 1,
        ),
        isFalse,
      );
    });

    test('owner cannot grant outside their own group', () {
      expect(
        canCreateOrRevokeRoleAssignment(
          [onGroup(Role.owner, 1)],
          targetRole: Role.user,
          scopeType: ScopeType.project,
          scopeId: 42,
          enclosingGroupId: 2,
        ),
        isFalse,
        reason: 'project belongs to a different group',
      );
      expect(
        canCreateOrRevokeRoleAssignment(
          [onGroup(Role.owner, 1)],
          targetRole: Role.user,
          scopeType: ScopeType.group,
          scopeId: 2,
        ),
        isFalse,
      );
    });

    test('owner cannot grant a global-scoped role', () {
      expect(
        canCreateOrRevokeRoleAssignment(
          [onGroup(Role.owner, 1)],
          targetRole: Role.user,
          scopeType: ScopeType.global,
        ),
        isFalse,
      );
    });

    test('an owner of a project alone cannot grant anything', () {
      expect(
        canCreateOrRevokeRoleAssignment(
          [onProject(Role.owner, 42)],
          targetRole: Role.user,
          scopeType: ScopeType.project,
          scopeId: 42,
          enclosingGroupId: 1,
        ),
        isFalse,
        reason: 'the rule is scoped to a group-level owner, not project-level',
      );
    });

    test('user can never grant a role', () {
      expect(
        canCreateOrRevokeRoleAssignment(
          [onGroup(Role.user, 1)],
          targetRole: Role.user,
          scopeType: ScopeType.group,
          scopeId: 1,
        ),
        isFalse,
      );
    });

    test('no roles grants nothing', () {
      expect(
        canCreateOrRevokeRoleAssignment(
          [],
          targetRole: Role.user,
          scopeType: ScopeType.global,
        ),
        isFalse,
      );
    });

    test('owner of group G may grant a team belonging to G', () {
      expect(
        canCreateOrRevokeRoleAssignment(
          [onGroup(Role.owner, 1)],
          targetRole: Role.user,
          scopeType: ScopeType.group,
          scopeId: 1,
          subjectTeamGroupId: 1,
        ),
        isTrue,
      );
    });

    test(
      'owner of group G may not grant a team belonging to another group',
      () {
        expect(
          canCreateOrRevokeRoleAssignment(
            [onGroup(Role.owner, 1)],
            targetRole: Role.user,
            scopeType: ScopeType.group,
            scopeId: 1,
            subjectTeamGroupId: 2,
          ),
          isFalse,
          reason:
              "the other group's owner controls that team's membership, "
              'not this one',
        );
      },
    );

    test('owner of group G may grant a team of G a role on one of G\'s '
        'projects', () {
      expect(
        canCreateOrRevokeRoleAssignment(
          [onGroup(Role.owner, 1)],
          targetRole: Role.user,
          scopeType: ScopeType.project,
          scopeId: 42,
          enclosingGroupId: 1,
          subjectTeamGroupId: 1,
        ),
        isTrue,
      );
    });

    test('admin may grant a team from any group', () {
      expect(
        canCreateOrRevokeRoleAssignment(
          [global(Role.admin)],
          targetRole: Role.owner,
          scopeType: ScopeType.group,
          scopeId: 1,
          subjectTeamGroupId: 2,
        ),
        isTrue,
        reason: "admin is exempt from the team-must-belong-to-G restriction",
      );
    });
  });

  group('canSearchUsers', () {
    test('admin may search', () {
      expect(canSearchUsers([global(Role.admin)]), isTrue);
    });

    test('owner of any group may search, not just one it owns', () {
      expect(canSearchUsers([onGroup(Role.owner, 1)]), isTrue);
    });

    test('a user role on a group may not search', () {
      expect(canSearchUsers([onGroup(Role.user, 1)]), isFalse);
    });

    test('someone with no roles at all may not search', () {
      expect(canSearchUsers(const []), isFalse);
    });

    test('an owner scoped to a project, not a group, may not search', () {
      // A project-scoped owner grant is not how the roles table is meant to
      // be populated (owner only ever targets group/global — see
      // canCreateOrRevokeRoleAssignment), but the check should still read
      // the scope type strictly rather than assume.
      expect(canSearchUsers([onProject(Role.owner, 1)]), isFalse);
    });
  });

  group('resolveRoles', () {
    late StructuredLogDatabase db;
    late Authorizer authorizer;
    late int userId;

    setUp(() async {
      db = openInMemory();
      authorizer = Authorizer(db);
      userId = await db
          .into(db.users)
          .insert(UsersCompanion.insert(username: 'u', passwordHash: 'x'));
      await db
          .into(db.roleAssignments)
          .insert(
            RoleAssignmentsCompanion.insert(
              subjectType: 'user',
              subjectId: userId,
              role: 'owner',
              scopeType: 'group',
              scopeId: const Value(5),
            ),
          );
    });
    tearDown(() => db.close());

    test('uses the token snapshot when the provider supplied one', () async {
      // The stored assignment says owner-of-group-5; the token says
      // user-of-group-9. The snapshot wins, which is what makes
      // token_version the revocation mechanism rather than a per-request
      // database read.
      final identity = VerifiedIdentity(
        userId: userId,
        username: 'u',
        roles: [onGroup(Role.user, 9)],
      );

      expect(await resolveRoles(authorizer, identity), [onGroup(Role.user, 9)]);
    });

    test('an empty snapshot is still a snapshot, not a missing one', () async {
      final identity = VerifiedIdentity(
        userId: userId,
        username: 'u',
        roles: const [],
      );

      expect(await resolveRoles(authorizer, identity), isEmpty);
    });

    test('falls back to storage when the provider supplied none', () async {
      final identity = VerifiedIdentity(
        userId: userId,
        username: 'u',
        roles: null,
      );

      expect(await resolveRoles(authorizer, identity), [
        onGroup(Role.owner, 5),
      ]);
    });
  });
}
