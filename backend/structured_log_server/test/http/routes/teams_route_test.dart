import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:structured_log_server/src/audit/audit_writer.dart';
import 'package:structured_log_server/src/auth/hashing.dart';
import 'package:structured_log_server/src/auth/identity_provider.dart';
import 'package:structured_log_server/src/errors.dart';
import 'package:structured_log_server/src/http/routes/teams_route.dart';
import 'package:structured_log_server/src/rbac/authorizer.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

const _admin = [EffectiveRole(role: Role.admin, scopeType: ScopeType.global)];
const _noRoles = <EffectiveRole>[];

StructuredLogDatabase openInMemory() {
  return StructuredLogDatabase(
    NativeDatabase.memory(setup: (db) => db.execute('PRAGMA foreign_keys=ON;')),
  );
}

void main() {
  late StructuredLogDatabase db;
  late Authorizer authorizer;
  late TeamRoutes routes;
  late int groupId;

  setUp(() async {
    db = openInMemory();
    authorizer = Authorizer(db);
    routes = TeamRoutes(db, authorizer, AuditWriter(db));
    groupId = await db
        .into(db.groups)
        .insert(GroupsCompanion.insert(name: 'g'));
  });
  tearDown(() => db.close());

  List<EffectiveRole> ownerOf(int groupId) => [
    EffectiveRole(
      role: Role.owner,
      scopeType: ScopeType.group,
      scopeId: groupId,
    ),
  ];

  Future<int> insertUser({String username = 'bob'}) {
    return db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            username: username,
            passwordHash: hashPassword('s3cret'),
          ),
        );
  }

  Future<int> insertTeam(int groupId, {String name = 't'}) {
    return db
        .into(db.teams)
        .insert(TeamsCompanion.insert(groupId: groupId, name: name));
  }

  group('listTeams', () {
    test('an admin sees every team in the group', () async {
      await insertTeam(groupId, name: 'on-call');
      await insertTeam(groupId, name: 'billing');

      final response = await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/groups/$groupId/teams',
          roles: _admin,
        ),
      );

      expect(response.statusCode, 200);
      final body = await decodeJson(response);
      final items = body['items'] as List;
      expect(items.map((t) => t['name']), containsAll(['on-call', 'billing']));
    });

    test('a plain user with access to the group can also list', () async {
      await insertTeam(groupId);
      final userRoles = [
        EffectiveRole(
          role: Role.user,
          scopeType: ScopeType.group,
          scopeId: groupId,
        ),
      ];

      final response = await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/groups/$groupId/teams',
          roles: userRoles,
        ),
      );

      expect(response.statusCode, 200);
    });

    test('a team of another group is not included', () async {
      final otherGroupId = await db
          .into(db.groups)
          .insert(GroupsCompanion.insert(name: 'g2'));
      await insertTeam(otherGroupId, name: 'not-this-one');

      final response = await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/groups/$groupId/teams',
          roles: _admin,
        ),
      );

      final body = await decodeJson(response);
      expect(body['items'], isEmpty);
    });

    test('someone with no access to the group is refused with 403', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'GET',
            'http://x/v1/groups/$groupId/teams',
            roles: _noRoles,
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('an unknown group is rejected with 404', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'GET',
            'http://x/v1/groups/999/teams',
            roles: _admin,
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });
  });

  group('listTeamMembers', () {
    test('resolves the current members\' usernames', () async {
      final teamId = await insertTeam(groupId);
      final alice = await insertUser(username: 'alice');
      final bob = await insertUser(username: 'bob2');
      await db
          .into(db.teamMembers)
          .insert(TeamMembersCompanion.insert(teamId: teamId, userId: alice));
      await db
          .into(db.teamMembers)
          .insert(TeamMembersCompanion.insert(teamId: teamId, userId: bob));

      final response = await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/teams/$teamId/members',
          roles: _admin,
        ),
      );

      expect(response.statusCode, 200);
      final body = await decodeJson(response);
      final items = body['items'] as List;
      expect(items.map((m) => m['username']), containsAll(['alice', 'bob2']));
    });

    test('an empty team returns an empty list, not an error', () async {
      final teamId = await insertTeam(groupId);

      final response = await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/teams/$teamId/members',
          roles: _admin,
        ),
      );

      final body = await decodeJson(response);
      expect(body['items'], isEmpty);
    });

    test('a plain user with access to the group can also list', () async {
      final teamId = await insertTeam(groupId);
      final userRoles = [
        EffectiveRole(
          role: Role.user,
          scopeType: ScopeType.group,
          scopeId: groupId,
        ),
      ];

      final response = await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/teams/$teamId/members',
          roles: userRoles,
        ),
      );

      expect(response.statusCode, 200);
    });

    test('someone with no access to the group is refused with 403', () async {
      final teamId = await insertTeam(groupId);

      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'GET',
            'http://x/v1/teams/$teamId/members',
            roles: _noRoles,
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('an unknown team is rejected with 404', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'GET',
            'http://x/v1/teams/999/members',
            roles: _admin,
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });
  });

  group('createTeam', () {
    test('an admin can create a team', () async {
      final response = await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/groups/$groupId/teams',
          roles: _admin,
          jsonBody: {'name': 'on-call'},
        ),
      );

      expect(response.statusCode, 201);
      final body = await decodeJson(response);
      expect(body['group_id'], groupId);
      expect(body['name'], 'on-call');
    });

    test('the owner of the group can create a team in it', () async {
      final response = await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/groups/$groupId/teams',
          roles: ownerOf(groupId),
          jsonBody: {'name': 'on-call'},
        ),
      );

      expect(response.statusCode, 201);
    });

    test('the owner of a different group is refused with 403', () async {
      final otherGroupId = await db
          .into(db.groups)
          .insert(GroupsCompanion.insert(name: 'g2'));

      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/groups/$groupId/teams',
            roles: ownerOf(otherGroupId),
            jsonBody: {'name': 'on-call'},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('a plain user is refused with 403', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/groups/$groupId/teams',
            roles: _noRoles,
            jsonBody: {'name': 'on-call'},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('a missing name is rejected with 400', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/groups/$groupId/teams',
            roles: _admin,
            jsonBody: <String, Object?>{},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });

    test('an unknown group is rejected with 404', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/groups/999/teams',
            roles: _admin,
            jsonBody: {'name': 'on-call'},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('leaves an audit record naming the team and its group', () async {
      await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/groups/$groupId/teams',
          roles: _admin,
          userId: 7,
          jsonBody: {'name': 'on-call'},
        ),
      );

      final row = (await auditRows(db)).single;
      expect(row.action, 'team.created');
      expect(row.actorUserId, 7);
      final metadata = auditMetadata(row);
      expect(metadata['name'], 'on-call');
      expect(metadata['group_id'], groupId);
    });
  });

  group('addTeamMember', () {
    test('an admin can add a member', () async {
      final teamId = await insertTeam(groupId);
      final userId = await insertUser();

      final response = await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/teams/$teamId/members',
          roles: _admin,
          jsonBody: {'user_id': userId},
        ),
      );

      expect(response.statusCode, 204);
      final member =
          await (db.select(db.teamMembers)..where(
                (t) => t.teamId.equals(teamId) & t.userId.equals(userId),
              ))
              .getSingleOrNull();
      expect(member, isNotNull);
    });

    test('the owner of the team\'s group can add a member', () async {
      final teamId = await insertTeam(groupId);
      final userId = await insertUser();

      final response = await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/teams/$teamId/members',
          roles: ownerOf(groupId),
          jsonBody: {'user_id': userId},
        ),
      );

      expect(response.statusCode, 204);
    });

    test('the owner of a different group is refused with 403', () async {
      final teamId = await insertTeam(groupId);
      final userId = await insertUser();
      final otherGroupId = await db
          .into(db.groups)
          .insert(GroupsCompanion.insert(name: 'g2'));

      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/teams/$teamId/members',
            roles: ownerOf(otherGroupId),
            jsonBody: {'user_id': userId},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('an unknown team is rejected with 404', () async {
      final userId = await insertUser();

      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/teams/999/members',
            roles: _admin,
            jsonBody: {'user_id': userId},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('an unknown user_id is rejected with 404', () async {
      final teamId = await insertTeam(groupId);

      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/teams/$teamId/members',
            roles: _admin,
            jsonBody: {'user_id': 999},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test(
      'adding an already-current member is idempotent, not an error',
      () async {
        final teamId = await insertTeam(groupId);
        final userId = await insertUser();
        await db
            .into(db.teamMembers)
            .insert(
              TeamMembersCompanion.insert(teamId: teamId, userId: userId),
            );

        final response = await routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/teams/$teamId/members',
            roles: _admin,
            jsonBody: {'user_id': userId},
          ),
        );

        expect(response.statusCode, 204);
        expect(await auditRows(db), isEmpty);
      },
    );

    test('bumps only the added member\'s token_version', () async {
      final teamId = await insertTeam(groupId);
      final addedId = await insertUser(username: 'added');
      final bystanderId = await insertUser(username: 'bystander');
      await db
          .into(db.teamMembers)
          .insert(
            TeamMembersCompanion.insert(teamId: teamId, userId: bystanderId),
          );

      await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/teams/$teamId/members',
          roles: _admin,
          jsonBody: {'user_id': addedId},
        ),
      );

      final added = await (db.select(
        db.users,
      )..where((t) => t.id.equals(addedId))).getSingle();
      final bystander = await (db.select(
        db.users,
      )..where((t) => t.id.equals(bystanderId))).getSingle();
      expect(added.tokenVersion, 1);
      expect(
        bystander.tokenVersion,
        0,
        reason: 'a new member joining does not affect anyone else\'s access',
      );
    });

    test('leaves an audit record naming the team and the added user', () async {
      final teamId = await insertTeam(groupId);
      final userId = await insertUser();

      await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/teams/$teamId/members',
          roles: _admin,
          userId: 7,
          jsonBody: {'user_id': userId},
        ),
      );

      final row = (await auditRows(db)).single;
      expect(row.action, 'team.member_added');
      expect(row.actorUserId, 7);
      expect(row.targetId, teamId);
      expect(auditMetadata(row)['user_id'], userId);
    });
  });

  group('removeTeamMember', () {
    test('an admin can remove a member', () async {
      final teamId = await insertTeam(groupId);
      final userId = await insertUser();
      await db
          .into(db.teamMembers)
          .insert(TeamMembersCompanion.insert(teamId: teamId, userId: userId));

      final response = await routes.router.call(
        authenticatedRequest(
          'DELETE',
          'http://x/v1/teams/$teamId/members/$userId',
          roles: _admin,
        ),
      );

      expect(response.statusCode, 204);
      expect(
        await (db.select(db.teamMembers)
              ..where((t) => t.teamId.equals(teamId) & t.userId.equals(userId)))
            .getSingleOrNull(),
        isNull,
      );
    });

    test('the owner of the team\'s group can remove a member', () async {
      final teamId = await insertTeam(groupId);
      final userId = await insertUser();
      await db
          .into(db.teamMembers)
          .insert(TeamMembersCompanion.insert(teamId: teamId, userId: userId));

      final response = await routes.router.call(
        authenticatedRequest(
          'DELETE',
          'http://x/v1/teams/$teamId/members/$userId',
          roles: ownerOf(groupId),
        ),
      );

      expect(response.statusCode, 204);
    });

    test('a non-member is rejected with 404', () async {
      final teamId = await insertTeam(groupId);
      final userId = await insertUser();

      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'DELETE',
            'http://x/v1/teams/$teamId/members/$userId',
            roles: _admin,
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('an unknown team is rejected with 404', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'DELETE',
            'http://x/v1/teams/999/members/1',
            roles: _admin,
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('bumps only the removed member\'s token_version', () async {
      final teamId = await insertTeam(groupId);
      final removedId = await insertUser(username: 'removed');
      final bystanderId = await insertUser(username: 'bystander');
      await db
          .into(db.teamMembers)
          .insert(
            TeamMembersCompanion.insert(teamId: teamId, userId: removedId),
          );
      await db
          .into(db.teamMembers)
          .insert(
            TeamMembersCompanion.insert(teamId: teamId, userId: bystanderId),
          );

      await routes.router.call(
        authenticatedRequest(
          'DELETE',
          'http://x/v1/teams/$teamId/members/$removedId',
          roles: _admin,
        ),
      );

      final removed = await (db.select(
        db.users,
      )..where((t) => t.id.equals(removedId))).getSingle();
      final bystander = await (db.select(
        db.users,
      )..where((t) => t.id.equals(bystanderId))).getSingle();
      expect(removed.tokenVersion, 1);
      expect(
        bystander.tokenVersion,
        0,
        reason:
            'removing one member does not affect the rest of the team\'s '
            'access',
      );
    });

    test(
      'leaves an audit record naming the team and the removed user',
      () async {
        final teamId = await insertTeam(groupId);
        final userId = await insertUser();
        await db
            .into(db.teamMembers)
            .insert(
              TeamMembersCompanion.insert(teamId: teamId, userId: userId),
            );

        await routes.router.call(
          authenticatedRequest(
            'DELETE',
            'http://x/v1/teams/$teamId/members/$userId',
            roles: _admin,
            userId: 7,
          ),
        );

        final row = (await auditRows(db)).single;
        expect(row.action, 'team.member_removed');
        expect(row.actorUserId, 7);
        expect(row.targetId, teamId);
        expect(auditMetadata(row)['user_id'], userId);
      },
    );
  });
}
