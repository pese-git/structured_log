import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_server/src/retention/purge_job.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

StructuredLogDatabase openInMemory() {
  return StructuredLogDatabase(
    NativeDatabase.memory(
      setup: (db) => db.execute('PRAGMA foreign_keys=ON;'),
    ),
  );
}

final _now = DateTime.utc(2026, 6, 1);

void main() {
  late StructuredLogDatabase db;
  late int groupId;

  DateTime clock() => _now;

  Future<int> newProject(
      {required int retentionDays, String name = 'p'}) async {
    final id = await db.into(db.projects).insert(
          ProjectsCompanion.insert(
            groupId: groupId,
            name: name,
            retentionDays: retentionDays,
          ),
        );
    await db.into(db.projectUsage).insert(
          ProjectUsageCompanion.insert(projectId: Value(id)),
        );
    return id;
  }

  /// Inserts an entry received [ageDays] ago and keeps `project_usage` in
  /// step, the way ingestion does.
  Future<int> addEntry(
    int projectId, {
    required int ageDays,
    int sizeBytes = 100,
    String event = 'e',
  }) async {
    final id = await db.into(db.logEntries).insert(
          LogEntriesCompanion.insert(
            projectId: projectId,
            receivedAt: _now.subtract(Duration(days: ageDays)),
            timestamp: _now.subtract(Duration(days: ageDays)),
            level: 'info',
            event: event,
            sizeBytes: sizeBytes,
            contextJson: '{}',
          ),
        );
    await (db.update(db.projectUsage)
          ..where((t) => t.projectId.equals(projectId)))
        .write(
      ProjectUsageCompanion.custom(
        entryCount: db.projectUsage.entryCount + const Constant(1),
        totalBytes: db.projectUsage.totalBytes + Constant(sizeBytes),
      ),
    );
    return id;
  }

  Future<ProjectUsageData> usageOf(int projectId) =>
      (db.select(db.projectUsage)..where((t) => t.projectId.equals(projectId)))
          .getSingle();

  Future<List<String>> eventsOf(int projectId) async {
    final rows = await (db.select(db.logEntries)
          ..where((t) => t.projectId.equals(projectId)))
        .get();
    return rows.map((e) => e.event).toList();
  }

  setUp(() async {
    db = openInMemory();
    groupId =
        await db.into(db.groups).insert(GroupsCompanion.insert(name: 'g'));
  });
  tearDown(() => db.close());

  group('what gets deleted', () {
    test('an entry older than its retention window goes', () async {
      final project = await newProject(retentionDays: 30);
      await addEntry(project, ageDays: 31, event: 'stale');

      final outcome = await purgeExpiredEntries(db, clock: clock);

      expect(await eventsOf(project), isEmpty);
      expect(outcome.deletedEntries, 1);
    });

    test('an entry inside the window stays', () async {
      final project = await newProject(retentionDays: 30);
      await addEntry(project, ageDays: 29, event: 'fresh');

      final outcome = await purgeExpiredEntries(db, clock: clock);

      expect(await eventsOf(project), ['fresh']);
      expect(outcome.deletedEntries, 0);
      expect(outcome.isEmpty, isTrue);
    });

    test('the horizon is each project\'s own, not a shared one', () async {
      // Two projects, same entry age, different retention: exactly the case
      // a single global cutoff would get wrong.
      final shortLived = await newProject(retentionDays: 7, name: 'short');
      final longLived = await newProject(retentionDays: 90, name: 'long');
      await addEntry(shortLived, ageDays: 30, event: 'short-stale');
      await addEntry(longLived, ageDays: 30, event: 'long-fresh');

      await purgeExpiredEntries(db, clock: clock);

      expect(await eventsOf(shortLived), isEmpty);
      expect(await eventsOf(longLived), ['long-fresh']);
    });

    test('mixed ages in one project: only the old ones go', () async {
      final project = await newProject(retentionDays: 10);
      await addEntry(project, ageDays: 20, event: 'old-1');
      await addEntry(project, ageDays: 11, event: 'old-2');
      await addEntry(project, ageDays: 9, event: 'kept-1');
      await addEntry(project, ageDays: 0, event: 'kept-2');

      final outcome = await purgeExpiredEntries(db, clock: clock);

      expect(await eventsOf(project), ['kept-1', 'kept-2']);
      expect(outcome.deletedEntries, 2);
      expect(outcome.affectedProjects, 1);
    });

    test('a database with nothing to purge reports an empty outcome', () async {
      await newProject(retentionDays: 30);
      final outcome = await purgeExpiredEntries(db, clock: clock);

      expect(outcome.isEmpty, isTrue);
      expect(outcome.affectedProjects, 0);
    });
  });

  group('usage counters', () {
    test('come down by exactly what was removed', () async {
      final project = await newProject(retentionDays: 10);
      await addEntry(project, ageDays: 20, sizeBytes: 300);
      await addEntry(project, ageDays: 20, sizeBytes: 200);
      await addEntry(project, ageDays: 1, sizeBytes: 50);

      final before = await usageOf(project);
      expect(before.entryCount, 3);
      expect(before.totalBytes, 550);

      final outcome = await purgeExpiredEntries(db, clock: clock);

      final after = await usageOf(project);
      expect(after.entryCount, 1, reason: 'only the fresh entry remains');
      expect(after.totalBytes, 50);
      expect(outcome.freedBytes, 500);
    });

    test('another project\'s counters are untouched', () async {
      final purged = await newProject(retentionDays: 1, name: 'a');
      final other = await newProject(retentionDays: 365, name: 'b');
      await addEntry(purged, ageDays: 10, sizeBytes: 100);
      await addEntry(other, ageDays: 10, sizeBytes: 700);

      await purgeExpiredEntries(db, clock: clock);

      expect((await usageOf(other)).entryCount, 1);
      expect((await usageOf(other)).totalBytes, 700);
    });

    test('a counter that already drifted low is clamped, not driven negative',
        () async {
      // If a counter ever understates what is stored, subtracting the real
      // size would take it below zero — and a negative total reads as an
      // enormous amount of free quota.
      final project = await newProject(retentionDays: 1);
      await addEntry(project, ageDays: 10, sizeBytes: 500);
      await (db.update(db.projectUsage)
            ..where((t) => t.projectId.equals(project.toInt())))
          .write(const ProjectUsageCompanion(
        entryCount: Value(0),
        totalBytes: Value(0),
      ));

      await purgeExpiredEntries(db, clock: clock);

      final after = await usageOf(project);
      expect(after.entryCount, 0);
      expect(after.totalBytes, 0);
    });

    test('purging frees room under a quota that was full', () async {
      final project = await newProject(retentionDays: 5);
      for (var i = 0; i < 4; i++) {
        await addEntry(project, ageDays: 10, sizeBytes: 100, event: 'old-$i');
      }
      expect((await usageOf(project)).entryCount, 4);

      await purgeExpiredEntries(db, clock: clock);

      expect((await usageOf(project)).entryCount, 0);
      expect((await usageOf(project)).totalBytes, 0);
    });
  });

  group('chunking', () {
    test('deletes everything expired however small the chunk', () async {
      final project = await newProject(retentionDays: 1);
      for (var i = 0; i < 25; i++) {
        await addEntry(project, ageDays: 10, event: 'e$i');
      }

      final outcome = await purgeExpiredEntries(db, clock: clock, chunkSize: 4);

      expect(outcome.deletedEntries, 25);
      expect(await eventsOf(project), isEmpty);
      expect((await usageOf(project)).entryCount, 0);
    });

    test('a chunk boundary landing exactly on the last row terminates',
        () async {
      // The loop breaks on a short chunk; an exact multiple has to end by
      // the following empty read instead, which is the case that loops
      // forever if that read is missing.
      final project = await newProject(retentionDays: 1);
      for (var i = 0; i < 10; i++) {
        await addEntry(project, ageDays: 5, event: 'e$i');
      }

      final outcome = await purgeExpiredEntries(db, clock: clock, chunkSize: 5)
          .timeout(const Duration(seconds: 10));

      expect(outcome.deletedEntries, 10);
    });

    test('rejects a chunk size below one', () {
      expect(
        () => purgeExpiredEntries(db, clock: clock, chunkSize: 0),
        throwsArgumentError,
      );
    });
  });

  group('PurgeScheduler', () {
    test('runOnce purges and reports through the logger', () async {
      final captured = <Map<String, dynamic>>[];
      StructlogConfiguration.configure(
        sinks: [
          LogSink(
            name: 'capture',
            output: (entry, _) => captured.add(entry),
            minLevel: LogLevel.trace,
          ),
        ],
      );
      addTearDown(StructlogConfiguration.reset);

      final project = await newProject(retentionDays: 1);
      await addEntry(project, ageDays: 10, sizeBytes: 42);

      final scheduler = PurgeScheduler(
        db,
        interval: const Duration(hours: 1),
        logger: getLogger(),
        clock: clock,
      );
      final outcome = await scheduler.runOnce();

      expect(outcome!.deletedEntries, 1);
      final logged =
          captured.singleWhere((e) => e['event'] == 'retention.purged');
      expect(logged['deleted_entries'], 1);
      expect(logged['freed_bytes'], 42);
    });

    test('a pass that removed nothing reports only at debug', () async {
      final captured = <Map<String, dynamic>>[];
      StructlogConfiguration.configure(
        sinks: [
          LogSink(
            name: 'capture',
            output: (entry, _) => captured.add(entry),
            minLevel: LogLevel.trace,
          ),
        ],
      );
      addTearDown(StructlogConfiguration.reset);

      await newProject(retentionDays: 30);
      await PurgeScheduler(
        db,
        interval: const Duration(hours: 1),
        logger: getLogger(),
        clock: clock,
      ).runOnce();

      // Not silence: "did the job run?" has to be answerable. But not at
      // info either, or a healthy server prints this every interval forever.
      expect(captured.single['event'], 'retention.purge_completed');
      expect(captured.single['level'], 'debug');
      expect(captured.single['deleted_entries'], 0);
    });

    test('a failing pass is reported and does not escape', () async {
      final captured = <Map<String, dynamic>>[];
      StructlogConfiguration.configure(
        sinks: [
          LogSink(
            name: 'capture',
            output: (entry, _) => captured.add(entry),
            minLevel: LogLevel.trace,
          ),
        ],
      );
      addTearDown(StructlogConfiguration.reset);

      final scheduler = PurgeScheduler(
        db,
        interval: const Duration(hours: 1),
        logger: getLogger(),
        clock: clock,
      );
      await db.close();

      // An unhandled error on a timer would take down the isolate; the next
      // pass may well succeed, so it must be reported and swallowed.
      expect(await scheduler.runOnce(), isNull);
      expect(
        captured.single['event'],
        'retention.purge_failed',
      );

      db = openInMemory(); // so tearDown has something to close
    });

    test('the timer fires and can be stopped', () async {
      final project = await newProject(retentionDays: 1);
      await addEntry(project, ageDays: 10);

      final scheduler = PurgeScheduler(
        db,
        interval: const Duration(milliseconds: 20),
        clock: clock,
      )..start();
      addTearDown(scheduler.stop);

      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while ((await eventsOf(project)).isNotEmpty) {
        if (DateTime.now().isAfter(deadline)) fail('the timer never fired');
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      scheduler.stop();
      await addEntry(project, ageDays: 10, event: 'after-stop');
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(
        await eventsOf(project),
        ['after-stop'],
        reason: 'a stopped scheduler must stay stopped',
      );
    });

    test('passes never overlap', () async {
      final project = await newProject(retentionDays: 1);
      for (var i = 0; i < 5; i++) {
        await addEntry(project, ageDays: 10, event: 'e$i');
      }

      final scheduler =
          PurgeScheduler(db, interval: const Duration(hours: 1), clock: clock);
      // Two passes started together: the second must decline rather than
      // double-count the decrement against the same rows.
      final results =
          await Future.wait([scheduler.runOnce(), scheduler.runOnce()]);

      expect(results.where((r) => r == null), hasLength(1));
      expect((await usageOf(project)).entryCount, 0);
      expect((await usageOf(project)).totalBytes, 0);
    });
  });
}
