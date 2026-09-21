import 'package:drift/native.dart';
import 'package:structured_log_server/src/audit/audit_writer.dart';
import 'package:structured_log_server/src/auth/identity_provider.dart';
import 'package:structured_log_server/src/errors.dart';
import 'package:structured_log_server/src/http/routes/secret_keys_route.dart';
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
  late int groupId;
  late int projectId;
  late SecretKeyRoutes routes;

  setUp(() async {
    db = openInMemory();
    authorizer = Authorizer(db);
    routes = SecretKeyRoutes(db, authorizer, AuditWriter(db));
    groupId = await db
        .into(db.groups)
        .insert(GroupsCompanion.insert(name: 'g'));
    projectId = await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            groupId: groupId,
            name: 'p',
            retentionDays: 30,
          ),
        );
  });
  tearDown(() => db.close());

  List<EffectiveRole> userOnProject(int projectId) => [
    EffectiveRole(
      role: Role.user,
      scopeType: ScopeType.project,
      scopeId: projectId,
    ),
  ];

  group('createSecretKey', () {
    test('an admin can create a key and receives the plaintext once', () async {
      final response = await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/projects/$projectId/secret-keys',
          roles: _admin,
          jsonBody: {'label': 'prod-instance-1'},
        ),
      );

      expect(response.statusCode, 201);
      final body = await decodeJson(response);
      expect(body['label'], 'prod-instance-1');
      expect(body['secret'], isA<String>());
      expect((body['secret'] as String), isNotEmpty);
    });

    test('label is optional', () async {
      final response = await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/projects/$projectId/secret-keys',
          roles: _admin,
          jsonBody: const <String, Object?>{},
        ),
      );
      expect(response.statusCode, 201);
      final body = await decodeJson(response);
      expect(body['label'], isNull);
    });

    test('a read-only caller cannot create a key', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/projects/$projectId/secret-keys',
            roles: userOnProject(projectId),
            jsonBody: const <String, Object?>{},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('an unknown project is rejected with 404', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/projects/999/secret-keys',
            roles: _admin,
            jsonBody: const <String, Object?>{},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });
  });

  group('listSecretKeys', () {
    test('metadata is listed without ever including the secret', () async {
      await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/projects/$projectId/secret-keys',
          roles: _admin,
          jsonBody: {'label': 'k1'},
        ),
      );

      final response = await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/projects/$projectId/secret-keys',
          roles: _admin,
        ),
      );
      final body = await decodeJson(response);
      final items = body['items'] as List;
      expect(items, hasLength(1));
      expect((items.single as Map).containsKey('secret'), isFalse);
      expect((items.single as Map)['label'], 'k1');
    });

    test('a caller with read-only access can still list', () async {
      final response = await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/projects/$projectId/secret-keys',
          roles: userOnProject(projectId),
        ),
      );
      expect(response.statusCode, 200);
    });

    test('a caller with no access at all is rejected with 403', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'GET',
            'http://x/v1/projects/$projectId/secret-keys',
            roles: _noRoles,
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });
  });

  group('revokeSecretKey', () {
    Future<int> createTestKey() async {
      final response = await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/projects/$projectId/secret-keys',
          roles: _admin,
          jsonBody: const <String, Object?>{},
        ),
      );
      final body = await decodeJson(response);
      return body['id'] as int;
    }

    test('an unknown key id is rejected with 404', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'DELETE',
            'http://x/v1/projects/$projectId/secret-keys/999999',
            roles: _admin,
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('a key belonging to another project is 404, not revoked', () async {
      // The key id alone must not address a key: an owner of one project
      // could otherwise revoke another project's key by guessing its id.
      final otherProject = await db
          .into(db.projects)
          .insert(
            ProjectsCompanion.insert(
              groupId: groupId,
              name: 'other',
              retentionDays: 30,
            ),
          );
      final foreignKey = await db
          .into(db.projectSecretKeys)
          .insert(
            ProjectSecretKeysCompanion.insert(
              projectId: otherProject,
              keyHash: 'hash',
            ),
          );

      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'DELETE',
            'http://x/v1/projects/$projectId/secret-keys/$foreignKey',
            roles: _admin,
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 404)),
      );

      final row = await (db.select(
        db.projectSecretKeys,
      )..where((t) => t.id.equals(foreignKey))).getSingle();
      expect(row.revokedAt, isNull);
    });

    test('revoking sets revoked_at and returns 204', () async {
      final keyId = await createTestKey();

      final response = await routes.router.call(
        authenticatedRequest(
          'DELETE',
          'http://x/v1/projects/$projectId/secret-keys/$keyId',
          roles: _admin,
        ),
      );
      expect(response.statusCode, 204);

      final row = await (db.select(
        db.projectSecretKeys,
      )..where((t) => t.id.equals(keyId))).getSingle();
      expect(row.revokedAt, isNotNull);
    });

    test('a read-only caller cannot revoke', () async {
      final keyId = await createTestKey();
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'DELETE',
            'http://x/v1/projects/$projectId/secret-keys/$keyId',
            roles: userOnProject(projectId),
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('an unknown key id is rejected with 404', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'DELETE',
            'http://x/v1/projects/$projectId/secret-keys/999',
            roles: _admin,
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test(
      'a key id belonging to a different project is rejected with 404',
      () async {
        final keyId = await createTestKey();
        final otherProjectId = await db
            .into(db.projects)
            .insert(
              ProjectsCompanion.insert(
                groupId: groupId,
                name: 'other',
                retentionDays: 30,
              ),
            );

        await expectLater(
          routes.router.call(
            authenticatedRequest(
              'DELETE',
              'http://x/v1/projects/$otherProjectId/secret-keys/$keyId',
              roles: _admin,
            ),
          ),
          throwsA(
            isA<ApiError>().having((e) => e.statusCode, 'statusCode', 404),
          ),
        );
      },
    );
  });

  group('the audit record', () {
    Future<Map<String, Object?>> createKey({String? label}) async {
      final response = await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/projects/$projectId/secret-keys',
          roles: _admin,
          userId: 5,
          jsonBody: label == null ? <String, Object?>{} : {'label': label},
        ),
      );
      return decodeJson(response);
    }

    test('a created key leaves one, and it carries no key', () async {
      final created = await createKey(label: 'ci');
      final secret = created['secret'] as String;

      final row = (await auditRows(db)).single;
      expect(row.action, 'secret_key.created');
      expect(row.targetType, 'secret_key');
      expect(row.actorUserId, 5);
      expect(row.targetId, created['id']);
      expect(auditMetadata(row), {'project_id': projectId, 'label': 'ci'});

      // The point of the record is that a key was issued and by whom. The key
      // itself is answered once, to one caller; the journal is read by more
      // people and for far longer.
      expect(row.metadata, isNot(contains(secret)));
      expect(
        row.metadata,
        isNot(contains('slk_')),
        reason: 'not even a prefix that would let a reader recognise one',
      );
    });

    test('a revoked key leaves one naming the key, not its value', () async {
      final created = await createKey(label: 'ci');

      await routes.router.call(
        authenticatedRequest(
          'DELETE',
          'http://x/v1/projects/$projectId/secret-keys/${created['id']}',
          roles: _admin,
          userId: 5,
        ),
      );

      final row = (await auditRows(db)).last;
      expect(row.action, 'secret_key.revoked');
      expect(row.targetId, created['id']);
      expect(auditMetadata(row), {'project_id': projectId, 'label': 'ci'});
      expect(row.metadata, isNot(contains(created['secret'] as String)));
    });

    test('a refused creation leaves none', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/projects/$projectId/secret-keys',
            roles: _noRoles,
            jsonBody: const <String, Object?>{},
          ),
        ),
        throwsA(isA<ApiError>()),
      );

      expect(await auditRows(db), isEmpty);
      expect(await db.select(db.projectSecretKeys).get(), isEmpty);
    });

    test('a refused revocation leaves none', () async {
      final created = await createKey();

      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'DELETE',
            'http://x/v1/projects/$projectId/secret-keys/${created['id']}',
            roles: _noRoles,
          ),
        ),
        throwsA(isA<ApiError>()),
      );

      expect(
        await auditRows(db),
        hasLength(1),
        reason: 'the creation above, and nothing from the refusal',
      );
    });

    test('listing keys writes nothing', () async {
      await createKey();
      await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/projects/$projectId/secret-keys',
          roles: _admin,
        ),
      );

      expect(await auditRows(db), hasLength(1));
    });
  });
}
