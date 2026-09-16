import 'package:fpdart/fpdart.dart';

import '../../../shared/api/api_failure.dart';
import '../../../shared/api/dto/audit_dto.dart';
import 'audit_filter.dart';

/// The audit log, one page at a time.
///
/// One method, because the endpoint answers one question. The DTOs travel as
/// they are, as everywhere else in this client: they already mirror the wire,
/// and a second identical set of domain classes would be ceremony rather than
/// insulation (`resources_repository.dart`).
///
/// Nothing here writes. The journal is append-only and no endpoint mutates it
/// — that is a property the server guards
/// (`test/http/audit_immutability_test.dart`), and this interface keeps the
/// client from being the thing that asks.
abstract interface class AuditRepository {
  /// One page, newest first.
  ///
  /// [cursor] is the `next_cursor` of the page before it; it belongs to the
  /// filter that produced it, so a caller that changes [filter] must start
  /// over rather than carry the cursor across.
  Future<Either<ApiFailure, AuditPageDto>> query({
    AuditFilter filter,
    String? cursor,
    int? limit,
  });
}
