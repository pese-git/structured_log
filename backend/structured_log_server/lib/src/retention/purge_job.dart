import 'dart:async';

import 'package:drift/drift.dart';
import 'package:structured_log/structured_log.dart';

import '../audit/action_classes.dart';
import '../audit/audit_action.dart';
import '../audit/audit_writer.dart';
import '../storage/database.dart';

/// What one purge pass removed.
class PurgeOutcome {
  /// Entries deleted across every project.
  final int deletedEntries;

  /// Bytes those entries accounted for, as counted by `project_usage`.
  final int freedBytes;

  /// Projects that had at least one entry removed.
  final int affectedProjects;

  const PurgeOutcome({
    required this.deletedEntries,
    required this.freedBytes,
    required this.affectedProjects,
    this.deletedAdminAudit = 0,
    this.deletedAuthAudit = 0,
    this.deletedRefreshTokens = 0,
  });

  /// Audit records removed, by class. Absent when audit retention is unset,
  /// which is the default.
  final int deletedAdminAudit;
  final int deletedAuthAudit;

  /// Expired refresh tokens removed.
  final int deletedRefreshTokens;

  bool get isEmpty =>
      deletedEntries == 0 &&
      deletedAdminAudit == 0 &&
      deletedAuthAudit == 0 &&
      deletedRefreshTokens == 0;

  Map<String, Object?> toContext() => {
        'deleted_entries': deletedEntries,
        'freed_bytes': freedBytes,
        'affected_projects': affectedProjects,
        'deleted_admin_audit': deletedAdminAudit,
        'deleted_auth_audit': deletedAuthAudit,
        'deleted_refresh_tokens': deletedRefreshTokens,
      };
}

/// Deletes entries older than their project's `retention_days` and brings
/// `project_usage` down by exactly what was removed (`log-server-quotas`).
///
/// Retention is per project, so the cutoff is computed per project rather
/// than once for the whole table — two projects with different
/// `retention_days` must not share a horizon.
///
/// Deletion runs in bounded chunks, each chunk and its counter update in one
/// transaction. Both halves of that matter: the server handles every request
/// in a single isolate (`design.md` decision 4), so one statement deleting
/// millions of rows would stall every connection until it finished; and a
/// crash between the delete and the decrement would leave `project_usage`
/// permanently overstating what is stored, which is a quota the operator
/// then cannot explain.
Future<PurgeOutcome> purgeExpiredEntries(
  StructuredLogDatabase db, {
  DateTime Function()? clock,
  int chunkSize = 500,
}) async {
  if (chunkSize < 1) {
    throw ArgumentError.value(chunkSize, 'chunkSize', 'must be at least 1');
  }
  final now = (clock ?? DateTime.now)();

  var deleted = 0;
  var freed = 0;
  var projects = 0;

  for (final project in await db.select(db.projects).get()) {
    final cutoff = now.subtract(Duration(days: project.retentionDays));
    var removedHere = 0;

    while (true) {
      // Two columns, not the row: `context_json` is most of a row's bytes,
      // and nothing here reads it.
      final chunk = await (db.selectOnly(db.logEntries)
            ..addColumns([db.logEntries.id, db.logEntries.sizeBytes])
            ..where(
              db.logEntries.projectId.equals(project.id) &
                  db.logEntries.receivedAt.isSmallerThanValue(cutoff),
            )
            ..limit(chunkSize))
          .map((row) => (
                id: row.read(db.logEntries.id)!,
                size: row.read(db.logEntries.sizeBytes)!,
              ))
          .get();
      if (chunk.isEmpty) break;

      final ids = chunk.map((e) => e.id).toList();
      final bytes = chunk.fold<int>(0, (sum, e) => sum + e.size);

      await db.transaction(() async {
        await (db.delete(db.logEntries)..where((t) => t.id.isIn(ids))).go();
        await (db.update(db.projectUsage)
              ..where((t) => t.projectId.equals(project.id)))
            .write(
          ProjectUsageCompanion.custom(
            // Clamped at zero: a counter that drifted below what is stored
            // would otherwise go negative and read as an enormous quota.
            entryCount: _atLeastZero(
              db.projectUsage.entryCount - Constant(ids.length),
            ),
            totalBytes: _atLeastZero(
              db.projectUsage.totalBytes - Constant(bytes),
            ),
          ),
        );
      });

      deleted += ids.length;
      freed += bytes;
      removedHere += ids.length;

      if (chunk.length < chunkSize) break;
    }

    if (removedHere > 0) projects++;
  }

  return PurgeOutcome(
    deletedEntries: deleted,
    freedBytes: freed,
    affectedProjects: projects,
  );
}

