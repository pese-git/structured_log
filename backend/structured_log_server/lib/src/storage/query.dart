import 'package:drift/drift.dart';

import 'database.dart';
import 'log_filter.dart';

export 'log_filter.dart' show LogFilter, logLevelOrder;

/// A filter + time range + pagination request for [LogStore.query].
///
/// [projectIds] is the already-authorized, already-unblocked scope to query
/// — resolving `project_id`/`group_id` from the request into this list, and
/// checking RBAC/`is_blocked`, is the caller's job (`log-server-api`,
/// `log-server-rbac`), not the storage layer's.
///
/// [filter] is the part shared with the live stream (`LogFilter`); the time
/// range and cursor are not, since a subscription is by definition about
/// what arrives from now on.
class LogQuery {
  final List<int> projectIds;
  final LogFilter filter;
  final DateTime? from;
  final DateTime? to;
  final int limit;

  /// The `id` of the last entry on the previous page. `null` starts from
  /// the newest matching entry (`log-server-api`: no cursor → descending by
  /// `id`).
  final int? cursor;

  /// The `id` to read forward from, exclusive — the catch-up direction used
  /// by `GET /v1/logs/stream?since_id=N` (`log-server-live-stream`). Unlike
  /// [cursor] it selects entries *newer* than the given id and orders them
  /// oldest-first, so they can be replayed in the order they arrived.
  final int? afterId;

  const LogQuery({
    required this.projectIds,
    this.filter = const LogFilter(),
    this.from,
    this.to,
    this.limit = 50,
    this.cursor,
    this.afterId,
  })  : assert(projectIds.length > 0, 'projectIds must not be empty'),
        assert(limit > 0, 'limit must be positive'),
        assert(
          cursor == null || afterId == null,
          'cursor (older than) and afterId (newer than) are opposite '
          'directions and cannot be combined',
        );
}

/// One page of [LogQuery] results. [nextCursor] is the `id` to pass back as
/// [LogQuery.cursor] for the next (older) page — `null` on the last page
/// (`log-server-pagination`).
class LogQueryPage {
  final List<LogEntry> entries;
  final int? nextCursor;

  const LogQueryPage({required this.entries, required this.nextCursor});
}

/// Renders [LogQuery] into a `SELECT * FROM log_entries ...` statement and
/// its bound variables. `LIKE`/`json_extract` conditions aren't expressible
/// through drift's typed query builder (`design.md` decision 3), so the
/// whole query is assembled as one raw statement instead of mixing builder
/// and `customSelect` fragments.
({String sql, List<Variable<Object>> variables}) buildLogQuerySql(
  LogQuery query,
) {
  final conditions = <String>[];
  final variables = <Variable<Object>>[];

  conditions.add(
    'project_id IN (${List.filled(query.projectIds.length, '?').join(', ')})',
  );
  variables.addAll(query.projectIds.map(Variable.withInt));

  query.filter.appendConditions(conditions, variables);

  if (query.from != null) {
    conditions.add('timestamp >= ?');
    variables.add(Variable.withDateTime(query.from!));
  }

  if (query.to != null) {
    conditions.add('timestamp <= ?');
    variables.add(Variable.withDateTime(query.to!));
  }

  if (query.cursor != null) {
    conditions.add('id < ?');
    variables.add(Variable.withInt(query.cursor!));
  }

  if (query.afterId != null) {
    conditions.add('id > ?');
    variables.add(Variable.withInt(query.afterId!));
  }

  variables.add(Variable.withInt(query.limit));

  // Catch-up reads forward and must replay in arrival order; paging reads
  // backward from the newest.
  final order = query.afterId != null ? 'ASC' : 'DESC';
  final sql = 'SELECT * FROM log_entries '
      'WHERE ${conditions.join(' AND ')} '
      'ORDER BY id $order '
      'LIMIT ?';

  return (sql: sql, variables: variables);
}
