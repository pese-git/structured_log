import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:structured_log_server/src/auth/identity_provider.dart';
import 'package:structured_log_server/src/rbac/authorizer.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

StructuredLogDatabase openInMemory() {
  return StructuredLogDatabase(
    NativeDatabase.memory(
      setup: (db) => db.execute('PRAGMA foreign_keys=ON;'),
    ),
  );
}

void main() {
  late StructuredLogDatabase db;
  late Authorizer authorizer;

  setUp(() {
    db = openInMemory();
    authorizer = Authorizer(db);
  });
  tearDown(() => db.close());

  Future<int> insertUser(String username) {
    return db.into(db.users).insert(
          UsersCompanion.insert(username: username, passwordHash: 'h'),
        );
  }

  test('a user with no role assignments has no effective roles', () async {
    final userId = await insertUser('alice');
    expect(await authorizer.effectiveRoles(userId), isEmpty);
  });

  test('a direct role assignment is returned', () async {
    final userId = await insertUser('alice');
    await db.into(db.roleAssignments).insert(
          RoleAssignmentsCompanion.insert(
            subjectType: 'user',
            subjectId: userId,
            role: 'admin',
            scopeType: 'global',
          ),
        );

    final roles = await authorizer.effectiveRoles(userId);
    expect(roles, [
      const EffectiveRole(role: Role.admin, scopeType: ScopeType.global),
    ]);
  });

  test('a role granted through team membership is inherited', () async {
    final userId = await insertUser('alice');
    final groupId = await db.into(db.groups).insert(
          GroupsCompanion.insert(name: 'g'),
        );
    final teamId = await db.into(db.teams).insert(
          TeamsCompanion.insert(groupId: groupId, name: 't'),
        );
    await db.into(db.teamMembers).insert(
          TeamMembersCompanion.insert(teamId: teamId, userId: userId),
        );
    await db.into(db.roleAssignments).insert(
          RoleAssignmentsCompanion.insert(
            subjectType: 'team',
            subjectId: teamId,
            role: 'owner',
            scopeType: 'group',
            scopeId: Value(groupId),
          ),
        );

    final roles = await authorizer.effectiveRoles(userId);
    expect(roles, [
      EffectiveRole(
          role: Role.owner, scopeType: ScopeType.group, scopeId: groupId),
    ]);
  });

  test('direct and team-inherited roles are both returned', () async {
    final userId = await insertUser('alice');
    final groupId = await db.into(db.groups).insert(
          GroupsCompanion.insert(name: 'g2'),
        );
    final projectId = await db.into(db.projects).insert(
          ProjectsCompanion.insert(
              groupId: groupId, name: 'p', retentionDays: 30),
        );
    final teamId = await db.into(db.teams).insert(
          TeamsCompanion.insert(groupId: groupId, name: 't2'),
        );
    await db.into(db.teamMembers).insert(
          TeamMembersCompanion.insert(teamId: teamId, userId: userId),
        );
    await db.into(db.roleAssignments).insert(
          RoleAssignmentsCompanion.insert(
            subjectType: 'user',
            subjectId: userId,
            role: 'user',
            scopeType: 'project',
            scopeId: Value(projectId),
          ),
        );
    await db.into(db.roleAssignments).insert(
          RoleAssignmentsCompanion.insert(
            subjectType: 'team',
            subjectId: teamId,
            role: 'owner',
            scopeType: 'group',
            scopeId: Value(groupId),
          ),
        );

    final roles = await authorizer.effectiveRoles(userId);
    expect(
      roles,
      unorderedEquals([
        EffectiveRole(
          role: Role.user,
          scopeType: ScopeType.project,
          scopeId: projectId,
        ),
        EffectiveRole(
          role: Role.owner,
          scopeType: ScopeType.group,
          scopeId: groupId,
        ),
      ]),
    );
  });

  test('a role granted to a different team is not inherited', () async {
    final userId = await insertUser('alice');
    final groupId = await db.into(db.groups).insert(
          GroupsCompanion.insert(name: 'g3'),
        );
    final otherTeamId = await db.into(db.teams).insert(
          TeamsCompanion.insert(groupId: groupId, name: 'other-team'),
        );
    await db.into(db.roleAssignments).insert(
          RoleAssignmentsCompanion.insert(
            subjectType: 'team',
            subjectId: otherTeamId,
            role: 'owner',
            scopeType: 'group',
            scopeId: Value(groupId),
          ),
        );

    expect(await authorizer.effectiveRoles(userId), isEmpty);
  });
}
