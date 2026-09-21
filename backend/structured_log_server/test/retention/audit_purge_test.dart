import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:structured_log_server/src/audit/audit_action.dart';
import 'package:structured_log_server/src/audit/audit_writer.dart';
import 'package:structured_log_server/src/retention/purge_job.dart';
import 'package:structured_log_server/src/storage/database.dart';
import 'package:test/test.dart';

StructuredLogDatabase openInMemory() {
  return StructuredLogDatabase(
    NativeDatabase.memory(setup: (db) => db.execute('PRAGMA foreign_keys=ON;')),
  );
}

void main() {
  late StructuredLogDatabase db;
  late AuditWriter audit;

  final now = DateTime.utc(2026, 6, 1);

  setUp(() {
    db = openInMemory();
    audit = AuditWriter(db);
  });
  tearDown(() => db.close());

  /// A record of [action] placed [ageDays] in the past.
  Future<void> seed(AuditAction action, {required int ageDays}) async {
    await db
        .into(db.auditLogEntries)
        .insert(
          AuditLogEntriesCompanion.insert(
            action: action.wire,
            targetType: 'user',
            metadata: '{}',
            createdAt: Value(now.subtract(Duration(days: ageDays))),
          ),
        );
  }

  Future<List<AuditLogEntry>> rows() => db.select(db.auditLogEntries).get();
  Future<List<String>> actions() async =>
      (await rows()).map((r) => r.action).toList();

  Future<({int admin, int auth})> purge({
    int? auditRetentionDays,
    int? authEventRetentionDays,
    int chunkSize = 500,
  }) {
    return purgeExpiredAuditEntries(
      db,
      audit,
      auditRetentionDays: auditRetentionDays,
      authEventRetentionDays: authEventRetentionDays,
      clock: () => now,
      chunkSize: chunkSize,
    );
  }

  test('by default nothing is deleted, at any age', () async {
    // The regression this protects is an operator's history disappearing on an
    // upgrade. Turning retention on is an explicit act; a server that predates
    // the setting kept everything, and continues to.
    await seed(AuditAction.groupCreated, ageDays: 4000);
    await seed(AuditAction.authLoginFailed, ageDays: 4000);

    final removed = await purge();

    expect(removed, (admin: 0, auth: 0));
    expect(await rows(), hasLength(2));
  });

  test('each class is deleted by its own period', () async {
    // The reason there are two periods: authentication events are produced by
    // traffic nobody here controls and carry addresses, while administrative
    // records are few and stay valuable for years.
    await seed(AuditAction.groupCreated, ageDays: 100);
    await seed(AuditAction.authLoginSucceeded, ageDays: 100);

    await purge(auditRetentionDays: 365, authEventRetentionDays: 30);

    expect(
      await actions(),
      containsAll(<String>['group.created']),
      reason: 'the administrative record is well inside its own year',
    );
    expect(
      await actions(),
      isNot(contains('auth.login_succeeded')),
      reason: 'and the authentication event is well past its month',
    );
  });

  test('an administrative record of the same age as a deleted auth event '
      'survives', () async {
    await seed(AuditAction.secretKeyRevoked, ageDays: 60);
    await seed(AuditAction.authThrottled, ageDays: 60);

    await purge(auditRetentionDays: 3650, authEventRetentionDays: 30);

    final remaining = await actions();
    expect(remaining, contains('secret_key.revoked'));
    expect(remaining, isNot(contains('auth.throttled')));
  });

  test('a pass that deleted something accounts for itself', () async {
    await seed(AuditAction.authLoginFailed, ageDays: 90);
    await seed(AuditAction.authLoginFailed, ageDays: 90);

    await purge(authEventRetentionDays: 30);

    final trace = (await rows()).singleWhere((r) => r.action == 'audit.purged');
    final metadata = jsonDecode(trace.metadata) as Map<String, Object?>;
    expect(metadata['scope'], 'auth');
    expect(metadata['deleted_count'], 2);
    expect(metadata['older_than'], isNotNull);
    expect(
      trace.actorUserId,
      isNull,
      reason: 'the server did this, not a person',
    );
  });

  test('a pass that deleted nothing writes no trace', () async {
    await seed(AuditAction.authLoginFailed, ageDays: 1);

    await purge(auditRetentionDays: 30, authEventRetentionDays: 30);

    expect(
      await actions(),
      ['auth.login_failed'],
      reason:
          'an hourly report of having done nothing is the traffic the journal '
          'exists to stay readable above',
    );
  });

  test('the trace survives the records it describes', () async {
    await seed(AuditAction.authLoginFailed, ageDays: 90);

    await purge(authEventRetentionDays: 30);

    final remaining = await actions();
    expect(remaining, ['audit.purged']);
  });

  test('the administrative sweep runs first, so its own trace is not swept '
      'by the auth sweep in the same pass', () async {
    // `audit.purged` is an administrative action. Were the auth sweep to run
    // first and the admin sweep second, the trace the auth sweep just wrote
    // would be a candidate for the admin sweep — young enough in practice, but
    // the ordering is what makes that not depend on the numbers.
    await seed(AuditAction.groupCreated, ageDays: 400);
    await seed(AuditAction.authLoginFailed, ageDays: 400);

    await purge(auditRetentionDays: 30, authEventRetentionDays: 30);

    final traces = (await rows())
        .where((r) => r.action == 'audit.purged')
        .toList();
    expect(traces, hasLength(2), reason: 'one per class, both kept');
  });

  test('deletion is chunked, and the loop terminates', () async {
    for (var i = 0; i < 25; i++) {
      await seed(AuditAction.authLoginFailed, ageDays: 90);
    }

    final removed = await purge(authEventRetentionDays: 30, chunkSize: 4);

    expect(removed.auth, 25);
    expect(await actions(), [
      'audit.purged',
    ], reason: 'every expired record is gone, not just the first chunk');
  });

  test('a record exactly at the horizon is kept', () async {
    // `<` rather than `<=`: the boundary belongs to the period the operator
    // asked to keep.
    await seed(AuditAction.authLoginFailed, ageDays: 30);

    await purge(authEventRetentionDays: 30);

    expect(await actions(), ['auth.login_failed']);
  });

  test('a chunk size below one is refused rather than looping', () async {
    expect(
      () => purge(authEventRetentionDays: 1, chunkSize: 0),
      throwsA(isA<ArgumentError>()),
    );
  });
}
