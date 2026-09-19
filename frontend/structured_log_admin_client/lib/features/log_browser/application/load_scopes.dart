import 'package:fpdart/fpdart.dart';

import '../../../shared/api/api_failure.dart';
import '../domain/log_browser_repository.dart';
import '../domain/log_scope.dart';

/// What the scope selector may offer.
class LoadScopes {
  final LogBrowserRepository _repository;

  const LoadScopes(this._repository);

  Future<Either<ApiFailure, ScopeOptions>> call() => _repository.loadScopes();

  /// The next page of the groups, or of the projects, after [cursor].
  Future<Either<ApiFailure, ScopeOptions>> more({
    required bool groups,
    required String cursor,
  }) => _repository.loadMoreScopes(groups: groups, cursor: cursor);
}
