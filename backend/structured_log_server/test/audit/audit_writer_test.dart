import 'dart:convert';

import 'package:drift/native.dart';
import 'package:structured_log_server/src/audit/audit_action.dart';
import 'package:structured_log_server/src/audit/audit_writer.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

StructuredLogDatabase openInMemory() {
  return StructuredLogDatabase(
    NativeDatabase.memory(
      setup: (db) => db.execute('PRAGMA foreign_keys=ON;'),
    ),
  );
}

void main() {
  late StructuredLogDatabase db;
  late AuditWriter audit;

  setUp(() {
    db = openInMemory();
    audit = AuditWriter(db);
  });

  tearDown(() => db.close());

  Future<List<AuditLogEntry>> rows() => db.select(db.auditLogEntries).get();

  test('a record carries the actor, the target and its metadata', () async {
    await audit.write(
      action: AuditAction.projectQuotaUpdated,
      targetType: AuditTargetType.project,
      actorUserId: 7,
      targetId: 42,
      metadata: {
        'before': {'max_entries': 1000},
        'after': {'max_entries': null},
      },
    );

    final row = (await rows()).single;
    expect(row.action, 'project.quota_updated');
    expect(row.targetType, 'project');
    expect(row.actorUserId, 7);
    expect(row.targetId, 42);
    expect(jsonDecode(row.metadata), {
      'before': {'max_entries': 1000},
      'after': {'max_entries': null},
    });
    expect(row.createdAt, isNotNull);
  });

  test('an event with nobody behind it stores that, rather than nothing',
      () async {
    // A login attempt under a username that does not exist has no actor and no
    // target row to point at. Both being null is the honest record of what
    // happened, and the column is nullable for exactly this.
    await audit.write(
      action: AuditAction.authLoginFailed,
      targetType: AuditTargetType.user,
      metadata: {'reason': 'unknown_user'},
    );

    final row = (await rows()).single;
    expect(row.actorUserId, isNull);
    expect(row.targetId, isNull);
    expect(row.targetType, 'user');
  });

  test('metadata is an empty object when there is nothing to say', () async {
    await audit.write(
      action: AuditAction.authLoggedOut,
      targetType: AuditTargetType.user,
      actorUserId: 3,
      targetId: 3,
    );

    expect(
      jsonDecode((await rows()).single.metadata),
      isEmpty,
      reason:
          'the column is NOT NULL, and a reader parsing it should never have '
          'to handle an empty string as a special case',
    );
  });

  test('a rolled-back mutation takes its audit record with it', () async {
    // The guarantee the whole journal rests on: a record that outlived the
    // change it describes is a claim about something that never happened. It
    // holds without the writer being told about the transaction, because
    // drift's transaction is zone-scoped — which is the reason `AuditWriter`
    // takes no executor.
    await expectLater(
      db.transaction(() async {
        await db.into(db.groups).insert(GroupsCompanion.insert(name: 'acme'));
        await audit.write(
          action: AuditAction.groupCreated,
          targetType: AuditTargetType.group,
          actorUserId: 1,
          targetId: 1,
        );
        throw StateError('the request failed after both writes');
      }),
      throwsA(isA<StateError>()),
    );

    expect(await rows(), isEmpty);
    expect(
      await db.select(db.groups).get(),
      isEmpty,
      reason: 'and the mutation itself is gone too — same transaction',
    );
  });

  test('a committed transaction keeps both', () async {
    await db.transaction(() async {
      await db.into(db.groups).insert(GroupsCompanion.insert(name: 'acme'));
      await audit.write(
        action: AuditAction.groupCreated,
        targetType: AuditTargetType.group,
        actorUserId: 1,
        targetId: 1,
      );
    });

    expect(await rows(), hasLength(1));
    expect(await db.select(db.groups).get(), hasLength(1));
  });
}
