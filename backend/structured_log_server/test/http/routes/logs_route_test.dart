import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:shelf/shelf.dart';
import 'package:structured_log_server/src/auth/identity_provider.dart';
import 'package:structured_log_server/src/auth/principal.dart';
import 'package:structured_log_server/src/errors.dart';
import 'package:structured_log_server/src/http/routes/logs_route.dart';
import 'package:structured_log_server/src/rbac/authorizer.dart';
import 'package:structured_log_server/src/live/log_broadcast.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:structured_log_server/src/storage/log_store.dart';
import 'package:test/test.dart';

import '../../support/query_recorder.dart';
import 'test_helpers.dart';

const _admin = [EffectiveRole(role: Role.admin, scopeType: ScopeType.global)];
const _noRoles = <EffectiveRole>[];

StructuredLogDatabase openInMemory() {
  return StructuredLogDatabase(
    NativeDatabase.memory(setup: (db) => db.execute('PRAGMA foreign_keys=ON;')),
  );
}

Request ingestRequest(int projectId, Object body) {
  return projectKeyRequest(
    'POST',
    'http://x/v1/logs',
    projectId: projectId,
    jsonBody: body,
  );
}

void main() {
  late StructuredLogDatabase db;
  late Authorizer authorizer;
  late LogStore logStore;
  late int groupId;
  late int projectId;
  late LogRoutes routes;

  setUp(() async {
    db = openInMemory();
    authorizer = Authorizer(db);
    logStore = DriftLogStore(db);
    routes = LogRoutes(db, authorizer, logStore, LogBroadcast());
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
    await db
        .into(db.projectUsage)
        .insert(ProjectUsageCompanion.insert(projectId: Value(projectId)));
  });
  tearDown(() => db.close());

  group('ingestLogs', () {
    test(
      'a well-formed batch is accepted and persisted, project_usage updated',
      () async {
        final response = await routes.router.call(
          ingestRequest(projectId, [
            {
              'event': 'e1',
              'level': 'info',
              'timestamp': '2026-01-01T00:00:00Z',
            },
            {
              'event': 'e2',
              'level': 'error',
              'timestamp': '2026-01-01T00:00:01Z',
            },
          ]),
        );

        expect(response.statusCode, 202);
        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body['accepted'], 2);
        expect(body['rejected'], isEmpty);

        final rows = await db.select(db.logEntries).get();
        expect(rows, hasLength(2));

        final usage = await (db.select(
          db.projectUsage,
        )..where((t) => t.projectId.equals(projectId))).getSingle();
        expect(usage.entryCount, 2);
      },
    );

    test(
      'a partially invalid batch reports rejections and still returns 202',
      () async {
        final response = await routes.router.call(
          ingestRequest(projectId, [
            {
              'event': 'ok',
              'level': 'info',
              'timestamp': '2026-01-01T00:00:00Z',
            },
            {'event': 'bad'}, // missing level
          ]),
        );

        expect(response.statusCode, 202);
        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body['accepted'], 1);
        expect((body['rejected'] as List), hasLength(1));
        expect((body['rejected'] as List).single, {
          'index': 1,
          'error': 'validation_error',
          'message':
              'level: must be one of trace, debug, info, warning, error, critical',
        });
      },
    );

    test(
      'ingestion into a blocked project is rejected wholesale with 403',
      () async {
        await (db.update(db.projects)..where((t) => t.id.equals(projectId)))
            .write(const ProjectsCompanion(isBlocked: Value(true)));

        await expectLater(
          routes.router.call(
            ingestRequest(projectId, [
              {
                'event': 'e',
                'level': 'info',
                'timestamp': '2026-01-01T00:00:00Z',
              },
            ]),
          ),
          throwsA(
            isA<ApiError>()
                .having((e) => e.statusCode, 'statusCode', 403)
                .having((e) => e.code, 'code', 'project_blocked'),
          ),
        );

        expect(await db.select(db.logEntries).get(), isEmpty);
      },
    );

    test(
      'one ingest batch is one transaction, and its statements do not grow with it',
      () async {
        final recorder = Recorder();
        final recorded = StructuredLogDatabase(
          NativeDatabase.memory(
            setup: (d) => d.execute('PRAGMA foreign_keys=ON;'),
          ).interceptWith(recorder),
        );
        addTearDown(recorded.close);
        final g = await recorded
            .into(recorded.groups)
            .insert(GroupsCompanion.insert(name: 'g'));
        final p = await recorded
            .into(recorded.projects)
            .insert(
              ProjectsCompanion.insert(
                groupId: g,
                name: 'p',
                retentionDays: 30,
              ),
            );
        await recorded
            .into(recorded.projectUsage)
            .insert(ProjectUsageCompanion.insert(projectId: Value(p)));
        final recordedRoutes = LogRoutes(
          recorded,
          Authorizer(recorded),
          DriftLogStore(recorded),
          LogBroadcast(),
        );

        Future<int> statementsFor(int n) async {
          recorder.clear();
          final response = await recordedRoutes.router.call(
            ingestRequest(p, [
              for (var i = 0; i < n; i++)
                {
                  'event': 'e$i',
                  'level': 'info',
                  'timestamp': '2026-01-01T00:00:00Z',
                },
            ]),
          );
          expect(response.statusCode, 202);
          // The one transaction the route opens — a second, inside it, is a
          // SAVEPOINT (what `insertBatch` used to add).
          expect(recorder.transactions, ['top-level']);
          return recorder.statements.length;
        }

        final one = await statementsFor(1);
        final hundred = await statementsFor(100);
        expect(
          hundred,
          one,
          reason: 'a round trip per entry is what this replaced',
        );
      },
    );

    group('concurrent requests are committed together', () {
      Map<String, Object?> one(String event) => {
        'event': event,
        'level': 'info',
        'timestamp': '2026-01-01T00:00:00Z',
      };

      Future<List<Map>> fire(LogRoutes r, int project, int n) async {
        final responses = await Future.wait([
          for (var i = 0; i < n; i++)
            r.router.call(ingestRequest(project, [one('e$i')])),
        ]);
        return [
          for (final response in responses)
            jsonDecode(await response.readAsString()) as Map,
        ];
      }

      test('forty single-entry requests need far fewer transactions', () async {
        final recorder = Recorder();
        final recorded = StructuredLogDatabase(
          NativeDatabase.memory(
            setup: (d) => d.execute('PRAGMA foreign_keys=ON;'),
          ).interceptWith(recorder),
        );
        addTearDown(recorded.close);
        final g = await recorded
            .into(recorded.groups)
            .insert(GroupsCompanion.insert(name: 'g'));
        final p = await recorded
            .into(recorded.projects)
            .insert(
              ProjectsCompanion.insert(
                groupId: g,
                name: 'p',
                retentionDays: 30,
              ),
            );
        await recorded
            .into(recorded.projectUsage)
            .insert(ProjectUsageCompanion.insert(projectId: Value(p)));
        final recordedRoutes = LogRoutes(
          recorded,
          Authorizer(recorded),
          DriftLogStore(recorded),
          LogBroadcast(),
        );
        recorder.clear();

        final bodies = await fire(recordedRoutes, p, 40);

        expect(bodies.every((b) => b['accepted'] == 1), isTrue);
        expect(await recorded.select(recorded.logEntries).get(), hasLength(40));
        final usage = await recorded.select(recorded.projectUsage).getSingle();
        expect(usage.entryCount, 40);
        // Requests that arrive while one transaction runs join the next.
        expect(recorder.transactions.length, lessThan(40 ~/ 2));
        expect(recorder.transactions, everyElement('top-level'));
        expect(
          recordedRoutes.ingestCoordinator.groupsCommitted,
          recorder.transactions.length,
        );
      });

      test(
        'a quota holds exactly across requests committed together',
        () async {
          await (db.update(db.projects)..where((t) => t.id.equals(projectId)))
              .write(const ProjectsCompanion(maxEntries: Value(10)));

          final bodies = await fire(routes, projectId, 30);

          expect(bodies.fold<int>(0, (n, b) => n + (b['accepted'] as int)), 10);
          expect(await db.select(db.logEntries).get(), hasLength(10));
          final usage = await (db.select(
            db.projectUsage,
          )..where((t) => t.projectId.equals(projectId))).getSingle();
          expect(usage.entryCount, 10);
        },
      );

      test('what is published is in id order across projects', () async {
        final other = await db
            .into(db.projects)
            .insert(
              ProjectsCompanion.insert(
                groupId: groupId,
                name: 'q',
                retentionDays: 30,
              ),
            );
        await db
            .into(db.projectUsage)
            .insert(ProjectUsageCompanion.insert(projectId: Value(other)));
        final broadcast = LogBroadcast();
        final seen = <int>[];
        final subscription = broadcast.stream.listen((e) => seen.add(e.id));
        addTearDown(subscription.cancel);
        final shared = LogRoutes(db, authorizer, logStore, broadcast);

        // Alternating projects, all at once: a group subscription drops an
        // entry whose id is below the last one it delivered.
        await Future.wait([
          for (var i = 0; i < 40; i++)
            shared.router.call(
              ingestRequest(i.isEven ? projectId : other, [one('e$i')]),
            ),
        ]);
        await Future<void>.delayed(Duration.zero);

        expect(seen, hasLength(40));
        expect(seen, [...seen]..sort());
      });
    });

    test('a body streamed past the limit is refused while reading', () async {
      final capped = LogRoutes(
        db,
        authorizer,
        logStore,
        LogBroadcast(),
        maxBodyBytes: 64,
      );
      var chunks = 0;
      Stream<List<int>> endless() async* {
        while (true) {
          chunks++;
          yield List.filled(32, 32);
        }
      }

      await expectLater(
        capped.router.call(
          Request(
            'POST',
            Uri.parse('http://x/v1/logs'),
            body: endless(),
            context: {
              'structured_log_server.principal': ProjectPrincipal(projectId),
            },
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 413)),
      );
      expect(chunks, lessThan(10));
    });

    test('concurrent batches cannot together exceed max_entries', () async {
      await (db.update(db.projects)..where((t) => t.id.equals(projectId)))
          .write(const ProjectsCompanion(maxEntries: Value(5)));

      Future<int> post() async {
        final response = await routes.router.call(
          ingestRequest(projectId, [
            for (var i = 0; i < 4; i++)
              {
                'event': 'e$i',
                'level': 'info',
                'timestamp': '2026-01-01T00:00:00Z',
              },
          ]),
        );
        final body = jsonDecode(await response.readAsString()) as Map;
        return body['accepted'] as int;
      }

      // Four at once, each alone within the quota; judged against one shared
      // snapshot they would all pass and store sixteen.
      final accepted = await Future.wait([post(), post(), post(), post()]);

      expect(accepted.reduce((a, b) => a + b), 5);
      expect((await db.select(db.logEntries).get()).length, 5);
      final usage = await (db.select(db.projectUsage)).getSingle();
      expect(usage.entryCount, 5);
    });

    test(
      'a body over the size limit is rejected with 413, nothing stored',
      () async {
        // The cap is a constructor field now — annotated handlers may not take
        // optional parameters.
        final capped = LogRoutes(
          db,
          authorizer,
          logStore,
          LogBroadcast(),
          maxBodyBytes: 5,
        );
        await expectLater(
          capped.router.call(
            ingestRequest(projectId, [
              {
                'event': 'e',
                'level': 'info',
                'timestamp': '2026-01-01T00:00:00Z',
              },
            ]),
          ),
          throwsA(
            isA<ApiError>().having((e) => e.statusCode, 'statusCode', 413),
          ),
        );
        expect(await db.select(db.logEntries).get(), isEmpty);
      },
    );

    test('a non-array body is rejected with 400', () async {
      await expectLater(
        routes.router.call(ingestRequest(projectId, {'not': 'an array'})),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });

    test('a body that is not JSON at all is rejected with 400', () async {
      // Not a variation on the one above: a bare jsonDecode threw
      // FormatException here, which left the handler as a 500 and a stack
      // trace in the log for anything a client happened to send.
      await expectLater(
        routes.router.call(
          Request(
            'POST',
            Uri.parse('http://x/v1/logs'),
            body: '{"event": "truncated"',
            context: {
              'structured_log_server.principal': ProjectPrincipal(projectId),
            },
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });
  });

  group('queryLogs', () {
    Future<void> seedLogs() async {
      await logStore.insertBatch(projectId, [
        LogEntriesCompanion.insert(
          projectId: 0,
          receivedAt: DateTime.now(),
          timestamp: DateTime.now(),
          level: 'info',
          event: 'e1',
          sizeBytes: 1,
          contextJson: '{"event":"e1","level":"info"}',
        ),
      ]);
    }

    test('requires exactly one of project_id/group_id', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest('GET', 'http://x/v1/logs', roles: _admin),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });

    test('rejects both project_id and group_id given together', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'GET',
            'http://x/v1/logs?project_id=$projectId&group_id=$groupId',
            roles: _admin,
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 400)),
      );
    });

    test('an unusable limit or cursor is a 400', () async {
      await seedLogs();
      for (final bad in ['limit=0', 'limit=-5', 'limit=abc', 'cursor=nope']) {
        await expectLater(
          routes.router.call(
            authenticatedRequest(
              'GET',
              'http://x/v1/logs?project_id=$projectId&$bad',
              roles: _admin,
            ),
          ),
          throwsA(
            isA<ApiError>().having((e) => e.statusCode, 'statusCode', 400),
          ),
          reason: bad,
        );
      }
    });

    test('a full last page carries no cursor', () async {
      await seedLogs();
      final response = await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/logs?project_id=$projectId&limit=1',
          roles: _admin,
        ),
      );
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['items'], hasLength(1));
      expect(body['next_cursor'], isNull);
    });

    test('an authorized project_id query returns matching entries', () async {
      await seedLogs();
      final response = await routes.router.call(
        authenticatedRequest(
          'GET',
          'http://x/v1/logs?project_id=$projectId',
          roles: _admin,
        ),
      );
      final body = jsonDecode(await response.readAsString()) as Map;
      final items = body['items'] as List;
      expect(items, hasLength(1));
      expect((items.single as Map)['event'], 'e1');
      expect((items.single as Map)['project_id'], projectId);
    });

    test('no access to the project scope is rejected with 403', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'GET',
            'http://x/v1/logs?project_id=$projectId',
            roles: _noRoles,
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('an unknown project_id is rejected with 404', () async {
      await expectLater(
        routes.router.call(
          authenticatedRequest(
            'GET',
            'http://x/v1/logs?project_id=999999',
            roles: _admin,
          ),
        ),
        throwsA(isA<ApiError>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test(
      'a directly-queried blocked project is rejected with project_blocked',
      () async {
        await (db.update(db.projects)..where((t) => t.id.equals(projectId)))
            .write(const ProjectsCompanion(isBlocked: Value(true)));
        await expectLater(
          routes.router.call(
            authenticatedRequest(
              'GET',
              'http://x/v1/logs?project_id=$projectId',
              roles: _admin,
            ),
          ),
          throwsA(
            isA<ApiError>()
                .having((e) => e.statusCode, 'statusCode', 403)
                .having((e) => e.code, 'code', 'project_blocked'),
          ),
        );
      },
    );

    test(
      'a group_id query silently excludes a blocked project instead of failing',
      () async {
        await seedLogs();
        await (db.update(db.projects)..where((t) => t.id.equals(projectId)))
            .write(const ProjectsCompanion(isBlocked: Value(true)));

        final response = await routes.router.call(
          authenticatedRequest(
            'GET',
            'http://x/v1/logs?group_id=$groupId',
            roles: _admin,
          ),
        );
        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body['items'], isEmpty);
      },
    );

    test(
      'a group with no visible non-blocked projects returns an empty page, not an error',
      () async {
        final emptyGroup = await db
            .into(db.groups)
            .insert(GroupsCompanion.insert(name: 'empty'));
        final response = await routes.router.call(
          authenticatedRequest(
            'GET',
            'http://x/v1/logs?group_id=$emptyGroup',
            roles: _admin,
          ),
        );
        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body['items'], isEmpty);
        expect(body['next_cursor'], isNull);
      },
    );

    test(
      'a context.<key> query parameter filters on the custom field',
      () async {
        await logStore.insertBatch(projectId, [
          LogEntriesCompanion.insert(
            projectId: 0,
            receivedAt: DateTime.now(),
            timestamp: DateTime.now(),
            level: 'info',
            event: 'has-order',
            sizeBytes: 1,
            contextJson: '{"event":"has-order","order_id":"ord_1"}',
          ),
          LogEntriesCompanion.insert(
            projectId: 0,
            receivedAt: DateTime.now(),
            timestamp: DateTime.now(),
            level: 'info',
            event: 'no-order',
            sizeBytes: 1,
            contextJson: '{"event":"no-order"}',
          ),
        ]);

        final response = await routes.router.call(
          authenticatedRequest(
            'GET',
            'http://x/v1/logs?project_id=$projectId&context.order_id=ord_1',
            roles: _admin,
          ),
        );
        final body = jsonDecode(await response.readAsString()) as Map;
        final items = body['items'] as List;
        expect(items, hasLength(1));
        expect((items.single as Map)['event'], 'has-order');
      },
    );
  });

  group('healthCheck', () {
    test('returns 200 with a status field', () async {
      final response = await routes.router.call(
        Request('GET', Uri.parse('http://x/healthz')),
      );
      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['status'], 'ok');
    });
  });
}
