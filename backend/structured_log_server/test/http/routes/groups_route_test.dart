import 'package:drift/native.dart';
import 'package:structured_log_server/src/audit/audit_writer.dart';
import 'package:structured_log_server/src/auth/identity_provider.dart';
import 'package:structured_log_server/src/errors.dart';
import 'package:structured_log_server/src/http/routes/groups_route.dart';
import 'package:structured_log_server/src/rbac/authorizer.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

const _admin = [EffectiveRole(role: Role.admin, scopeType: ScopeType.global)];
const _noRoles = <EffectiveRole>[];

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
  late GroupRoutes routes;

  setUp(() {
    db = openInMemory();
    authorizer = Authorizer(db);
    routes = GroupRoutes(db, authorizer, AuditWriter(db));
  });
  tearDown(() => db.close());

  group('createGroup', () {
    test('admin can create a group', () async {
      final response = await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/groups',
          roles: _admin,
          jsonBody: {'name': 'payments-team'},
        ),
      );

      expect(response.statusCode, 201);
      final body = await decodeJson(response);
      expect(body['name'], 'payments-team');
      expect(body['id'], isNotNull);
      expect(body['created_at'], isNotNull);
    });

    test('a non-admin is rejected with 403', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/groups',
            roles: _noRoles,
            jsonBody: {'name': 'x'},
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
            'http://x/v1/groups',
            roles: _admin,
            jsonBody: <String, Object?>{},
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });
  });

  group('listGroups', () {
    test('a global admin sees every group', () async {
      await db.into(db.groups).insert(GroupsCompanion.insert(name: 'a'));
      await db.into(db.groups).insert(GroupsCompanion.insert(name: 'b'));

      final response = await routes.router.call(
        authenticatedRequest('GET', 'http://x/v1/groups', roles: _admin),
      );
      final body = await decodeJson(response);
      expect((body['items'] as List), hasLength(2));
    });

    test('a user only sees groups covered by their roles', () async {
      final groupA = await db.into(db.groups).insert(
            GroupsCompanion.insert(name: 'visible'),
          );
      await db.into(db.groups).insert(GroupsCompanion.insert(name: 'hidden'));

      final response = await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/groups',
          roles: [
            EffectiveRole(
              role: Role.owner,
              scopeType: ScopeType.group,
              scopeId: groupA,
            ),
          ],
        ),
      );
      final body = await decodeJson(response);
      final items = body['items'] as List;
      expect(items, hasLength(1));
      expect((items.single as Map)['name'], 'visible');
    });

    test('a caller with no roles sees no groups', () async {
      await db.into(db.groups).insert(GroupsCompanion.insert(name: 'a'));

      final response = await routes.router.call(
        authenticatedRequest('GET', 'http://x/v1/groups', roles: _noRoles),
      );
      final body = await decodeJson(response);
      expect(body['items'], isEmpty);
    });
  });

  group('the audit record', () {
    test('a created group leaves one, naming who made it', () async {
      await routes.router.call(
        authenticatedRequest(
          'POST',
          'http://x/v1/groups',
          roles: _admin,
          userId: 9,
          jsonBody: {'name': 'payments-team'},
        ),
      );

      final row = (await auditRows(db)).single;
      expect(row.action, 'group.created');
      expect(row.targetType, 'group');
      expect(row.actorUserId, 9);
      expect(row.targetId, isNotNull);
      expect(auditMetadata(row)['name'], 'payments-team');
    });

    test('a refused attempt leaves none', () async {
      // The record answers "who did this", so a request that did nothing must
      // not produce one — an audit log carrying attempts alongside acts cannot
      // be read as either (`specs/log-server-audit`).
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/groups',
            roles: _noRoles,
            jsonBody: {'name': 'x'},
          ),
        ),
        throwsA(isA<ApiError>()),
      );

      expect(await auditRows(db), isEmpty);
    });

    test('a rejected body leaves none either', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'POST',
            'http://x/v1/groups',
            roles: _admin,
            jsonBody: {'name': ''},
          ),
        ),
        throwsA(isA<ApiError>()),
      );

      expect(await auditRows(db), isEmpty);
      expect(await db.select(db.groups).get(), isEmpty);
    });

    test('reading the list writes nothing', () async {
      await routes.router.call(
        authenticatedRequest('GET', 'http://x/v1/groups', roles: _admin),
      );

      expect(
        await auditRows(db),
        isEmpty,
        reason: 'the journal records acts, not queries',
      );
    });
  });
}
