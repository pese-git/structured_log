import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

StructuredLogDatabase openInMemory() {
  return StructuredLogDatabase(
    NativeDatabase.memory(
      setup: (db) => db.execute('PRAGMA foreign_keys=ON;'),
    ),
  );
}

Future<int> insertGroup(StructuredLogDatabase db, {String name = 'g'}) {
  return db.into(db.groups).insert(GroupsCompanion.insert(name: name));
}

Future<int> insertProject(
  StructuredLogDatabase db, {
  required int groupId,
  String name = 'p',
  int retentionDays = 30,
}) {
  return db.into(db.projects).insert(
        ProjectsCompanion.insert(
          groupId: groupId,
          name: name,
          retentionDays: retentionDays,
        ),
      );
}

Future<int> insertUser(
  StructuredLogDatabase db, {
  required String username,
  String? email,
  bool isPrimaryAdmin = false,
}) {
  return db.into(db.users).insert(
        UsersCompanion.insert(
          username: username,
          passwordHash: 'hash',
          email: Value(email),
          isPrimaryAdmin: Value(isPrimaryAdmin),
        ),
      );
}

void main() {
  group('log_entries', () {
    late StructuredLogDatabase db;
    late int projectA;
    late int projectB;

    setUp(() async {
      db = openInMemory();
      final group = await insertGroup(db);
      projectA = await insertProject(db, groupId: group, name: 'a');
      projectB = await insertProject(db, groupId: group, name: 'b');
    });

    tearDown(() => db.close());

    test('an entry is tied to exactly the project it was inserted under',
        () async {
      await db.into(db.logEntries).insert(
            LogEntriesCompanion.insert(
              projectId: projectA,
              receivedAt: DateTime.now(),
              timestamp: DateTime.now(),
              level: 'info',
              event: 'e',
              sizeBytes: 1,
              contextJson: '{}',
            ),
          );

      final inA = await (db.select(
        db.logEntries,
      )..where((t) => t.projectId.equals(projectA)))
          .get();
      final inB = await (db.select(
        db.logEntries,
      )..where((t) => t.projectId.equals(projectB)))
          .get();

      expect(inA, hasLength(1));
      expect(inB, isEmpty);
    });

    test('an arbitrary context field round-trips through context_json',
        () async {
      final context = {
        'event': 'checkout',
        'order_id': 'ord_42',
        'amount': 19.99
      };
      await db.into(db.logEntries).insert(
            LogEntriesCompanion.insert(
              projectId: projectA,
              receivedAt: DateTime.now(),
              timestamp: DateTime.now(),
              level: 'info',
              event: 'checkout',
              sizeBytes: 1,
              contextJson: jsonEncode(context),
            ),
          );

      final row = await db.select(db.logEntries).getSingle();
      final decoded = jsonDecode(row.contextJson) as Map<String, dynamic>;
      expect(decoded['order_id'], 'ord_42');
      expect(decoded['amount'], 19.99);
    });

    test('received_at is independent of timestamp', () async {
      final clientTimestamp = DateTime.utc(2020, 1, 1);
      final serverReceivedAt = DateTime.utc(2026, 6, 15, 10, 30);

      await db.into(db.logEntries).insert(
            LogEntriesCompanion.insert(
              projectId: projectA,
              receivedAt: serverReceivedAt,
              timestamp: clientTimestamp,
              level: 'info',
              event: 'delayed',
              sizeBytes: 1,
              contextJson: '{}',
            ),
          );

      final row = await db.select(db.logEntries).getSingle();
      expect(row.timestamp, clientTimestamp);
      expect(row.receivedAt, serverReceivedAt);
      expect(row.receivedAt, isNot(row.timestamp));
    });

    test('filtering by project_id and level plans through the composite index',
        () async {
      final plan = await db.customSelect(
        'EXPLAIN QUERY PLAN SELECT * FROM log_entries '
        'WHERE project_id = ? AND level = ? ORDER BY timestamp',
        variables: [Variable.withInt(projectA), Variable.withString('info')],
      ).get();
      final planText = plan.map((r) => r.data.values.join(' ')).join('\n');
      expect(planText, contains('idx_log_entries_project_level_timestamp'));
    });
  });

  group('users', () {
    late StructuredLogDatabase db;

    setUp(() => db = openInMemory());
    tearDown(() => db.close());

    test('username is unique across the whole table', () async {
      await insertUser(db, username: 'alice');
      expect(() => insertUser(db, username: 'alice'),
          throwsA(isA<SqliteException>()));
    });

    test('email is unique when set, but any number of users may have no email',
        () async {
      await insertUser(db, username: 'a', email: 'a@example.com');
      await insertUser(db, username: 'b'); // no email
      await insertUser(db, username: 'c'); // no email either — must not collide

      expect(
        () => insertUser(db, username: 'd', email: 'a@example.com'),
        throwsA(isA<SqliteException>()),
      );
    });

    test('at most one user may have is_primary_admin = true', () async {
      await insertUser(db, username: 'root', isPrimaryAdmin: true);
      expect(
        () => insertUser(db, username: 'other', isPrimaryAdmin: true),
        throwsA(isA<SqliteException>()),
      );
    });

    test('a soft-deleted user keeps its username/email reserved', () async {
      final id =
          await insertUser(db, username: 'alice', email: 'alice@example.com');
      await (db.update(db.users)..where((t) => t.id.equals(id))).write(
        UsersCompanion(deletedAt: Value(DateTime.now())),
      );

      expect(
        () => insertUser(db, username: 'alice'),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => insertUser(db,
            username: 'someone-else', email: 'alice@example.com'),
        throwsA(isA<SqliteException>()),
      );
    });
  });

  group('projects and teams', () {
    late StructuredLogDatabase db;

    setUp(() => db = openInMemory());
    tearDown(() => db.close());

    test('a project always belongs to an existing group', () async {
      expect(
        () => insertProject(db, groupId: 999),
        throwsA(isA<SqliteException>()),
      );
    });

    test('a new project is not blocked by default', () async {
      final group = await insertGroup(db);
      final projectId = await insertProject(db, groupId: group);
      final row = await (db.select(
        db.projects,
      )..where((t) => t.id.equals(projectId)))
          .getSingle();
      expect(row.isBlocked, isFalse);
    });

    test('a team always belongs to an existing group', () async {
      expect(
        () => db.into(db.teams).insert(
              TeamsCompanion.insert(groupId: 999, name: 't'),
            ),
        throwsA(isA<SqliteException>()),
      );
    });
  });

  group('role_assignments', () {
    late StructuredLogDatabase db;

    setUp(() => db = openInMemory());
    tearDown(() => db.close());

    test('a global-scope assignment stores a null scope_id', () async {
      final id = await db.into(db.roleAssignments).insert(
            RoleAssignmentsCompanion.insert(
              subjectType: 'user',
              subjectId: 1,
              role: 'admin',
              scopeType: 'global',
            ),
          );
      final row = await (db.select(
        db.roleAssignments,
      )..where((t) => t.id.equals(id)))
          .getSingle();
      expect(row.scopeId, isNull);
    });

    test('a group-scope assignment stores the group id', () async {
      final group = await insertGroup(db);
      final id = await db.into(db.roleAssignments).insert(
            RoleAssignmentsCompanion.insert(
              subjectType: 'user',
              subjectId: 1,
              role: 'owner',
              scopeType: 'group',
              scopeId: Value(group),
            ),
          );
      final row = await (db.select(
        db.roleAssignments,
      )..where((t) => t.id.equals(id)))
          .getSingle();
      expect(row.scopeId, group);
    });
  });

  group('revocable tokens', () {
    late StructuredLogDatabase db;
    late int userId;

    setUp(() async {
      db = openInMemory();
      userId = await insertUser(db, username: 'alice');
    });
    tearDown(() => db.close());

    test('a revoked refresh token stays in storage with revoked_at set',
        () async {
      final now = DateTime.now();
      final id = await db.into(db.refreshTokens).insert(
            RefreshTokensCompanion.insert(
              userId: userId,
              tokenHash: 'h',
              expiresAt: now.add(const Duration(days: 30)),
            ),
          );

      await (db.update(db.refreshTokens)..where((t) => t.id.equals(id))).write(
        RefreshTokensCompanion(revokedAt: Value(now)),
      );

      final row = await (db.select(
        db.refreshTokens,
      )..where((t) => t.id.equals(id)))
          .getSingle();
      expect(row.revokedAt, isNotNull);
    });

    test('a used password-reset token stays in storage with used_at set',
        () async {
      final now = DateTime.now();
      final id = await db.into(db.passwordResetTokens).insert(
            PasswordResetTokensCompanion.insert(
              userId: userId,
              tokenHash: 'h',
              expiresAt: now.add(const Duration(minutes: 30)),
            ),
          );

      await (db.update(
        db.passwordResetTokens,
      )..where((t) => t.id.equals(id)))
          .write(
        PasswordResetTokensCompanion(usedAt: Value(now)),
      );

      final row = await (db.select(
        db.passwordResetTokens,
      )..where((t) => t.id.equals(id)))
          .getSingle();
      expect(row.usedAt, isNotNull);
    });
  });

  group('audit_log_entries', () {
    late StructuredLogDatabase db;

    setUp(() => db = openInMemory());
    tearDown(() => db.close());

    test('a rolled-back transaction leaves no audit entry behind', () async {
      await expectLater(
        db.transaction(() async {
          await db.into(db.auditLogEntries).insert(
                AuditLogEntriesCompanion.insert(
                  action: 'group.created',
                  targetType: 'group',
                  metadata: '{}',
                ),
              );
          throw StateError('simulated failure after the mutation');
        }),
        throwsA(isA<StateError>()),
      );

      final rows = await db.select(db.auditLogEntries).get();
      expect(rows, isEmpty);
    });
  });

  group('project_usage', () {
    late StructuredLogDatabase db;
    late int projectId;

    setUp(() async {
      db = openInMemory();
      final group = await insertGroup(db);
      projectId = await insertProject(db, groupId: group);
    });
    tearDown(() => db.close());

    test('usage grows on insert and shrinks on purge, atomically', () async {
      await db.into(db.projectUsage).insert(
            ProjectUsageCompanion.insert(projectId: Value(projectId)),
          );

      await db.transaction(() async {
        await (db.update(
          db.projectUsage,
        )..where((t) => t.projectId.equals(projectId)))
            .write(
          const ProjectUsageCompanion(
            entryCount: Value(10),
            totalBytes: Value(1000),
          ),
        );
      });

      var row = await (db.select(
        db.projectUsage,
      )..where((t) => t.projectId.equals(projectId)))
          .getSingle();
      expect(row.entryCount, 10);
      expect(row.totalBytes, 1000);

      await db.transaction(() async {
        await (db.update(
          db.projectUsage,
        )..where((t) => t.projectId.equals(projectId)))
            .write(
          const ProjectUsageCompanion(
              entryCount: Value(6), totalBytes: Value(600)),
        );
      });

      row = await (db.select(
        db.projectUsage,
      )..where((t) => t.projectId.equals(projectId)))
          .getSingle();
      expect(row.entryCount, 6);
      expect(row.totalBytes, 600);
    });
  });

  group('persistence and concurrency', () {
    test('data survives closing and reopening the same database file',
        () async {
      final dir =
          Directory.systemTemp.createTempSync('structured_log_server_test');
      final dbPath = '${dir.path}/test.sqlite';
      addTearDown(() => dir.deleteSync(recursive: true));

      final first = StructuredLogDatabase.open(dbPath);
      final group = await insertGroup(first);
      final projectId = await insertProject(first, groupId: group);
      await first.into(first.logEntries).insert(
            LogEntriesCompanion.insert(
              projectId: projectId,
              receivedAt: DateTime.now(),
              timestamp: DateTime.now(),
              level: 'info',
              event: 'before_restart',
              sizeBytes: 1,
              contextJson: '{}',
            ),
          );
      await first.close();

      final second = StructuredLogDatabase.open(dbPath);
      final rows = await second.select(second.logEntries).get();
      expect(rows, hasLength(1));
      expect(rows.single.event, 'before_restart');
      await second.close();
    });

    test('a read is not blocked by a concurrent write on a WAL database',
        () async {
      // Two live connections to the same file is the point of this test —
      // silence drift's single-connection-per-file advisory warning for it.
      final previousWarningSetting =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(
        () => driftRuntimeOptions.dontWarnAboutMultipleDatabases =
            previousWarningSetting,
      );

      final dir =
          Directory.systemTemp.createTempSync('structured_log_server_test');
      final dbPath = '${dir.path}/test.sqlite';
      addTearDown(() => dir.deleteSync(recursive: true));

      final writer = StructuredLogDatabase.open(dbPath);
      final group = await insertGroup(writer);
      final projectId = await insertProject(writer, groupId: group);

      final reader = StructuredLogDatabase.open(dbPath);

      final writeFuture = writer.transaction(() async {
        for (var i = 0; i < 50; i++) {
          await writer.into(writer.logEntries).insert(
                LogEntriesCompanion.insert(
                  projectId: projectId,
                  receivedAt: DateTime.now(),
                  timestamp: DateTime.now(),
                  level: 'info',
                  event: 'e$i',
                  sizeBytes: 1,
                  contextJson: '{}',
                ),
              );
        }
      });

      final readFuture = reader.select(reader.groups).get();

      await Future.wait([writeFuture, readFuture]).timeout(
        const Duration(seconds: 5),
      );

      await writer.close();
      await reader.close();
    });
  });
}
