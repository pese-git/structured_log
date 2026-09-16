import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';

import '../../../shared/api/api_client.dart';
import '../../../shared/api/api_failure.dart';
import '../../../shared/api/dto/audit_dto.dart';
import '../../../shared/api/failure_mapper.dart';
import '../domain/audit_filter.dart';
import '../domain/audit_repository.dart';

class AuditRepositoryImpl implements AuditRepository {
  final ApiClient _api;

  const AuditRepositoryImpl(this._api);

  @override
  Future<Either<ApiFailure, AuditPageDto>> query({
    AuditFilter filter = const AuditFilter(),
    String? cursor,
    int? limit,
  }) {
    return _attempt(
      () => _api.audit.query(
        actorUserId: filter.actorUserId,
        action: filter.action,
        targetType: filter.targetType,
        targetId: filter.targetId,
        // UTC, as the server parses it. Sending local time would move the
        // window by the reader's own offset without saying so — the same rule
        // the log browser follows in `logQueryParameters`.
        from: filter.from?.toUtc().toIso8601String(),
        to: filter.to?.toUtc().toIso8601String(),
        cursor: cursor,
        limit: limit,
      ),
    );
  }

  /// The one call here has the same two outcomes as every call in the client,
  /// and the same one way of telling them apart.
  Future<Either<ApiFailure, T>> _attempt<T>(Future<T> Function() call) async {
    try {
      return right(await call());
    } on DioException catch (error) {
      return left(mapDioException(error));
    }
  }
}
