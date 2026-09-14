import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:structured_log_server/src/storage/log_store.dart';
import 'package:structured_log_server/src/storage/query.dart';
import 'package:test/test.dart';

StructuredLogDatabase openInMemory() {
  return StructuredLogDatabase(
    NativeDatabase.memory(
      setup: (db) => db.execute('PRAGMA foreign_keys=ON;'),
    ),
  );
}

LogEntriesCompanion entry({
  required String event,
  String level = 'info',
  String? category,
  DateTime? timestamp,
  String? sessionId,
  String? contextJson,
}) {
  final now = timestamp ?? DateTime.now();
  return LogEntriesCompanion.insert(
    projectId: 0, // overwritten by DriftLogStore.insertBatch
    receivedAt: now,
    timestamp: now,
    level: level,
    event: event,
    category: Value(category),
    sessionId: Value(sessionId),
    sizeBytes: 1,
    contextJson: contextJson ?? '{}',
  );
}

void main() {
  late StructuredLogDatabase db;
  late DriftLogStore store;
  late int projectA;
  late int projectB;

  setUp(() async {
    db = openInMemory();
    store = DriftLogStore(db);
    final group = await db.into(db.groups).insert(
          GroupsCompanion.insert(name: 'g'),
        );
    projectA = await db.into(db.projects).insert(
          ProjectsCompanion.insert(
              groupId: group, name: 'a', retentionDays: 30),
        );
    projectB = await db.into(db.projects).insert(
          ProjectsCompanion.insert(
              groupId: group, name: 'b', retentionDays: 30),
        );
  });

  tearDown(() => db.close());

  group('insertBatch', () {
    test('ties every entry to the given project and returns their ids',
        () async {
      final ids = await store.insertBatch(projectA, [
        entry(event: 'e1'),
        entry(event: 'e2'),
      ]);

      expect(ids, hasLength(2));
      final rows = await db.select(db.logEntries).get();
      expect(rows.every((r) => r.projectId == projectA), isTrue);
      expect(rows.map((r) => r.event), containsAll(['e1', 'e2']));
    });

    test('nothing is inserted if a later entry in the batch fails', () async {
      // A batch of otherwise-valid companions plus one with a null column
      // that violates NOT NULL — the whole transaction must roll back.
      final badEntry = LogEntriesCompanion.insert(
        projectId: 0,
        receivedAt: DateTime.now(),
        timestamp: DateTime.now(),
        level: 'info',
        event: 'bad',
        sizeBytes: 1,
        contextJson: '{}',
      ).copyWith(level: const Value.absent()); // drops a required column

      await expectLater(
        store.insertBatch(projectA, [entry(event: 'ok'), badEntry]),
        throwsA(anything),
      );

      final rows = await db.select(db.logEntries).get();
      expect(rows, isEmpty);
    });
  });

  group('query', () {
    test('only returns entries within the requested project scope', () async {
      await store.insertBatch(projectA, [entry(event: 'in-a')]);
      await store.insertBatch(projectB, [entry(event: 'in-b')]);

      final page = await store.query(LogQuery(projectIds: [projectA]));
      expect(page.entries.map((e) => e.event), ['in-a']);
    });

    test('a group scope aggregates every project id passed in', () async {
      await store.insertBatch(projectA, [entry(event: 'in-a')]);
      await store.insertBatch(projectB, [entry(event: 'in-b')]);

      final page = await store.query(
        LogQuery(projectIds: [projectA, projectB]),
      );
      expect(
          page.entries.map((e) => e.event), unorderedEquals(['in-a', 'in-b']));
    });

    test('filters by minimum level', () async {
      await store.insertBatch(projectA, [
        entry(event: 'e-debug', level: 'debug'),
        entry(event: 'e-warning', level: 'warning'),
        entry(event: 'e-error', level: 'error'),
      ]);

      final page = await store.query(
        LogQuery(projectIds: [projectA], minLevel: 'warning'),
      );
      expect(
        page.entries.map((e) => e.event),
        unorderedEquals(['e-warning', 'e-error']),
      );
    });

    test('filters by category', () async {
      await store.insertBatch(projectA, [
        entry(event: 'e1', category: 'payments'),
        entry(event: 'e2', category: 'auth'),
      ]);

      final page = await store.query(
        LogQuery(projectIds: [projectA], category: 'payments'),
      );
      expect(page.entries.map((e) => e.event), ['e1']);
    });

    test('filters by timestamp range', () async {
      await store.insertBatch(projectA, [
        entry(event: 'old', timestamp: DateTime.utc(2020)),
        entry(event: 'in-range', timestamp: DateTime.utc(2025, 6)),
        entry(event: 'new', timestamp: DateTime.utc(2030)),
      ]);

      final page = await store.query(
        LogQuery(
          projectIds: [projectA],
          from: DateTime.utc(2024),
          to: DateTime.utc(2026),
        ),
      );
      expect(page.entries.map((e) => e.event), ['in-range']);
    });

    test('filters by correlation field', () async {
      await store.insertBatch(projectA, [
        entry(event: 'mine', sessionId: 's-1'),
        entry(event: 'not-mine', sessionId: 's-2'),
      ]);

      final page = await store.query(
        LogQuery(projectIds: [projectA], sessionId: 's-1'),
      );
      expect(page.entries.map((e) => e.event), ['mine']);
    });

    test('q searches event and the full context', () async {
      await store.insertBatch(projectA, [
        entry(event: 'checkout_failed'),
        entry(event: 'other', contextJson: '{"reason":"checkout timeout"}'),
        entry(event: 'unrelated'),
      ]);

      final page = await store.query(
        LogQuery(projectIds: [projectA], q: 'checkout'),
      );
      expect(
        page.entries.map((e) => e.event),
        unorderedEquals(['checkout_failed', 'other']),
      );
    });

    test('q escapes LIKE wildcard characters literally', () async {
      await store.insertBatch(projectA, [
        entry(event: 'has_underscore'),
        entry(event: 'hasXunderscore'),
      ]);

      final page = await store.query(
        LogQuery(projectIds: [projectA], q: 'has_underscore'),
      );
      expect(page.entries.map((e) => e.event), ['has_underscore']);
    });

    test(
        'filters by an arbitrary context field, matching string and numeric values',
        () async {
      await store.insertBatch(projectA, [
        entry(event: 'string-match', contextJson: '{"order_id":"42"}'),
        entry(event: 'numeric-match', contextJson: '{"order_id":42}'),
        entry(event: 'no-match', contextJson: '{"order_id":"43"}'),
      ]);

      final page = await store.query(
        LogQuery(projectIds: [projectA], contextEquals: {'order_id': '42'}),
      );
      expect(
        page.entries.map((e) => e.event),
        unorderedEquals(['string-match', 'numeric-match']),
      );
    });

    test('without a cursor, the newest entries come first', () async {
      await store.insertBatch(projectA, [
        entry(event: 'first'),
        entry(event: 'second'),
        entry(event: 'third'),
      ]);

      final page = await store.query(LogQuery(projectIds: [projectA]));
      expect(page.entries.map((e) => e.event), ['third', 'second', 'first']);
    });

    test('a cursor page contains only strictly older entries, no overlap',
        () async {
      await store.insertBatch(
        projectA,
        List.generate(5, (i) => entry(event: 'e$i')),
      );

      final firstPage = await store.query(
        LogQuery(projectIds: [projectA], limit: 3),
      );
      expect(firstPage.entries, hasLength(3));

      final secondPage = await store.query(
        LogQuery(
          projectIds: [projectA],
          limit: 3,
          cursor: firstPage.nextCursor,
        ),
      );
      expect(secondPage.entries, hasLength(2));

      final firstIds = firstPage.entries.map((e) => e.id).toSet();
      final secondIds = secondPage.entries.map((e) => e.id).toSet();
      expect(firstIds.intersection(secondIds), isEmpty);
      expect(secondPage.entries.every((e) => e.id < firstPage.entries.last.id),
          isTrue);
    });

    test('nextCursor is null once entries run out', () async {
      await store.insertBatch(projectA, [entry(event: 'only')]);
      final page = await store.query(LogQuery(projectIds: [projectA]));
      final next = await store.query(
        LogQuery(projectIds: [projectA], cursor: page.nextCursor),
      );
      expect(next.entries, isEmpty);
      expect(next.nextCursor, isNull);
    });
  });
}
