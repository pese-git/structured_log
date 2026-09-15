import 'package:fpdart/fpdart.dart';

import '../../../shared/api/api_failure.dart';
import '../../../shared/api/dto/log_dto.dart';
import 'log_filter.dart';
import 'log_scope.dart';

/// One page of entries, plus the cursor that reaches the next one.
typedef LogPage = ({List<LogEntryDto> entries, String? nextCursor});

abstract interface class LogBrowserRepository {
  /// What the scope selector may offer — the caller's readable groups and
  /// projects.
  Future<Either<ApiFailure, ScopeOptions>> loadScopes();

  /// One page. [cursor] continues a previous one; `null` starts over.
  ///
  /// Entries are returned exactly as the server sent them: `LogEntryDto` is
  /// already a plain value with the arbitrary context separated out, and a
  /// second identical domain class would be ceremony rather than insulation.
  Future<Either<ApiFailure, LogPage>> query({
    required LogScope scope,
    required LogFilter filter,
    String? cursor,
    int limit,
  });
}
