@Tags(['postgres'])
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:structured_log_server/src/storage/database.dart';
import 'package:structured_log_server/src/storage/log_store.dart';
import 'package:test/test.dart';

/// `add-postgres-backend` design.md decision 5: `DriftLogStore._insertPostgres`
/// is a genuinely separate implementation from the SQLite hot path (a
/// multi-row `INSERT ... RETURNING *` instead of `last_insert_rowid()` +
/// range read) — this file is what proves it behaves the same way the
/// SQLite path already does (`test/storage/log_store_test.dart`), against a
/// real PostgreSQL instance rather than SQLite.
///
/// Connection settings: `STRUCTURED_LOG_TEST_POSTGRES_*`, same convention
/// as `postgres_database_test.dart`.
String _env(String suffix, String fallback) =>
    Platform.environment['STRUCTURED_LOG_TEST_POSTGRES_$suffix'] ?? fallback;

final _host = _env('HOST', 'localhost');
final _port = int.parse(_env('PORT', '5432'));
final _database = _env('DATABASE', 'postgres');
final _username = _env('USERNAME', 'postgres');
final _password = Platform.environment['STRUCTURED_LOG_TEST_POSTGRES_PASSWORD'];

LogEntriesCompanion _entry({
  required String event,
  String level = 'info',
  String? category,
  String? logger,
  String? sessionId,
  int? connectionGeneration,
  DateTime? timestamp,
  String? contextJson,
}) {
  final now = timestamp ?? DateTime.utc(2026, 1, 1);
  return LogEntriesCompanion.insert(
    projectId: 0, // overwritten by DriftLogStore.insertBatch
    receivedAt: now,
    timestamp: now,
    level: level,
    event: event,
    category: Value(category),
    logger: Value(logger),
    sessionId: Value(sessionId),
    connectionGeneration: Value(connectionGeneration),
    sizeBytes: 1,
    contextJson: contextJson ?? '{}',
  );
}

void main() {
  setUpAll(() {
    if (_password == null) {
      throw StateError(
        'STRUCTURED_LOG_TEST_POSTGRES_PASSWORD must be set to run tests '
        'tagged postgres (see dart_test.yaml).',
      );
    }
  });

  late StructuredLogDatabase db;
  late DriftLogStore store;
  late int projectA;
  late int projectB;

  setUp(() async {
    db = StructuredLogDatabase.openPostgres(
      host: _host,
      port: _port,
      database: _database,
      username: _username,
      password: _password!,
      sslMode: 'disable',
    );
    // Postgres-tagged tests share one database across files/runs (no
    // per-test file the way SQLite gets `NativeDatabase.memory()`) — start
    // every test from a clean slate the same way the manual verification in
    // this session did.
    await db.customStatement(
      'TRUNCATE log_entries, projects, groups RESTART IDENTITY CASCADE',
    );
    store = DriftLogStore(db);
    final group = await db
        .into(db.groups)
        .insert(GroupsCompanion.insert(name: 'g'));
    projectA = await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            groupId: group,
            name: 'a',
            retentionDays: 30,
          ),
        );
    projectB = await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            groupId: group,
            name: 'b',
            retentionDays: 30,
          ),
        );
  });

  tearDown(() => db.close());

  test('ties every entry to the given project, returns rows in input order, '
      'with consecutive ids', () async {
    final rows = await store.insertBatch(projectA, [
      for (var i = 0; i < 10; i++)
        _entry(event: 'e$i', level: i.isEven ? 'info' : 'error'),
    ]);

    expect(rows.map((r) => r.event), [for (var i = 0; i < 10; i++) 'e$i']);
    expect(rows.every((r) => r.projectId == projectA), isTrue);
    expect([
      for (var i = 1; i < rows.length; i++) rows[i].id - rows[i - 1].id,
    ], everyElement(1));
  });

  test('nullable fields round-trip, including all-absent ones', () async {
    final rows = await store.insertBatch(projectA, [
      _entry(
        event: 'full',
        category: 'cat',
        logger: 'log',
        sessionId: 'sess',
        connectionGeneration: 3,
      ),
      _entry(event: 'bare'), // every nullable field left absent
    ]);

    expect(rows[0].category, 'cat');
    expect(rows[0].logger, 'log');
    expect(rows[0].sessionId, 'sess');
    expect(rows[0].connectionGeneration, 3);
    expect(rows[1].category, isNull);
    expect(rows[1].logger, isNull);
    expect(rows[1].sessionId, isNull);
    expect(rows[1].connectionGeneration, isNull);
  });

  test('a batch that cannot be stored stores nothing (atomic)', () async {
    await expectLater(
      store.insertBatch(99999, [_entry(event: 'a'), _entry(event: 'b')]),
      throwsA(anything),
    );
    expect(await db.select(db.logEntries).get(), isEmpty);
  });

  test('insertRows ties each entry to its own already-set projectId', () async {
    final rows = await store.insertRows([
      _entry(event: 'a').copyWith(projectId: Value(projectA)),
      _entry(event: 'b').copyWith(projectId: Value(projectB)),
      _entry(event: 'c').copyWith(projectId: Value(projectA)),
    ]);

    expect(rows.map((r) => r.event), ['a', 'b', 'c']);
    expect(rows.map((r) => r.projectId), [projectA, projectB, projectA]);
  });

  test(
    'concurrent batches each get back exactly their own rows, not a '
    'neighbor\'s — the id-adjacency risk this implementation avoids',
    () async {
      final results = await Future.wait([
        for (var i = 0; i < 5; i++)
          store.insertBatch(i.isEven ? projectA : projectB, [
            for (var j = 0; j < 10; j++) _entry(event: 'b$i-$j'),
          ]),
      ]);

      for (var i = 0; i < results.length; i++) {
        expect(results[i].map((r) => r.event), [
          for (var j = 0; j < 10; j++) 'b$i-$j',
        ], reason: 'batch $i');
      }
      // Every id assigned exactly once across all batches — proves RETURNING
      // tied each row to its own INSERT, not a range that could overlap
      // under concurrency.
      final allIds = results.expand((rows) => rows.map((r) => r.id)).toList();
      expect(allIds.toSet(), hasLength(allIds.length));
    },
  );

  test('an empty batch touches nothing', () async {
    expect(await store.insertBatch(projectA, const []), isEmpty);
  });
}
