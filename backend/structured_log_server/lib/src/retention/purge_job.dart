import 'dart:async';

import 'package:drift/drift.dart';
import 'package:structured_log/structured_log.dart';

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
  });

  bool get isEmpty => deletedEntries == 0;

  Map<String, Object?> toContext() => {
        'deleted_entries': deletedEntries,
        'freed_bytes': freedBytes,
        'affected_projects': affectedProjects,
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
      final chunk = await (db.select(db.logEntries)
            ..where((t) =>
                t.projectId.equals(project.id) &
                t.receivedAt.isSmallerThanValue(cutoff))
            ..limit(chunkSize))
          .get();
      if (chunk.isEmpty) break;

      final ids = chunk.map((e) => e.id).toList();
      final bytes = chunk.fold<int>(0, (sum, e) => sum + e.sizeBytes);

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

  Timer? _timer;
  var _running = false;

  PurgeScheduler(
    this._db, {
    required this.interval,
    BoundLogger? logger,
    DateTime Function()? clock,
    this.chunkSize = 500,
  })  : _logger = logger,
        _clock = clock;

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
      final outcome = await purgeExpiredEntries(
        _db,
        clock: _clock,
        chunkSize: chunkSize,
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
