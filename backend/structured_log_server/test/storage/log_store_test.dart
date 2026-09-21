import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:structured_log_server/src/storage/log_store.dart';
import 'package:structured_log_server/src/storage/query.dart';
import 'package:test/test.dart';

import '../support/query_recorder.dart';

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
    test('ties every entry to the given project and returns the stored rows',
        () async {
      final inserted = await store.insertBatch(projectA, [
        entry(event: 'e1'),
        entry(event: 'e2'),
      ]);

      expect(inserted.map((r) => r.event), ['e1', 'e2']);
      expect(inserted.every((r) => r.id > 0), isTrue);
      expect(inserted.every((r) => r.projectId == projectA), isTrue);
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

  group('insertBatch, as the ingest path uses it', () {
    late Recorder recorder;
    late StructuredLogDatabase recorded;
    late DriftLogStore recordedStore;
    late int project;

    setUp(() async {
      recorder = Recorder();
      recorded = StructuredLogDatabase(
        NativeDatabase.memory(
                setup: (d) => d.execute('PRAGMA foreign_keys=ON;'))
            .interceptWith(recorder),
      );
      recordedStore = DriftLogStore(recorded);
      final g = await recorded
          .into(recorded.groups)
          .insert(GroupsCompanion.insert(name: 'g'));
      project = await recorded.into(recorded.projects).insert(
          ProjectsCompanion.insert(groupId: g, name: 'p', retentionDays: 30));
      recorder.clear();
    });
    tearDown(() => recorded.close());

    test('returns rows in order, with consecutive ids, exactly as stored',
        () async {
      // Something else in the table first, so the ids do not start at 1.
      await recordedStore.insertBatch(project, [entry(event: 'earlier')]);

      final rows = await recordedStore.insertBatch(
        project,
        [
          for (var i = 0; i < 25; i++)
            entry(event: 'e$i', level: i.isEven ? 'info' : 'error')
        ],
      );

      expect(rows.map((r) => r.event), [for (var i = 0; i < 25; i++) 'e$i']);
      expect(
        [for (var i = 1; i < rows.length; i++) rows[i].id - rows[i - 1].id],
        everyElement(1),
      );
      final stored = await (recorded.select(recorded.logEntries)
            ..where((t) => t.id.isBetweenValues(rows.first.id, rows.last.id)))
          .get();
      expect(rows, stored);
      expect(rows.first.id, greaterThan(1));
    });

    test('an empty batch touches nothing', () async {
      expect(await recordedStore.insertBatch(project, const []), isEmpty);
      expect(recorder.statements, isEmpty);
      expect(recorder.transactions, isEmpty);
    });

    test('inside the caller\'s transaction it opens none of its own', () async {
      await recorded.transaction(() async {
        await recordedStore
            .insertBatch(project, [entry(event: 'a'), entry(event: 'b')]);
      });

      // One: the caller's. A second, nested one is a SAVEPOINT, and that alone
      // cost half of an ingest batch.
      expect(recorder.transactions, ['top-level']);
    });

    test('outside a transaction it runs in one of its own, and only one',
        () async {
      await recordedStore.insertBatch(project, [entry(event: 'a')]);
      expect(recorder.transactions, ['top-level']);
    });

    test('the number of statements does not grow with the batch', () async {
      Future<int> statementsFor(int n) async {
        recorder.clear();
        await recorded.transaction(() async {
          await recordedStore.insertBatch(
              project, [for (var i = 0; i < n; i++) entry(event: 'x$i')]);
        });
        return recorder.statements.length;
      }

      final one = await statementsFor(1);
      final hundred = await statementsFor(100);
      // Before: one INSERT ... RETURNING per entry, each a round trip.
      expect(hundred, one);
    });

    test(
        'is atomic with its caller: rolling the transaction back removes the rows',
        () async {
      await expectLater(
        recorded.transaction(() async {
          await recordedStore.insertBatch(project, [entry(event: 'gone')]);
          throw StateError('the caller changes its mind');
        }),
        throwsStateError,
      );
      expect(await recorded.select(recorded.logEntries).get(), isEmpty);
    });

    test('is atomic on its own: a batch that cannot be stored stores nothing',
        () async {
      await expectLater(
        recordedStore
            .insertBatch(99999, [entry(event: 'a'), entry(event: 'b')]),
        throwsA(anything),
      );
      expect(await recorded.select(recorded.logEntries).get(), isEmpty);
    });

    test('two concurrent batches each get back their own rows', () async {
      final g2 = await recorded
          .into(recorded.groups)
          .insert(GroupsCompanion.insert(name: 'g2'));
      final other = await recorded.into(recorded.projects).insert(
          ProjectsCompanion.insert(groupId: g2, name: 'q', retentionDays: 30));

      final results = await Future.wait([
        for (var i = 0; i < 10; i++)
          recordedStore.insertBatch(i.isEven ? project : other,
              [for (var j = 0; j < 20; j++) entry(event: 'b$i-$j')]),
      ]);

      for (var i = 0; i < 10; i++) {
        expect(results[i].map((r) => r.event),
            [for (var j = 0; j < 20; j++) 'b$i-$j']);
        expect(
            results[i]
                .every((r) => r.projectId == (i.isEven ? project : other)),
            isTrue);
      }
      expect(await recorded.select(recorded.logEntries).get(), hasLength(200));
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
        LogQuery(
          projectIds: [projectA],
          filter: const LogFilter(minLevel: 'warning'),
        ),
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
        LogQuery(
          projectIds: [projectA],
          filter: const LogFilter(category: 'payments'),
        ),
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
        LogQuery(
          projectIds: [projectA],
          filter: const LogFilter(sessionId: 's-1'),
        ),
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
        LogQuery(
          projectIds: [projectA],
          filter: const LogFilter(q: 'checkout'),
        ),
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
        LogQuery(
          projectIds: [projectA],
          filter: const LogFilter(q: 'has_underscore'),
        ),
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
        LogQuery(
          projectIds: [projectA],
          filter: const LogFilter(contextEquals: {'order_id': '42'}),
        ),
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

    test('nextCursor is null on the last page, even when it is full', () async {
      await store.insertBatch(
        projectA,
        List.generate(3, (i) => entry(event: 'e$i')),
      );

      // Exactly `limit` entries left: nothing follows, and saying so is the
      // point — a cursor here would cost the client a request to find out.
      final page = await store.query(
        LogQuery(projectIds: [projectA], limit: 3),
      );
      expect(page.entries, hasLength(3));
      expect(page.nextCursor, isNull);
    });

    test('nextCursor is the last shown entry, not the probe row', () async {
      await store.insertBatch(
        projectA,
        List.generate(4, (i) => entry(event: 'e$i')),
      );

      final page = await store.query(
        LogQuery(projectIds: [projectA], limit: 3),
      );
      expect(page.entries, hasLength(3));
      expect(page.nextCursor, page.entries.last.id);

      final next = await store.query(
        LogQuery(projectIds: [projectA], limit: 3, cursor: page.nextCursor),
      );
      expect(next.entries.map((e) => e.event), ['e0']);
      expect(next.nextCursor, isNull);
    });
  });
}
