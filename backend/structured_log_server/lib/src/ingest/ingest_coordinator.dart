import 'dart:async';

import 'package:drift/drift.dart';

import '../live/log_broadcast.dart';
import '../storage/database.dart';
import '../storage/log_store.dart';
import 'ingest.dart';

/// Commits concurrent `POST /v1/logs` requests together (`log-server-api`).
///
/// A request used to open a transaction of its own: begin, read usage, insert,
/// update usage, commit — six round trips to the database's isolate and a
/// commit, whatever the size of the batch. For a client that sends one entry at
/// a time that fixed cost *was* the request (~0.65 ms of CPU, against ~50 µs
/// for each further entry of a large batch).
///
/// Requests that arrive while a transaction is running now wait for it and go
/// in the next one, all together. Nothing waits *for company*: with no load a
/// request is its own group and pays nothing extra; the group forms only from
/// what queued up behind the previous commit, so latency does not grow at low
/// load and throughput does at high load.
///
/// What is preserved, deliberately:
///
/// - **Quotas are exact and sequential.** Requests are judged in arrival order
///   against the usage the requests before them already consumed, inside the
///   transaction, exactly as separate transactions would have judged them.
/// - **What is published is in id order.** The group's rows are inserted as one
///   list and published as that list: a group subscription drops an entry whose
///   id is not above the last one it delivered, so publishing request by
///   request, or project by project, in any other order would lose entries.
/// - **Publishing happens after the commit**, once for the whole group.
///
/// A failure of the transaction itself (the database went away) fails every
/// request in it; a bad *request* never gets this far, since parsing and
/// validation happen before it is submitted.
class IngestCoordinator {
  final StructuredLogDatabase _db;
  final LogStore _logStore;
  final LogBroadcast _broadcast;

  /// Upper bound on entries committed together. It bounds how long one
  /// transaction holds the writer, and so how long a reader-side request or a
  /// later group can wait behind it; a request larger than this still goes
  /// through, alone.
  final int maxEntriesPerGroup;

  final List<_Request> _queue = [];
  bool _draining = false;

  /// Transactions committed so far. For tests and diagnostics: the ratio to
  /// the requests submitted is how much grouping is happening.
  int groupsCommitted = 0;

  IngestCoordinator(
    this._db,
    this._logStore,
    this._broadcast, {
    this.maxEntriesPerGroup = 2000,
  });

  /// Validates [rawEntries] against the project's quota and stores what passes,
  /// in a transaction shared with whatever else is waiting. Completes after
  /// the commit and the publish.
  Future<IngestOutcome> submit({
    required int projectId,
    required int? maxEntries,
    required int? maxBytes,
    required List<Object?> rawEntries,
  }) {
    final request = _Request(projectId, maxEntries, maxBytes, rawEntries);
    _queue.add(request);
    if (!_draining) unawaited(_drain());
    return request.done.future;
  }

  Future<void> _drain() async {
    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        await _commit(_takeGroup());
      }
    } finally {
      _draining = false;
    }
  }

  List<_Request> _takeGroup() {
    var entries = 0;
    var taken = 0;
    for (final request in _queue) {
      final size = request.rawEntries.length;
      if (taken > 0 && entries + size > maxEntriesPerGroup) break;
      entries += size;
      taken++;
    }
    final group = _queue.sublist(0, taken);
    _queue.removeRange(0, taken);
    return group;
  }

  Future<void> _commit(List<_Request> group) async {
    final List<IngestOutcome> outcomes;
    final List<LogEntry> rows;
    try {
      (outcomes, rows) = await _db.transaction(() async {
        // What each project has used so far, this group's earlier requests
        // included; read once per project, written back once.
        final usage = <int, _Usage>{};
        final outcomes = <IngestOutcome>[];
        final toInsert = <LogEntriesCompanion>[];
        final now = DateTime.now();

        for (final request in group) {
          var current = usage[request.projectId];
          if (current == null) {
            final row =
                await (_db.select(_db.projectUsage)
                      ..where((t) => t.projectId.equals(request.projectId)))
                    .getSingleOrNull();
            current = usage[request.projectId] = _Usage(
              row?.entryCount ?? 0,
              row?.totalBytes ?? 0,
            );
          }
          final outcome = processIngestBatch(
            rawEntries: request.rawEntries,
            maxEntries: request.maxEntries,
            maxBytes: request.maxBytes,
            currentEntryCount: current.entryCount,
            currentTotalBytes: current.totalBytes,
            receivedAt: now,
          );
          current.entryCount += outcome.entryCountDelta;
          current.totalBytes += outcome.bytesDelta;
          current.entryDelta += outcome.entryCountDelta;
          current.bytesDelta += outcome.bytesDelta;
          outcomes.add(outcome);
          for (final entry in outcome.accepted) {
            toInsert.add(entry.copyWith(projectId: Value(request.projectId)));
          }
        }

        final rows = await _logStore.insertRows(toInsert);
        for (final MapEntry(key: projectId, value: used) in usage.entries) {
          if (used.entryDelta == 0 && used.bytesDelta == 0) continue;
          await (_db.update(
            _db.projectUsage,
          )..where((t) => t.projectId.equals(projectId))).write(
            ProjectUsageCompanion.custom(
              entryCount:
                  _db.projectUsage.entryCount + Constant(used.entryDelta),
              totalBytes:
                  _db.projectUsage.totalBytes + Constant(used.bytesDelta),
            ),
          );
        }
        return (outcomes, rows);
      });
    } catch (error, stack) {
      for (final request in group) {
        request.done.completeError(error, stack);
      }
      return;
    }

    groupsCommitted++;
    // After the commit, never inside it: a subscriber may react by reading
    // these rows back (catch-up), and they have to be there
    // (`log-server-live-stream`).
    if (rows.isNotEmpty) _broadcast.publish(rows);
    for (var i = 0; i < group.length; i++) {
      group[i].done.complete(outcomes[i]);
    }
  }
}

class _Request {
  final int projectId;
  final int? maxEntries;
  final int? maxBytes;
  final List<Object?> rawEntries;
  final done = Completer<IngestOutcome>();

  _Request(this.projectId, this.maxEntries, this.maxBytes, this.rawEntries);
}

class _Usage {
  int entryCount;
  int totalBytes;
  int entryDelta = 0;
  int bytesDelta = 0;

  _Usage(this.entryCount, this.totalBytes);
}
