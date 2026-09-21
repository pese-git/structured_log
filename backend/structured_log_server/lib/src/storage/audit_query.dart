import 'package:drift/drift.dart';

import '../audit/audit_action.dart';
import 'database.dart';
import 'page.dart';

/// A filter and one page's worth of pagination over the audit log.
///
/// Every field is a narrowing, and all of them combine — an operator asking
/// "what did this account do to that project last Tuesday" is asking one
/// question, not four (`specs/log-server-audit`).
class AuditQuery {
  /// Who acted. `null` matches every actor; it cannot be used to ask for
  /// records with no actor, which is what [actorAbsent] is for.
  final int? actorUserId;

  /// Records whose actor is null — failed logins under a username that does
  /// not exist, throttled requests, the server's own purge. A separate flag
  /// rather than a magic value, because "any actor" and "no actor" are
  /// different questions and a nullable int cannot say both.
  final bool actorAbsent;

  final AuditAction? action;
  final String? targetType;
  final int? targetId;
  final DateTime? from;
  final DateTime? to;
  final int limit;

  /// The `id` of the last record on the previous page; the next page is
  /// strictly older. Keyset rather than an offset for the same reason as
  /// `LogQuery`: rows arriving between two requests shift an offset and make
  /// pages overlap or skip.
  final int? cursor;

  const AuditQuery({
    this.actorUserId,
    this.actorAbsent = false,
    this.action,
    this.targetType,
    this.targetId,
    this.from,
    this.to,
    this.limit = 50,
    this.cursor,
  }) : assert(limit > 0, 'limit must be positive'),
       assert(
         !(actorAbsent && actorUserId != null),
         'actorAbsent asks for records with no actor; actorUserId asks for '
         'one particular actor — together they match nothing',
       );
}

/// One page of [AuditQuery] results. [nextCursor] is `null` once there is
/// nothing older left.
class AuditQueryPage {
  final List<AuditLogEntry> entries;
  final int? nextCursor;

  const AuditQueryPage({required this.entries, required this.nextCursor});
}

/// Renders [AuditQuery] into a statement and its bound variables.
///
/// Raw SQL to match `buildLogQuerySql`, which is next to this file and does
/// the same job for the other journal — two shapes for one kind of query
/// would make the pair harder to read than either alone.
({String sql, List<Variable<Object>> variables}) buildAuditQuerySql(
  AuditQuery query,
) {
  final conditions = <String>['1 = 1'];
  final variables = <Variable<Object>>[];

  if (query.actorAbsent) {
    conditions.add('actor_user_id IS NULL');
  } else if (query.actorUserId != null) {
    conditions.add('actor_user_id = ?');
    variables.add(Variable.withInt(query.actorUserId!));
  }

  if (query.action != null) {
    conditions.add('action = ?');
    variables.add(Variable.withString(query.action!.wire));
  }

  if (query.targetType != null) {
    conditions.add('target_type = ?');
    variables.add(Variable.withString(query.targetType!));
  }

  if (query.targetId != null) {
    conditions.add('target_id = ?');
    variables.add(Variable.withInt(query.targetId!));
  }

  if (query.from != null) {
    conditions.add('created_at >= ?');
    variables.add(Variable.withDateTime(query.from!));
  }

  if (query.to != null) {
    conditions.add('created_at <= ?');
    variables.add(Variable.withDateTime(query.to!));
  }

  if (query.cursor != null) {
    conditions.add('id < ?');
    variables.add(Variable.withInt(query.cursor!));
  }

  variables.add(Variable.withInt(query.limit));

  final sql =
      'SELECT * FROM audit_log_entries '
      'WHERE ${conditions.join(' AND ')} '
      'ORDER BY id DESC '
      'LIMIT ?';

  return (sql: sql, variables: variables);
}

/// Runs [query] and reports whether there is another page.
///
/// Asks for one row more than the caller wanted and drops it: the alternative
/// is a second `COUNT` query, or telling the reader "there may be more" on
/// every page including the last one.
Future<AuditQueryPage> runAuditQuery(
  StructuredLogDatabase db,
  AuditQuery query,
) async {
  final probe = buildAuditQuerySql(
    AuditQuery(
      actorUserId: query.actorUserId,
      actorAbsent: query.actorAbsent,
      action: query.action,
      targetType: query.targetType,
      targetId: query.targetId,
      from: query.from,
      to: query.to,
      limit: query.limit + 1,
      cursor: query.cursor,
    ),
  );

  final rows = await db
      .customSelect(
        probe.sql,
        variables: probe.variables,
        readsFrom: {db.auditLogEntries},
      )
      .get();

  final page = pageFromProbe(
    rows.map((row) => db.auditLogEntries.map(row.data)).toList(),
    query.limit,
    (entry) => entry.id,
  );

  return AuditQueryPage(entries: page.items, nextCursor: page.nextCursor);
}
