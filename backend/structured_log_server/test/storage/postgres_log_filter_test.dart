@Tags(['postgres'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:structured_log_server/src/storage/database.dart';
import 'package:structured_log_server/src/storage/log_store.dart';
import 'package:structured_log_server/src/storage/query.dart';
import 'package:test/test.dart';

/// `context.<key>` filtering (`LogFilter.contextEquals`) is the one
/// dialect-sensitive condition in `appendConditions` — `json_extract` (used
/// for SQLite, `test/storage/log_filter_test.dart`) doesn't exist on
/// Postgres at all, so it's ported to `jsonb`'s `#>>` operator
/// (`add-postgres-backend` design.md, task 4.3). Everything else `LogFilter`
/// does is already covered by `query_dialect_test.dart` (placeholder
/// numbering) and the SQLite-side test (the conditions themselves) — this
/// file is only about the one expression that's genuinely different.
///
/// Connection settings: `STRUCTURED_LOG_TEST_POSTGRES_*`, same convention as
/// the other Postgres-tagged storage tests.
String _env(String suffix, String fallback) =>
    Platform.environment['STRUCTURED_LOG_TEST_POSTGRES_$suffix'] ?? fallback;

final _host = _env('HOST', 'localhost');
final _port = int.parse(_env('PORT', '5432'));
final _database = _env('DATABASE', 'postgres');
final _username = _env('USERNAME', 'postgres');
final _password = Platform.environment['STRUCTURED_LOG_TEST_POSTGRES_PASSWORD'];

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
  late int projectId;

  setUp(() async {
    db = StructuredLogDatabase.openPostgres(
      host: _host,
      port: _port,
      database: _database,
      username: _username,
      password: _password!,
      sslMode: 'disable',
    );
    await db.customStatement(
      'TRUNCATE log_entries, projects, groups RESTART IDENTITY CASCADE',
    );
    store = DriftLogStore(db);
    final groupId = await db
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
    await store.insertBatch(projectId, [
      LogEntriesCompanion.insert(
        projectId: 0,
        receivedAt: DateTime.utc(2026, 1, 1),
        timestamp: DateTime.utc(2026, 1, 1),
        level: 'info',
        event: 'checkout started',
        sizeBytes: 10,
        contextJson: jsonEncode({
          'order_id': 42,
          'flagged': true,
          'nested': {'a': 'b'},
        }),
      ),
      LogEntriesCompanion.insert(
        projectId: 0,
        receivedAt: DateTime.utc(2026, 1, 2),
        timestamp: DateTime.utc(2026, 1, 2),
        level: 'info',
        event: 'checkout failed',
        sizeBytes: 10,
        contextJson: jsonEncode({'order_id': '42'}),
      ),
      LogEntriesCompanion.insert(
        projectId: 0,
        receivedAt: DateTime.utc(2026, 1, 3),
        timestamp: DateTime.utc(2026, 1, 3),
        level: 'info',
        event: 'unrelated',
        sizeBytes: 10,
        contextJson: jsonEncode({'order_id': null}),
      ),
    ]);
  });

  tearDown(() => db.close());

  Future<Set<String>> select(LogFilter filter) async {
    final page = await store.query(
      LogQuery(projectIds: [projectId], filter: filter),
    );
    return page.entries.map((e) => e.event).toSet();
  }

  test(
    'matches a number and its string form alike, from either column',
    () async {
      expect(await select(const LogFilter(contextEquals: {'order_id': '42'})), {
        'checkout started',
        'checkout failed',
      });
    },
  );

  test('a JSON null value never matches, on Postgres either', () async {
    expect(
      await select(const LogFilter(contextEquals: {'order_id': 'null'})),
      isEmpty,
    );
  });

  test('a missing key matches nothing', () async {
    expect(
      await select(const LogFilter(contextEquals: {'nope': 'x'})),
      isEmpty,
    );
  });

  test(
    'a nested key uses the dotted path, same convention as SQLite',
    () async {
      expect(await select(const LogFilter(contextEquals: {'nested.a': 'b'})), {
        'checkout started',
      });
    },
  );

  test(
    'a JSON boolean reads as "true"/"false" here — the opposite of SQLite\'s '
    '1/0 (documented, accepted asymmetry, log_filter.dart)',
    () async {
      expect(
        await select(const LogFilter(contextEquals: {'flagged': 'true'})),
        {'checkout started'},
      );
      expect(
        await select(const LogFilter(contextEquals: {'flagged': '1'})),
        isEmpty,
      );
    },
  );
}
