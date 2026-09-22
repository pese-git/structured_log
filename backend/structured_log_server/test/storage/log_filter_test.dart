import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:structured_log_server/src/storage/log_store.dart';
import 'package:structured_log_server/src/storage/query.dart';
import 'package:test/test.dart';

StructuredLogDatabase openInMemory() {
  return StructuredLogDatabase(
    NativeDatabase.memory(setup: (db) => db.execute('PRAGMA foreign_keys=ON;')),
  );
}

/// The entries every case below is evaluated against — deliberately varied
/// on each field the filter touches, including the null/absent cases where
/// SQL's three-valued logic is easy to get wrong in Dart.
final _entries = <({String event, LogEntriesCompanion row})>[
  (
    event: 'checkout started',
    row: LogEntriesCompanion.insert(
      projectId: 0,
      receivedAt: DateTime.utc(2026, 1, 1),
      timestamp: DateTime.utc(2026, 1, 1),
      level: 'info',
      event: 'checkout started',
      category: const Value('payments'),
      logger: const Value('checkout'),
      sessionId: const Value('s-1'),
      sizeBytes: 10,
      contextJson: jsonEncode({'order_id': 42, 'flagged': true}),
    ),
  ),
  (
    event: 'CHECKOUT failed',
    row: LogEntriesCompanion.insert(
      projectId: 0,
      receivedAt: DateTime.utc(2026, 1, 2),
      timestamp: DateTime.utc(2026, 1, 2),
      level: 'error',
      event: 'CHECKOUT failed',
      category: const Value('payments'),
      sizeBytes: 10,
      contextJson: jsonEncode({'order_id': '42'}),
    ),
  ),
  (
    event: 'no category at all',
    row: LogEntriesCompanion.insert(
      projectId: 0,
      receivedAt: DateTime.utc(2026, 1, 3),
      timestamp: DateTime.utc(2026, 1, 3),
      level: 'debug',
      event: 'no category at all',
      sizeBytes: 10,
      contextJson: jsonEncode({
        'order_id': null,
        'nested': {'a': 1},
      }),
    ),
  ),
  (
    event: 'has_underscore',
    row: LogEntriesCompanion.insert(
      projectId: 0,
      receivedAt: DateTime.utc(2026, 1, 4),
      timestamp: DateTime.utc(2026, 1, 4),
      level: 'critical',
      event: 'has_underscore',
      logger: const Value('checkout'),
      sizeBytes: 10,
      contextJson: jsonEncode(<String, Object?>{}),
    ),
  ),
];

/// Every filter shape worth checking, with the events it must select.
///
/// The expectation is written out rather than derived, so that the group
/// below catches both kinds of failure: a hand-written expectation catches
/// the two paths being wrong in the same way, and comparing them to each
/// other catches them drifting apart.
const _cases = <(String, LogFilter, List<String>)>[
  ('empty', LogFilter(), _all),
  (
    'minLevel info',
    LogFilter(minLevel: 'info'),
    ['checkout started', 'CHECKOUT failed', 'has_underscore'],
  ),
  ('minLevel critical', LogFilter(minLevel: 'critical'), ['has_underscore']),
  ('minLevel trace', LogFilter(minLevel: 'trace'), _all),
  (
    'category',
    LogFilter(category: 'payments'),
    ['checkout started', 'CHECKOUT failed'],
  ),
  (
    'logger',
    LogFilter(logger: 'checkout'),
    ['checkout started', 'has_underscore'],
  ),
  ('sessionId', LogFilter(sessionId: 's-1'), ['checkout started']),
  ('sessionId absent', LogFilter(sessionId: 'nobody'), []),
  (
    'q is case-insensitive',
    LogFilter(q: 'checkout'),
    ['checkout started', 'CHECKOUT failed'],
  ),
  (
    'q is case-insensitive the other way',
    LogFilter(q: 'CHECKOUT'),
    ['checkout started', 'CHECKOUT failed'],
  ),
  (
    'q treats _ literally, not as a LIKE wildcard',
    LogFilter(q: 'has_underscore'),
    ['has_underscore'],
  ),
  (
    'context matches a number and its string form alike',
    LogFilter(contextEquals: {'order_id': '42'}),
    ['checkout started', 'CHECKOUT failed'],
  ),
  (
    'context JSON null never matches',
    LogFilter(contextEquals: {'order_id': 'null'}),
    [],
  ),
  // SQLite has no boolean type: json_extract yields 1/0, so `true` is not
  // the value to search for. Both paths must agree on that.
  (
    'context boolean reads as 1',
    LogFilter(contextEquals: {'flagged': '1'}),
    ['checkout started'],
  ),
  (
    'context boolean is not "true"',
    LogFilter(contextEquals: {'flagged': 'true'}),
    [],
  ),
  ('context missing key', LogFilter(contextEquals: {'nope': 'x'}), []),
  (
    'combined',
    LogFilter(minLevel: 'info', category: 'payments'),
    ['checkout started', 'CHECKOUT failed'],
  ),
];