/// Deletes audit records past their retention, each class by its own period
/// (`design.md` decision 46).
///
/// A class whose period is `null` is not swept at all — not swept with an
/// infinite horizon, not swept: keeping records indefinitely is the default,
/// and an upgrade must not delete an operator's history on its own.
///
/// Chunked like the log purge and for the same reason — one statement removing
/// a year of authentication events would stall every connection on the single
/// isolate until it finished. Each chunk is its own transaction; a pass
/// interrupted halfway has simply deleted less.
///
/// The pass accounts for itself: one `audit.purged` per class that removed
/// anything, written outside a transaction because a deletion pass has no
/// mutation to be atomic with (`action_classes.dart`). A pass that deleted
/// nothing writes nothing — otherwise the journal would fill with hourly
/// reports of having done nothing, which is the traffic it exists to stay
/// readable above.
Future<({int admin, int auth})> purgeExpiredAuditEntries(
  StructuredLogDatabase db,
  AuditWriter audit, {
  int? auditRetentionDays,
  int? authEventRetentionDays,
  DateTime Function()? clock,
  int chunkSize = 500,
}) async {
  if (chunkSize < 1) {
    throw ArgumentError.value(chunkSize, 'chunkSize', 'must be at least 1');
  }
  final now = (clock ?? DateTime.now)();

  final authWire = authEventActions.map((a) => a.wire).toList(growable: false);

  Future<int> sweep({
    required int retentionDays,
    required bool authEvents,
  }) async {
    final cutoff = now.subtract(Duration(days: retentionDays));
    var removed = 0;

    while (true) {
      final ids = await (db.selectOnly(db.auditLogEntries)
            ..addColumns([db.auditLogEntries.id])
            ..where(
              authEvents
                  ? db.auditLogEntries.action.isIn(authWire) &
                      db.auditLogEntries.createdAt.isSmallerThanValue(cutoff)
                  : db.auditLogEntries.action.isNotIn(authWire) &
                      db.auditLogEntries.createdAt.isSmallerThanValue(cutoff),
            )
            ..limit(chunkSize))
          .map((row) => row.read(db.auditLogEntries.id)!)
          .get();
      if (ids.isEmpty) break;

      await db.transaction(() async {
        await (db.delete(db.auditLogEntries)..where((t) => t.id.isIn(ids)))
            .go();
      });
      removed += ids.length;

      if (ids.length < chunkSize) break;
    }

    if (removed > 0) {
      await audit.write(
        action: AuditAction.auditPurged,
        targetType: AuditTargetType.audit,
        metadata: {
          'scope': authEvents ? 'auth' : 'admin',
          'deleted_count': removed,
          'older_than': cutoff.toUtc().toIso8601String(),
        },
      );
    }
    return removed;
  }

  // Administrative first, so that the `audit.purged` the admin sweep writes
  // is younger than the auth cutoff and cannot be removed by the sweep that
  // follows it in the same pass.
  final admin = auditRetentionDays == null
      ? 0
      : await sweep(retentionDays: auditRetentionDays, authEvents: false);
  final auth = authEventRetentionDays == null
      ? 0
      : await sweep(retentionDays: authEventRetentionDays, authEvents: true);

  return (admin: admin, auth: auth);
}

/// Deletes refresh tokens whose expiry has passed.
///
/// Every renewal issues a new row and the old one is only marked revoked, so
/// without this the table grows for as long as the server runs. Only *expired*
/// rows go: a revoked token that has not yet expired must stay, because
/// presenting it again is what reveals a stolen token (`log-server-auth`); once
/// it is expired it is refused as invalid either way. Chunked for the same
/// reason as the other sweeps.
Future<int> purgeExpiredRefreshTokens(
  StructuredLogDatabase db, {
  DateTime Function()? clock,
  int chunkSize = 500,
}) async {
  if (chunkSize < 1) {
    throw ArgumentError.value(chunkSize, 'chunkSize', 'must be at least 1');
  }
  final now = (clock ?? DateTime.now)();
  var removed = 0;
  while (true) {
    final ids = await (db.selectOnly(db.refreshTokens)
          ..addColumns([db.refreshTokens.id])
          ..where(db.refreshTokens.expiresAt.isSmallerThanValue(now))
          ..limit(chunkSize))
        .map((row) => row.read(db.refreshTokens.id)!)
        .get();
    if (ids.isEmpty) break;
    await (db.delete(db.refreshTokens)..where((t) => t.id.isIn(ids))).go();
    removed += ids.length;
    if (ids.length < chunkSize) break;
  }
  return removed;
}

