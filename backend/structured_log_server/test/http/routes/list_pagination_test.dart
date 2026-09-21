import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:shelf/shelf.dart';
import 'package:structured_log_server/src/audit/audit_action.dart';
import 'package:structured_log_server/src/audit/audit_writer.dart';
import 'package:structured_log_server/src/auth/identity_provider.dart';
import 'package:structured_log_server/src/errors.dart';
import 'package:structured_log_server/src/http/page_request.dart';
import 'package:structured_log_server/src/http/routes/audit_log_route.dart';
import 'package:structured_log_server/src/http/routes/groups_route.dart';
import 'package:structured_log_server/src/http/routes/logs_route.dart';
import 'package:structured_log_server/src/http/routes/projects_route.dart';
import 'package:structured_log_server/src/http/routes/users_route.dart';
import 'package:structured_log_server/src/live/log_broadcast.dart';
import 'package:structured_log_server/src/rbac/access_check.dart';
import 'package:structured_log_server/src/rbac/authorizer.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:structured_log_server/src/storage/log_store.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// The contract every paginated list shares (`log-server-pagination`), and
/// what a page of groups/projects is counted over (`GroupRoutes.listGroups`).
const _admin = [EffectiveRole(role: Role.admin, scopeType: ScopeType.global)];

typedef Handle = Future<Response> Function(Request);

EffectiveRole _role(Role role, ScopeType scope, [int? id]) =>
    EffectiveRole(role: role, scopeType: scope, scopeId: id);

