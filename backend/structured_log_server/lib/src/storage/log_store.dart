import 'package:drift/drift.dart';

import 'database.dart';
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
    final built = buildLogQuerySql(query);
    final rows = await _db.customSelect(
      built.sql,
      variables: built.variables,
      readsFrom: {_db.logEntries},
    ).get();
    final entries = rows.map((row) => _db.logEntries.map(row.data)).toList();
    return LogQueryPage(
      entries: entries,
      nextCursor: entries.isEmpty ? null : entries.last.id,
    );
  }
}
