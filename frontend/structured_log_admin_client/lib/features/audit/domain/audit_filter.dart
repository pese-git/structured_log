import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../shared/api/dto/audit_dto.dart';

part 'audit_filter.freezed.dart';

/// Everything `GET /v1/audit-log` can narrow by, as one value.
///
/// One object rather than a pile of arguments, for the same reason as
/// [LogFilter] next door: "the filters changed" has to be a single comparison,
/// because that is the event that resets pagination — a cursor belongs to the
/// query that produced it, and continuing it against a changed filter would
/// page through a question nobody asked (`specs/admin-client-audit-log`).
///
/// The fields are exactly the five controls the screen is required to offer:
/// action, target type, target id, actor, and a time range. There is
/// deliberately no "records with no actor" filter — the storage layer can ask
/// it, but the route does not expose it, and the screen must not invent a
/// parameter the server would silently ignore.
@freezed
abstract class AuditFilter with _$AuditFilter {
  const factory AuditFilter({
    /// Who acted. A record with no actor at all — a login under a username
    /// that does not exist, a throttled request, the server's own purge — is
    /// matched by no value of this field, only by leaving it unset.
    int? actorUserId,

    /// One of the server's closed set. Typed rather than a raw string: the
    /// server refuses an unknown value with 400, so a filter that could hold
    /// one would turn a typo into a failed request instead of a menu choice.
    AuditAction? action,
    AuditTargetType? targetType,
    int? targetId,
    DateTime? from,
    DateTime? to,
  }) = _AuditFilter;

  const AuditFilter._();

  /// Whether anything is narrowing the query.
  ///
  /// Drives the "clear filters" affordance and, more importantly, the wording
  /// of an empty result: "nothing matched these filters", "nothing has
  /// happened yet" and "this is older than the server keeps" are three
  /// different things to tell a reader, and only the first two are decidable
  /// here.
  bool get isActive =>
      actorUserId != null ||
      action != null ||
      targetType != null ||
      targetId != null ||
      from != null ||
      to != null;
}