void main() {
  late StructuredLogDatabase db;
  late Authorizer authorizer;
  late GroupRoutes groups;
  late ProjectRoutes projects;

  setUp(() {
    db = StructuredLogDatabase(
      NativeDatabase.memory(
        setup: (db) => db.execute('PRAGMA foreign_keys=ON;'),
      ),
    );
    authorizer = Authorizer(db);
    final audit = AuditWriter(db);
    groups = GroupRoutes(db, authorizer, audit);
    projects = ProjectRoutes(db, authorizer, audit);
  });
  tearDown(() => db.close());

  Future<int> addGroup(String name) =>
      db.into(db.groups).insert(GroupsCompanion.insert(name: name));

  Future<int> addProject(int groupId, String name) => db
      .into(db.projects)
      .insert(
        ProjectsCompanion.insert(
          groupId: groupId,
          name: name,
          retentionDays: 30,
        ),
      );

  Future<Map<String, Object?>> get(
    Handle routerOf,
    String path,
    List<EffectiveRole> roles,
  ) async {
    final response = await routerOf(
      authenticatedRequest('GET', 'http://x$path', roles: roles),
    );
    expect(response.statusCode, 200);
    return decodeJson(response);
  }

  List<int> ids(Map<String, Object?> body) => [
    for (final item in body['items']! as List)
      ((item as Map)['id'] as num).toInt(),
  ];

  /// Walks a list to its end `limit` at a time, returning every id in the
  /// order served.
  Future<List<int>> walk(
    Handle routerOf,
    String path,
    List<EffectiveRole> roles, {
    int limit = 2,
  }) async {
    final seen = <int>[];
    String? cursor;
    for (var guard = 0; guard < 1000; guard++) {
      final sep = path.contains('?') ? '&' : '?';
      final body = await get(
        routerOf,
        '$path${sep}limit=$limit${cursor == null ? '' : '&cursor=$cursor'}',
        roles,
      );
      seen.addAll(ids(body));
      cursor = body['next_cursor'] as String?;
      if (cursor == null) return seen;
    }
    fail('the cursor never ended');
  }

  group('groups', () {
    test('an admin walks every group, newest first, none twice', () async {
      final created = [for (var i = 0; i < 7; i++) await addGroup('g$i')];
      expect(
        await walk(groups.router.call, '/v1/groups', _admin),
        created.reversed.toList(),
      );
    });

    test(
      'a caller with one group among many gets it on the first page',
      () async {
        // The reason the visibility filter lives in the query: filtered after
        // the page was cut, this caller would be shown an empty page and a
        // cursor over 50 rows that are not theirs.
        final mine = await addGroup('mine');
        for (var i = 0; i < 120; i++) {
          await addGroup('other$i');
        }
        final body = await get(groups.router.call, '/v1/groups?limit=50', [
          _role(Role.user, ScopeType.group, mine),
        ]);
        expect(ids(body), [mine]);
        expect(body['next_cursor'], isNull);
      },
    );

    test('a caller with no role at all sees nothing', () async {
      await addGroup('g');
      final body = await get(groups.router.call, '/v1/groups', const []);
      expect(ids(body), isEmpty);
      expect(body['next_cursor'], isNull);
    });

    test('a name filter combines with the cursor', () async {
      final prod = [for (var i = 0; i < 3; i++) await addGroup('prod-$i')];
      await addGroup('staging');
      final first = await get(
        groups.router.call,
        '/v1/groups?name=prod&limit=1',
        _admin,
      );
      expect(ids(first), [prod.last]);
      expect(first['next_cursor'], isNotNull);
      expect(
        await walk(
          groups.router.call,
          '/v1/groups?name=prod',
          _admin,
          limit: 1,
        ),
        prod.reversed.toList(),
      );
    });

    test(
      'a group created between two pages does not disturb the cursor',
      () async {
        final created = [for (var i = 0; i < 4; i++) await addGroup('g$i')];
        final first = await get(
          groups.router.call,
          '/v1/groups?limit=2',
          _admin,
        );
        await addGroup('late');
        final second = await get(
          groups.router.call,
          '/v1/groups?limit=2&cursor=${first['next_cursor']}',
          _admin,
        );
        expect(
          [...ids(first), ...ids(second)],
          created.reversed.toList(),
          reason:
              'the new group has a larger id, so a walk downwards from the '
              'cursor never reaches it, and never skips an old one',
        );
      },
    );
  });

  group('projects', () {
    test('a caller sees a project by a grant on it or on its group', () async {
      final g1 = await addGroup('g1');
      final g2 = await addGroup('g2');
      final p1 = await addProject(g1, 'p1');
      final p2 = await addProject(g1, 'p2');
      final p3 = await addProject(g2, 'p3');
      await addProject(g2, 'p4');

      final roles = [
        _role(Role.user, ScopeType.group, g1),
        _role(Role.owner, ScopeType.project, p3),
      ];
      expect(await walk(projects.router.call, '/v1/projects', roles), [
        p3,
        p2,
        p1,
      ]);
    });

    test(
      'group_id and name narrow the page, and the cursor continues it',
      () async {
        final g1 = await addGroup('g1');
        final g2 = await addGroup('g2');
        final a = [for (var i = 0; i < 3; i++) await addProject(g1, 'api-$i')];
        await addProject(g1, 'web');
        await addProject(g2, 'api-x');

        expect(
          await walk(
            projects.router.call,
            '/v1/projects?group_id=$g1&name=api',
            _admin,
            limit: 2,
          ),
          a.reversed.toList(),
        );
      },
    );

    test('a non-integer group_id is still a 400', () async {
      await expectLater(
        projects.router.call(
          authenticatedRequest(
            'GET',
            'http://x/v1/projects?group_id=abc',
            roles: _admin,
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });
  });

  /// The SQL condition and `canRead` say the same thing two ways round; here
  /// they are made to answer the same questions.
  group('what a list shows equals what canRead allows', () {
    final roleSets =
        <String, List<EffectiveRole> Function(List<int>, List<int>)>{
          'admin': (g, p) => _admin,
          'a global user': (g, p) => [_role(Role.user, ScopeType.global)],
          'owner of one group': (g, p) => [
            _role(Role.owner, ScopeType.group, g[0]),
          ],
          'user of two groups': (g, p) => [
            _role(Role.user, ScopeType.group, g[0]),
            _role(Role.user, ScopeType.group, g[2]),
          ],
          'owner of one project': (g, p) => [
            _role(Role.owner, ScopeType.project, p[3]),
          ],
          'a project in a group they hold no grant on': (g, p) => [
            _role(Role.user, ScopeType.group, g[0]),
            _role(Role.user, ScopeType.project, p[5]),
          ],
          'no roles': (g, p) => const [],
        };

    for (final entry in roleSets.entries) {
      test(entry.key, () async {
        final gids = [for (var i = 0; i < 3; i++) await addGroup('g$i')];
        final pids = <int>[];
        final owner = <int, int>{};
        for (var i = 0; i < 6; i++) {
          final group = gids[i % 3];
          final id = await addProject(group, 'p$i');
          pids.add(id);
          owner[id] = group;
        }
        final roles = entry.value(gids, pids);

        final shownGroups = await walk(groups.router.call, '/v1/groups', roles);
        final shownProjects = await walk(
          projects.router.call,
          '/v1/projects',
          roles,
        );

        expect(shownGroups.toSet(), {
          for (final g in gids)
            if (canRead(roles, targetType: ScopeType.group, targetId: g)) g,
        });
        expect(shownProjects.toSet(), {
          for (final p in pids)
            if (canRead(
              roles,
              targetType: ScopeType.project,
              targetId: p,
              enclosingGroupId: owner[p],
            ))
              p,
        });
      });
    }
  });

  test('a caller holding thousands of grants is still answered', () async {
    // The visible set travels as bound variables; SQLite has a ceiling on
    // them, and that ceiling has to be somewhere far past any real caller.
    final g = await addGroup('g');
    final mine = await addProject(g, 'mine');
    final roles = [
      for (var i = 1; i <= 5000; i++)
        _role(Role.user, ScopeType.project, i + 100000),
      _role(Role.user, ScopeType.project, mine),
    ];
    final body = await get(projects.router.call, '/v1/projects', roles);
    expect(ids(body), [mine]);
  });

  group('every paginated list obeys the same contract', () {
    late Map<String, Future<Response> Function(String query)> lists;

    setUp(() async {
      final g = await addGroup('g');
      final p = await addProject(g, 'p');
      await db
          .into(db.projectUsage)
          .insert(ProjectUsageCompanion.insert(projectId: Value(p)));
      final store = DriftLogStore(db);
      for (var i = 0; i < 5; i++) {
        await addGroup('extra$i');
        await addProject(g, 'extra$i');
        await db
            .into(db.users)
            .insert(UsersCompanion.insert(username: 'u$i', passwordHash: 'x'));
        await AuditWriter(db).write(
          action: AuditAction.groupCreated,
          targetType: AuditTargetType.group,
          actorUserId: 1,
          targetId: i,
        );
      }
      await store.insertBatch(p, [
        for (var i = 0; i < 6; i++)
          LogEntriesCompanion.insert(
            projectId: 0,
            receivedAt: DateTime.now(),
            timestamp: DateTime.now(),
            level: 'info',
            event: 'e$i',
            sizeBytes: 1,
            contextJson: '{"event":"e$i","level":"info"}',
          ),
      ]);

      final logs = LogRoutes(db, authorizer, store, LogBroadcast());
      final users = UserRoutes(db, authorizer, AuditWriter(db));
      final audit = AuditLogRoutes(db, authorizer);
      Future<Response> call(Handle r, String path) =>
          r(authenticatedRequest('GET', 'http://x$path', roles: _admin));
      lists = {
        '/v1/groups': (q) => call(groups.router.call, '/v1/groups$q'),
        '/v1/projects': (q) => call(projects.router.call, '/v1/projects$q'),
        '/v1/users': (q) => call(users.router.call, '/v1/users$q'),
        '/v1/audit-log': (q) => call(audit.router.call, '/v1/audit-log$q'),
        '/v1/logs': (q) => call(
          logs.router.call,
          '/v1/logs?project_id=$p${q.isEmpty ? '' : '&${q.substring(1)}'}',
        ),
      };
    });

    test(
      'pages are disjoint, descending, and the last has no cursor',
      () async {
        for (final entry in lists.entries) {
          final seen = <int>[];
          String? cursor;
          var pages = 0;
          do {
            final response = await entry.value(
              '?limit=2${cursor == null ? '' : '&cursor=$cursor'}',
            );
            expect(response.statusCode, 200, reason: entry.key);
            final body = await decodeJson(response);
            seen.addAll(ids(body));
            cursor = body['next_cursor'] as String?;
            pages++;
          } while (cursor != null && pages < 50);

          expect(cursor, isNull, reason: '${entry.key}: the cursor must end');
          expect(
            seen.toSet(),
            hasLength(seen.length),
            reason: '${entry.key}: no id twice',
          );
          expect(
            seen,
            orderedEquals([...seen]..sort((a, b) => b.compareTo(a))),
            reason: '${entry.key}: newest first',
          );
          expect(seen.length, greaterThan(2), reason: entry.key);
        }
      },
    );

    test('a limit above the ceiling is brought to it', () async {
      for (final entry in lists.entries) {
        final response = await entry.value('?limit=100000');
        expect(response.statusCode, 200, reason: entry.key);
        expect(
          ids(await decodeJson(response)).length,
          lessThanOrEqualTo(maxPageSize),
          reason: entry.key,
        );
      }
    });

    test('an unusable limit or cursor is a 400 everywhere', () async {
      for (final entry in lists.entries) {
        for (final bad in [
          '?limit=0',
          '?limit=-5',
          '?limit=abc',
          '?cursor=x',
        ]) {
          await expectLater(
            entry.value(bad),
            throwsA(
              isA<ApiError>().having((e) => e.statusCode, 'statusCode', 400),
            ),
            reason: '${entry.key}$bad',
          );
        }
      }
    });
  });
}