const _all = [
  'checkout started',
  'CHECKOUT failed',
  'no category at all',
  'has_underscore',
];

void main() {
  late StructuredLogDatabase db;
  late LogStore store;
  late int projectId;
  late List<LogEntry> stored;

  setUp(() async {
    db = openInMemory();
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
    await store.insertBatch(projectId, _entries.map((e) => e.row).toList());
    stored = (await store.query(LogQuery(projectIds: [projectId]))).entries;
    expect(stored, hasLength(_entries.length));
  });
  tearDown(() => db.close());

  // The whole point of LogFilter is that `GET /v1/logs` and
  // `GET /v1/logs/stream` cannot disagree about which entries a caller
  // asked for (`design.md` decision 29). Asserting each path against its
  // own hand-written expectation would not catch them drifting apart, so
  // this asserts them against *each other*, over the same rows.
  group('SQL and the in-memory predicate select the same entries', () {
    for (final (name, filter, expected) in _cases) {
      test(name, () async {
        final fromSql = await store.query(
          LogQuery(projectIds: [projectId], filter: filter),
        );
        final bySql = fromSql.entries.map((e) => e.event).toSet();
        final byPredicate = stored.where(filter.matches).map((e) => e.event);

        expect(bySql, expected.toSet(), reason: 'SQL path');
        expect(byPredicate.toSet(), expected.toSet(), reason: 'predicate path');
      });
    }
  });

  group('level validation', () {
    test('isValidLevel accepts every known level and nothing else', () {
      for (final level in logLevelOrder) {
        expect(LogFilter.isValidLevel(level), isTrue, reason: level);
      }
      expect(LogFilter.isValidLevel('bogus'), isFalse);
      expect(LogFilter.isValidLevel('INFO'), isFalse);
    });

    test('an unknown minLevel fails by name rather than as a RangeError', () {
      expect(
        () => buildLogQuerySql(
          LogQuery(
            projectIds: const [1],
            filter: const LogFilter(minLevel: 'bogus'),
          ),
          dialect: SqlDialect.sqlite,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('an entry whose level is unknown never passes a level filter', () {
      final unknown = stored.first.copyWith(level: 'chatter');
      expect(const LogFilter(minLevel: 'trace').matches(unknown), isFalse);
    });
  });

  group('afterId', () {
    test('reads forward from the given id, oldest first', () async {
      final all = stored.toList()..sort((a, b) => a.id.compareTo(b.id));
      final page = await store.query(
        LogQuery(projectIds: [projectId], afterId: all[1].id),
      );
      expect(page.entries.map((e) => e.id), [all[2].id, all[3].id]);
    });

    test('is exclusive of the given id', () async {
      final all = stored.toList()..sort((a, b) => a.id.compareTo(b.id));
      final page = await store.query(
        LogQuery(projectIds: [projectId], afterId: all.last.id),
      );
      expect(page.entries, isEmpty);
    });

    test('applies the same filter as a backward page', () async {
      final page = await store.query(
        LogQuery(
          projectIds: [projectId],
          filter: const LogFilter(minLevel: 'error'),
          afterId: 0,
        ),
      );
      expect(page.entries.map((e) => e.event), [
        'CHECKOUT failed',
        'has_underscore',
      ]);
    });
  });
}
