import 'package:drift/native.dart';
import 'package:structured_log_server/src/auth/claims.dart';
import 'package:structured_log_server/src/auth/identity_provider.dart';
import 'package:structured_log_server/src/rbac/authorizer.dart';
import 'package:structured_log_server/src/rbac/token_version.dart';
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
  late int userId;
  late int otherUserId;

  Future<int> versionOf(int id) async {
    final user =
        await (db.select(db.users)..where((t) => t.id.equals(id))).getSingle();
    return user.tokenVersion;
  }

  setUp(() async {
    db = openInMemory();
    userId = await db.into(db.users).insert(
          UsersCompanion.insert(username: 'u', passwordHash: 'x'),
        );
    otherUserId = await db.into(db.users).insert(
          UsersCompanion.insert(username: 'other', passwordHash: 'x'),
        );
  });
  tearDown(() => db.close());

  group('incrementTokenVersion', () {
    test('starts at zero and goes up by one', () async {
      expect(await versionOf(userId), 0);
      await incrementTokenVersion(db, userId);
      expect(await versionOf(userId), 1);
    });

    test('accumulates across calls', () async {
      for (var i = 0; i < 3; i++) {
        await incrementTokenVersion(db, userId);
      }
      expect(await versionOf(userId), 3);
    });

    test('touches only the named user', () async {
      await incrementTokenVersion(db, userId);
      expect(await versionOf(otherUserId), 0);
    });

    test('increments in SQL rather than read-modify-write', () async {
      // Concurrent revocations must not lose one another: two callers that
      // each read 0 and wrote 1 would revoke once instead of twice, and a
      // token issued in between would survive.
      await Future.wait([
        incrementTokenVersion(db, userId),
        incrementTokenVersion(db, userId),
        incrementTokenVersion(db, userId),
      ]);

      expect(await versionOf(userId), 3);
    });

    test('an unknown user id changes nothing and does not throw', () async {
      await incrementTokenVersion(db, 999999);
      expect(await versionOf(userId), 0);
    });
  });

  group('incrementTokenVersionsForTeam', () {
    late int groupId;
    late int teamId;

    setUp(() async {
      groupId =
          await db.into(db.groups).insert(GroupsCompanion.insert(name: 'g'));
      teamId = await db.into(db.teams).insert(
            TeamsCompanion.insert(groupId: groupId, name: 't'),
          );
    });

    test('bumps every current member, in one call', () async {
      await db.into(db.teamMembers).insert(
            TeamMembersCompanion.insert(teamId: teamId, userId: userId),
          );
      await db.into(db.teamMembers).insert(
            TeamMembersCompanion.insert(teamId: teamId, userId: otherUserId),
          );

      await incrementTokenVersionsForTeam(db, teamId);

      expect(await versionOf(userId), 1);
      expect(await versionOf(otherUserId), 1);
    });

    test('does not touch a user who isn\'t a member of this team', () async {
      await db.into(db.teamMembers).insert(
            TeamMembersCompanion.insert(teamId: teamId, userId: userId),
          );

      await incrementTokenVersionsForTeam(db, teamId);

      expect(await versionOf(otherUserId), 0);
    });

    test('does not touch a member of a different team', () async {
      final otherTeamId = await db.into(db.teams).insert(
            TeamsCompanion.insert(groupId: groupId, name: 't2'),
          );
      await db.into(db.teamMembers).insert(
            TeamMembersCompanion.insert(teamId: otherTeamId, userId: userId),
          );

      await incrementTokenVersionsForTeam(db, teamId);

      expect(await versionOf(userId), 0);
    });

    test('an empty team is a no-op, not an error', () async {
      await incrementTokenVersionsForTeam(db, teamId);
      expect(await versionOf(userId), 0);
    });

    test('an unknown team id changes nothing and does not throw', () async {
      await incrementTokenVersionsForTeam(db, 999999);
      expect(await versionOf(userId), 0);
    });
  });

  group('ClaimsResolver', () {
    late ClaimsResolver resolver;

    setUp(() => resolver = ClaimsResolver(db, Authorizer(db)));

    test('carries the current token_version, not a stale one', () async {
      await incrementTokenVersion(db, userId);
      await incrementTokenVersion(db, userId);

      expect((await resolver.resolve(userId)).tokenVersion, 2);
    });

    test('resolves effective roles from storage at issuance time', () async {
      expect((await resolver.resolve(userId)).roles, isEmpty);

      await db.into(db.roleAssignments).insert(
            RoleAssignmentsCompanion.insert(
              subjectType: 'user',
              subjectId: userId,
              role: 'admin',
              scopeType: 'global',
            ),
          );

      // A token issued now must see the role granted a moment ago — this is
      // what makes "refresh after a 401" show the caller their current
      // rights (`design.md` decision 10).
      final claims = await resolver.resolve(userId);
      expect(claims.roles, hasLength(1));
      expect(claims.roles.single.role, Role.admin);
      expect(claims.roles.single.scopeType, ScopeType.global);
    });

    test('does not mix in another user\'s roles', () async {
      await db.into(db.roleAssignments).insert(
            RoleAssignmentsCompanion.insert(
              subjectType: 'user',
              subjectId: otherUserId,
              role: 'admin',
              scopeType: 'global',
            ),
          );

      expect((await resolver.resolve(userId)).roles, isEmpty);
    });
  });
}