Expression<int> _atLeastZero(Expression<int> value) =>
    CaseWhenExpression<int>(cases: [
      CaseWhen(value.isSmallerThanValue(0), then: const Constant(0)),
    ], orElse: value);

/// Runs [purgeExpiredEntries] on a timer for the lifetime of the process.
///
/// The timer lives here rather than inside the store because something has
/// to own it: a periodic task nobody can cancel keeps a shutting-down
/// server — or a test — alive. [stop] is what the entrypoint calls.
///
/// Passes never overlap. If one takes longer than the interval, the next
/// tick is skipped rather than queued, because two purges running against
/// the same rows would double-count the decrement.
class PurgeScheduler {
  final StructuredLogDatabase _db;
  final Duration interval;
  final BoundLogger? _logger;
  final DateTime Function()? _clock;
  final int chunkSize;

  /// One timer for both journals (`docs/operations/configuration.md`): the log
  /// sweep and the audit sweep run in the same pass, so an operator has one
  /// interval to reason about rather than two that can interleave.
  final AuditWriter? _audit;
  final int? auditRetentionDays;
  final int? authEventRetentionDays;
  final int auditChunkSize;

  Timer? _timer;
  var _running = false;

  PurgeScheduler(
    this._db, {
    required this.interval,
    BoundLogger? logger,
    DateTime Function()? clock,
    this.chunkSize = 500,
    AuditWriter? audit,
    this.auditRetentionDays,
    this.authEventRetentionDays,
    this.auditChunkSize = 500,
  })  : _logger = logger,
        _clock = clock,
        _audit = audit;

  void start() {
    _timer ??= Timer.periodic(interval, (_) => unawaited(runOnce()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// One pass, also callable directly — which is how tests drive it without
  /// waiting out an interval.
  Future<PurgeOutcome?> runOnce() async {
    if (_running) return null;
    _running = true;
    try {
      final logs = await purgeExpiredEntries(
        _db,
        clock: _clock,
        chunkSize: chunkSize,
      );

      final audit = _audit;
      final removedAudit = audit == null
          ? (admin: 0, auth: 0)
          : await purgeExpiredAuditEntries(
              _db,
              audit,
              auditRetentionDays: auditRetentionDays,
              authEventRetentionDays: authEventRetentionDays,
              clock: _clock,
              chunkSize: auditChunkSize,
            );

      final removedTokens = await purgeExpiredRefreshTokens(
        _db,
        clock: _clock,
        chunkSize: chunkSize,
      );

      final outcome = PurgeOutcome(
        deletedRefreshTokens: removedTokens,
        deletedEntries: logs.deletedEntries,
        freedBytes: logs.freedBytes,
        affectedProjects: logs.affectedProjects,
        deletedAdminAudit: removedAudit.admin,
        deletedAuthAudit: removedAudit.auth,
      );
      if (outcome.isEmpty) {
        // At debug, because a server whose projects are all within
        // retention would otherwise print this every interval forever. It
        // is still worth emitting at all: "did the job run?" is otherwise
        // unanswerable from the outside, since a pass that deleted nothing
        // looks exactly like a scheduler that was never started.
        _logger?.debug('retention.purge_completed',
            context: outcome.toContext());
      } else {
        _logger?.info('retention.purged', context: outcome.toContext());
      }
      return outcome;
    } catch (error, stackTrace) {
      // A failed pass must not kill the timer — the next one may well
      // succeed, and an unhandled error here would take down the isolate.
      _logger?.error('retention.purge_failed', context: {
        'error': '$error',
        'stack_trace': '$stackTrace',
      });
      return null;
    } finally {
      _running = false;
    }
  }
}
