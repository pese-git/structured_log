import 'package:drift/drift.dart';

import 'database.dart';
import 'page.dart';
import 'query.dart';

/// Persists and queries [LogEntries] rows. Implemented by [DriftLogStore];
/// kept as an interface so callers (HTTP routes, tests) depend on behavior,
/// not on `drift` directly.
abstract class LogStore {
  /// Inserts [entries] under [projectId] atomically, returning the stored rows
  /// in the same order as [entries] — ids assigned (`log-server-storage`: every
  /// entry is tied to exactly one project).
  ///
  /// Called inside the caller's transaction it joins it, and opens none of its
  /// own; called outside one, it runs in a transaction of its own.
  ///
  /// The rows rather than their ids, because the live stream broadcasts
  /// exactly what was committed (`log-server-live-stream`) and rebuilding
  /// a row from its companion would be a second, drift-prone copy of the
  /// mapping.
  Future<List<LogEntry>> insertBatch(
    int projectId,
    List<LogEntriesCompanion> entries,
  );

  /// Like [insertBatch] for entries of several projects at once: each
  /// companion already carries its own `projectId`. The rows come back in the
  /// order given, which is the order of their ids.
  Future<List<LogEntry>> insertRows(List<LogEntriesCompanion> entries);

  /// Returns one page of entries matching [query] (`log-server-api`).
  Future<LogQueryPage> query(LogQuery query);
}

class DriftLogStore implements LogStore {
  final StructuredLogDatabase _db;

  DriftLogStore(this._db);

  @override
  Future<List<LogEntry>> insertBatch(
    int projectId,
    List<LogEntriesCompanion> entries,
  ) {
    return insertRows([
      for (final entry in entries) entry.copyWith(projectId: Value(projectId)),
    ]);
  }

  @override
  Future<List<LogEntry>> insertRows(List<LogEntriesCompanion> entries) {
    if (entries.isEmpty) return Future.value(const []);
    // A transaction inside a transaction is a SAVEPOINT, and that alone cost
    // half of an ingest batch. `POST /v1/logs` already holds one around this
    // call, so join it; only a caller without one gets one here.
    return _db.isInTransaction
        ? _insert(entries)
        : _db.transaction(() => _insert(entries));
  }

  /// One statement batch, then one read of what it wrote.
  ///
  /// This replaced an `insertReturning` per entry, each an awaited round trip
  /// to the database's isolate: 100 of them per batch, and the ingest path is
  /// one long chain of them.
  ///
  /// The rows are found by id range. That is sound because the ids are
  /// `AUTOINCREMENT` and this runs on the one connection, inside a transaction
  /// that holds it — nothing else can insert between the batch and the read —
  /// so the ids of the [entries] are exactly the `entries.length` ending at
  /// `last_insert_rowid()`. Anything else is a bug worth failing loudly for,
  /// not a row set to broadcast.
  Future<List<LogEntry>> _insert(List<LogEntriesCompanion> entries) async {
    await _db.batch((b) => b.insertAll(_db.logEntries, entries));

    final last =
        (await _db.customSelect('SELECT last_insert_rowid() AS id').getSingle())
            .read<int>('id');
    final first = last - entries.length + 1;
    final rows = await (_db.select(_db.logEntries)
          ..where((t) => t.id.isBetweenValues(first, last))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    if (rows.length != entries.length) {
      throw StateError(
        'Expected ${entries.length} rows with ids $first..$last after the '
        'insert, found ${rows.length}.',
      );
    }
    return rows;
  }

  @override
  Future<LogQueryPage> query(LogQuery query) async {
    // One row past the limit, only to learn whether another page exists
    // (`pageFromProbe`). The live stream's catch-up reads through here too
    // (`afterId`): it never looks at the cursor, and the trimmed page is the
    // same size it asked for.
    final built = buildLogQuerySql(
      LogQuery(
        projectIds: query.projectIds,
        filter: query.filter,
        from: query.from,
        to: query.to,
        limit: query.limit + 1,
        cursor: query.cursor,
        afterId: query.afterId,
      ),
    );
    final rows = await _db.customSelect(
      built.sql,
      variables: built.variables,
      readsFrom: {_db.logEntries},
    ).get();
    final page = pageFromProbe(
      rows.map((row) => _db.logEntries.map(row.data)).toList(),
      query.limit,
      (entry) => entry.id,
    );
    return LogQueryPage(entries: page.items, nextCursor: page.nextCursor);
  }
}
