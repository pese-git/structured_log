import 'package:drift/drift.dart';

import 'database.dart';
import 'query.dart';

/// Persists and queries [LogEntries] rows. Implemented by [DriftLogStore];
/// kept as an interface so callers (HTTP routes, tests) depend on behavior,
/// not on `drift` directly.
abstract class LogStore {
  /// Inserts [entries] under [projectId] in one transaction, returning the
  /// assigned `id` of each inserted row in the same order as [entries]
  /// (`log-server-storage`: every entry is tied to exactly one project).
  Future<List<int>> insertBatch(
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
  Future<List<int>> insertBatch(
    int projectId,
    List<LogEntriesCompanion> entries,
  ) {
    return _db.transaction(() async {
      final ids = <int>[];
      for (final entry in entries) {
        final id = await _db
            .into(_db.logEntries)
            .insert(entry.copyWith(projectId: Value(projectId)));
        ids.add(id);
      }
      return ids;
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
