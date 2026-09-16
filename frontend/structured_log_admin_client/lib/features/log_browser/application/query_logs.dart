import 'package:fpdart/fpdart.dart';

import '../../../shared/api/api_failure.dart';
import '../domain/log_browser_repository.dart';
import '../domain/log_filter.dart';
import '../domain/log_scope.dart';

/// One page of entries for a scope and a filter.
class QueryLogs {
  final LogBrowserRepository _repository;

  /// How many entries a page holds. Fifty is the server's own default; it is
  /// named here so the cubit and the tests agree on it.
  static const pageSize = 50;

  const QueryLogs(this._repository);

  Future<Either<ApiFailure, LogPage>> call({
    required LogScope scope,
    required LogFilter filter,
    String? cursor,
  }) {
    return _repository.query(
      scope: scope,
      filter: filter,
      cursor: cursor,
      limit: pageSize,
    );
  }
}
