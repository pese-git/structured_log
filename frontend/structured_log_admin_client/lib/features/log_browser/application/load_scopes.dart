import 'package:fpdart/fpdart.dart';

import '../../../shared/api/api_failure.dart';
import '../domain/log_browser_repository.dart';
import '../domain/log_scope.dart';

/// What the scope selector may offer.
class LoadScopes {
  final LogBrowserRepository _repository;

  const LoadScopes(this._repository);

  Future<Either<ApiFailure, ScopeOptions>> call() => _repository.loadScopes();
}
