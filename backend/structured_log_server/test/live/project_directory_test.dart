import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:structured_log_server/src/live/project_directory.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

StructuredLogDatabase openInMemory() {
  return StructuredLogDatabase(
    NativeDatabase.memory(setup: (db) => db.execute('PRAGMA foreign_keys=ON;')),
  );
}

/// `tableUpdates` reach listeners as events, one turn after the write.
Future<void> settle() => pumpEventQueue();

void main() {
  late StructuredLogDatabase db;
  late ProjectDirectory directory;
  late int groupId;
  late int projectId;

  setUp(() async {
    db = openInMemory();
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
    directory = ProjectDirectory(db);
  });
  tearDown(() async {
    await directory.close();
    await db.close();
  });

  Future<void> block(int id, {bool blocked = true}) =>
      (db.update(db.projects)..where((t) => t.id.equals(id))).write(
        ProjectsCompanion(isBlocked: Value(blocked)),
      );

  group('remembering', () {
    test('answers from the database once, then from memory', () async {
      final first = await directory.standing(projectId);
      final second = await directory.standing(projectId);

      expect(first!.groupId, groupId);
      expect(first.isBlocked, isFalse);
      expect(second, same(first));
      expect(directory.databaseReads, 1);
    });

    test('peek only ever reports what is already known', () async {
      expect(directory.peek(projectId), isNull);
      await directory.standing(projectId);
      expect(directory.peek(projectId)!.groupId, groupId);
      expect(directory.databaseReads, 1);
    });

    test('a hundred callers arriving together share one read', () async {
      // The first lookup cannot have finished when the others ask — which is
      // the case for a whole batch published to every subscriber at once.
      final answers = await Future.wait([
        for (var i = 0; i < 100; i++) directory.standing(projectId),
      ]);

      expect(answers.map((a) => a!.groupId).toSet(), {groupId});
      expect(directory.databaseReads, 1);
    });

    test('a project that does not exist is not remembered', () async {
      expect(await directory.standing(9999), isNull);
      expect(await directory.standing(9999), isNull);
      expect(directory.databaseReads, 2);

      // And one created after being asked about is found, not shadowed by the
      // earlier "no".
      final late = await db
          .into(db.projects)
          .insert(
            ProjectsCompanion.insert(
              groupId: groupId,
              name: 'later',
              retentionDays: 30,
            ),
          );
      expect((await directory.standing(late))!.groupId, groupId);
    });

    test('holds no more than its limit', () async {
      final small = ProjectDirectory(db, maxEntries: 2);
      addTearDown(small.close);
      final ids = [projectId];
      for (var i = 0; i < 3; i++) {
        ids.add(
          await db
              .into(db.projects)
              .insert(
                ProjectsCompanion.insert(
                  groupId: groupId,
                  name: 'x$i',
                  retentionDays: 30,
                ),
              ),
        );
      }
      await settle();
      for (final id in ids) {
        await small.standing(id);
      }
      expect(
        ids.where((id) => small.peek(id) != null).length,
        lessThanOrEqualTo(2),
      );
    });
  });

  group('forgetting', () {
    test('blocking a project is seen at once by the next lookup', () async {
      expect((await directory.standing(projectId))!.isBlocked, isFalse);

      await block(projectId);
      await settle();

      expect(directory.peek(projectId), isNull);
      expect((await directory.standing(projectId))!.isBlocked, isTrue);
      expect(directory.databaseReads, 2);
    });

    test('and unblocking likewise', () async {
      await block(projectId);
      await settle();
      expect((await directory.standing(projectId))!.isBlocked, isTrue);

      await block(projectId, blocked: false);
      await settle();
      expect((await directory.standing(projectId))!.isBlocked, isFalse);
    });

    test(
      'a change made inside a transaction is seen once it commits',
      () async {
        await directory.standing(projectId);

        await db.transaction(() async {
          await block(projectId);
          await settle();
          // Not yet committed: nothing has been announced.
          expect(directory.peek(projectId), isNotNull);
        });
        await settle();

        expect(directory.peek(projectId), isNull);
        expect((await directory.standing(projectId))!.isBlocked, isTrue);
      },
    );

    test('any write to the table forgets, whatever it changes', () async {
      await directory.standing(projectId);
      await (db.update(db.projects)..where((t) => t.id.equals(projectId)))
          .write(const ProjectsCompanion(maxEntries: Value(5)));
      await settle();
      expect(directory.peek(projectId), isNull);
    });

    test('a write to another table does not', () async {
      await directory.standing(projectId);
      await db.into(db.groups).insert(GroupsCompanion.insert(name: 'other'));
      await settle();
      expect(directory.peek(projectId), isNotNull);
    });

    test(
      'a read that began before a change is answered but not remembered',
      () async {
        // Asked, then the table changes before the answer is in: what came back
        // may be the old state, so it must not be kept.
        final asking = directory.standing(projectId);
        directory.invalidate();
        await asking;

        expect(directory.peek(projectId), isNull);
        await directory.standing(projectId);
        expect(directory.databaseReads, 2);
      },
    );

    test(
      'a caller after a change does not join a read from before it',
      () async {
        final before = directory.standing(projectId);
        directory.invalidate();
        final after = directory.standing(projectId);

        await Future.wait([before, after]);
        expect(directory.databaseReads, 2);
      },
    );
  });
}
