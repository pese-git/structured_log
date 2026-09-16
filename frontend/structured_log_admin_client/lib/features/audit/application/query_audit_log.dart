import 'package:fpdart/fpdart.dart';

import '../../../shared/api/api_failure.dart';
import '../../../shared/api/dto/audit_dto.dart';
import '../domain/audit_filter.dart';
import '../domain/audit_repository.dart';

/// Reading the audit log — the whole of what this feature can do.
///
/// One class with two entry points rather than two classes with one method
/// each, on the same principle as `ManageGroups`: both are the same screen's
/// work about the same thing, and the pair is what makes the paging contract
/// legible — [first] starts a query, [more] continues exactly that one.
class QueryAuditLog {
  final AuditRepository _repository;

  const QueryAuditLog(this._repository);

  /// The newest page for [filter]. Always starts over, which is what a changed
  /// filter requires (`specs/admin-client-audit-log`).
  Future<Either<ApiFailure, AuditPageDto>> first({
    AuditFilter filter = const AuditFilter(),
    int? limit,
  }) => _repository.query(filter: filter, limit: limit);

  /// The next, older page of the same query.
  ///
  /// [filter] has to be passed again, and has to be the one [first] was called
  /// with: the server re-applies it on every page, so a cursor carried onto a
  /// different filter would return records the reader never asked for.
  Future<Either<ApiFailure, AuditPageDto>> more({
    required String cursor,
    AuditFilter filter = const AuditFilter(),
    int? limit,
  }) => _repository.query(filter: filter, cursor: cursor, limit: limit);
}
