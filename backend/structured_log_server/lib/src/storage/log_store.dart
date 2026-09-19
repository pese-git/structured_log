import 'package:drift/drift.dart';

import 'database.dart';
import 'page.dart';
import 'query.dart';

/// Persists and queries [LogEntries] rows. Implemented by [DriftLogStore];
/// kept as an interface so callers (HTTP routes, tests) depend on behavior,
/// not on `drift` directly.
abstract class LogStore {
  /// Inserts [entries] under [projectId] in one transaction, returning the
  /// stored rows in the same order as [entries] — ids assigned
  /// (`log-server-storage`: every entry is tied to exactly one project).
  ///
  /// The rows rather than their ids, because the live stream broadcasts
  /// exactly what was committed (`log-server-live-stream`) and rebuilding
  /// a row from its companion would be a second, drift-prone copy of the
  /// mapping.
  Future<List<LogEntry>> insertBatch(
    int projectId,
    List<LogEntriesCompanion> entries,
  );

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
    return _db.transaction(() async {
      final rows = <LogEntry>[];
      for (final entry in entries) {
        final row = await _db
            .into(_db.logEntries)
            .insertReturning(entry.copyWith(projectId: Value(projectId)));
        rows.add(row);
      }
      return rows;
    });
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
