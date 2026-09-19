import 'package:drift/native.dart';
import 'package:structured_log_server/src/audit/audit_action.dart';
import 'package:structured_log_server/src/audit/audit_writer.dart';
import 'package:structured_log_server/src/auth/identity_provider.dart';
import 'package:structured_log_server/src/errors.dart';
import 'package:structured_log_server/src/http/page_request.dart';
import 'package:structured_log_server/src/http/routes/audit_log_route.dart';
import 'package:structured_log_server/src/rbac/authorizer.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

const _admin = [EffectiveRole(role: Role.admin, scopeType: ScopeType.global)];
const _noRoles = <EffectiveRole>[];

List<EffectiveRole> ownerOf(int groupId) => [
      EffectiveRole(
        role: Role.owner,
        scopeType: ScopeType.group,
        scopeId: groupId,
      ),
    ];

StructuredLogDatabase openInMemory() {
  return StructuredLogDatabase(
    NativeDatabase.memory(
      setup: (db) => db.execute('PRAGMA foreign_keys=ON;'),
    ),
  );
}

void main() {
  late StructuredLogDatabase db;
  late AuditWriter audit;
  late AuditLogRoutes routes;

  setUp(() {
    db = openInMemory();
    audit = AuditWriter(db);
    routes = AuditLogRoutes(db, Authorizer(db));
  });
  tearDown(() => db.close());

  Future<Map<String, Object?>> query([String queryString = '']) async {
    final response = await routes.router.call(
      authenticatedRequest(
        'GET',
        'http://x/v1/audit-log$queryString',
        roles: _admin,
      ),
    );
    expect(response.statusCode, 200);
    return decodeJson(response);
  }

  List<Object?> itemsOf(Map<String, Object?> body) =>
      body['items']! as List<Object?>;

  group('access', () {
    test('an admin may read it', () async {
      expect(itemsOf(await query()), isEmpty);
    });

    test('a group owner may not', () async {
      // Not even a filtered view of their own group: the log spans tenants,
      // and the slice about one group still says which administrator acted on
      // it and from where.
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'GET',
            'http://x/v1/audit-log',
            roles: ownerOf(1),
          ),
        ),
        throwsA(
          isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
    });

    test('a user with no roles may not', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'GET',
            'http://x/v1/audit-log',
            roles: _noRoles,
          ),
        ),
        throwsA(isA<ApiError>()),
      );
    });
  });

  group('filters', () {
    setUp(() async {
      await audit.write(
        action: AuditAction.groupCreated,
        targetType: AuditTargetType.group,
        actorUserId: 1,
        targetId: 10,
        metadata: {'name': 'acme'},
      );
      await audit.write(
        action: AuditAction.projectCreated,
        targetType: AuditTargetType.project,
        actorUserId: 2,
        targetId: 20,
      );
      await audit.write(
        action: AuditAction.secretKeyRevoked,
        targetType: AuditTargetType.secretKey,
        actorUserId: 1,
        targetId: 30,
      );
    });

    test('by action', () async {
      final items = itemsOf(await query('?action=group.created'));
      expect(items, hasLength(1));
      expect((items.single! as Map)['target_id'], 10);
    });

    test('by actor', () async {
      expect(itemsOf(await query('?actor_user_id=1')), hasLength(2));
    });

    test('by target type and id together', () async {
      final items = itemsOf(await query('?target_type=project&target_id=20'));
      expect(items, hasLength(1));
      expect((items.single! as Map)['action'], 'project.created');
    });

    test('combined filters narrow in one request', () async {
      // An operator asking "what did this account do to that resource" is
      // asking one question, and every filter has to apply to it at once.
      expect(
        itemsOf(await query('?actor_user_id=1&target_type=group')),
        hasLength(1),
      );
      expect(
        itemsOf(await query('?actor_user_id=2&target_type=group')),
        isEmpty,
      );
    });

    test('an unknown action is refused, not answered with nothing', () async {
      // "No records" and "you misspelled it" look identical to a reader, and
      // only one of them is true. In a journal whose whole job is answering
      // "did this happen", the wrong one is unacceptable.
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'GET',
            'http://x/v1/audit-log?action=group.renamed',
            roles: _admin,
          ),
        ),
        throwsA(
          isA<ApiError>().having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });

    test('the newest record comes first', () async {
      final items = itemsOf(await query());
      expect((items.first! as Map)['action'], 'secret_key.revoked');
      expect((items.last! as Map)['action'], 'group.created');
    });

    test('an entry carries its metadata as an object, not a string', () async {
      final items = itemsOf(await query('?action=group.created'));
      expect((items.single! as Map)['metadata'], {'name': 'acme'});
    });
  });

  group('pagination', () {
    setUp(() async {
      for (var i = 0; i < 5; i++) {
        await audit.write(
          action: AuditAction.groupCreated,
          targetType: AuditTargetType.group,
          actorUserId: 1,
          targetId: i,
        );
      }
    });

    test('pages do not overlap and the last one ends the cursor', () async {
      final first = await query('?limit=2');
      expect(itemsOf(first), hasLength(2));
      expect(first['next_cursor'], isNotNull);

      final second = await query('?limit=2&cursor=${first['next_cursor']}');
      final third = await query('?limit=2&cursor=${second['next_cursor']}');

      final seen = [
        ...itemsOf(first),
        ...itemsOf(second),
        ...itemsOf(third),
      ].map((item) => (item! as Map)['id']).toList();

      expect(seen, hasLength(5), reason: 'every record exactly once');
      expect(seen.toSet(), hasLength(5), reason: 'and none of them twice');
      expect(
        third['next_cursor'],
        isNull,
        reason:
            'the reader is told there is no more, rather than discovering it '
            'by asking for an empty page',
      );
    });

    test('a full last page still ends the cursor', () async {
      // The off-by-one that a `length == limit` check gets wrong: five records
      // read in pages of five is exactly one page, not one and an empty one.
      final page = await query('?limit=5');
      expect(itemsOf(page), hasLength(5));
      expect(page['next_cursor'], isNull);
    });
  });

  group('page parameters', () {
    Future<void> expectStatus(
      String queryString,
      int status, {
      List<EffectiveRole> roles = _admin,
    }) {
      return expectLater(
        routes.router.call(
          authenticatedRequest(
            'GET',
            'http://x/v1/audit-log$queryString',
            roles: roles,
          ),
        ),
        throwsA(
          isA<ApiError>().having((e) => e.statusCode, 'statusCode', status),
        ),
      );
    }

    test('an unusable limit is a 400, not a failure inside storage', () async {
      await expectStatus('?limit=0', 400);
      await expectStatus('?limit=-5', 400);
      await expectStatus('?limit=abc', 400);
    });

    test('an unusable cursor is a 400', () async {
      await expectStatus('?cursor=not-a-cursor', 400);
    });

    test('the role check comes before the parameters', () async {
      // A group owner sending a bad limit is told they may not, not that the
      // limit is wrong: the second answer would confirm the route exists and
      // is worth calling to someone who has no business with it.
      await expectStatus('?limit=0', 403, roles: ownerOf(1));
    });

    test('a limit above the ceiling is served at the ceiling', () async {
      for (var i = 0; i < maxPageSize + 1; i++) {
        await audit.write(
          action: AuditAction.groupCreated,
          targetType: AuditTargetType.group,
          actorUserId: 1,
          targetId: i,
        );
      }
      final page = await query('?limit=100000');
      expect(itemsOf(page), hasLength(maxPageSize));
      expect(page['next_cursor'], isNotNull);
    });
  });

  group('the retention policy travels with the page', () {
    test('unset means kept indefinitely, and says so as null', () async {
      final body = await query();
      expect(body['audit_retention_days'], isNull);
      expect(body['auth_event_retention_days'], isNull);
    });

    test('a configured policy is reported alongside the records', () async {
      // A reader looking at an empty range needs to know whether it is outside
      // what is kept, and that question arrives with the result.
      routes = AuditLogRoutes(
        db,
        Authorizer(db),
        retention: const AuditRetention(
          auditRetentionDays: 365,
          authEventRetentionDays: 30,
        ),
      );

      final body = await query();
      expect(body['audit_retention_days'], 365);
      expect(body['auth_event_retention_days'], 30);
    });
  });

  test('a record with no actor is returned, not hidden', () async {
    await audit.write(
      action: AuditAction.authLoginFailed,
      targetType: AuditTargetType.user,
      metadata: {'reason': 'unknown_user'},
    );

    final item = itemsOf(await query()).single! as Map;
    expect(item['actor_user_id'], isNull);
    expect(item['target_id'], isNull);
    expect(item['action'], 'auth.login_failed');
  });
}
