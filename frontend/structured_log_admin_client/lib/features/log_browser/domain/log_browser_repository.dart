import 'package:fpdart/fpdart.dart';

import '../../../shared/api/api_failure.dart';
import '../../../shared/api/dto/log_dto.dart';
import 'live_feed_event.dart';
import 'log_filter.dart';
import 'log_scope.dart';

/// One page of entries, plus the cursor that reaches the next one.
typedef LogPage = ({List<LogEntryDto> entries, String? nextCursor});

abstract interface class LogBrowserRepository {
  /// What the scope selector may offer — the caller's readable groups and
  /// projects.
  Future<Either<ApiFailure, ScopeOptions>> loadScopes();

  /// The page after [cursor] of the groups or of the projects — only what was
  /// newly read, with the cursor to go on from (`ScopeOptions.groupsCursor`/
  /// `projectsCursor`, whichever [groups] names).
  Future<Either<ApiFailure, ScopeOptions>> loadMoreScopes({
    required bool groups,
    required String cursor,
  });

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

  /// Entries accepted from now on, in the same scope and with the same filter
  /// as [query] — the subscription behind the chat-history feed
  /// (`specs/admin-client-log-browser`).
  ///
  /// [sinceId] is the newest entry already held, so the server replays the
  /// gap between that page and this subscription rather than leaving a hole.
  ///
  /// Not an `Either`: a live subscription has outcomes over time, not one
  /// outcome, so its refusals travel as [LiveFeedFailed] inside the stream
  /// and the stream itself never errors.
  Stream<LiveFeedEvent> watch({
    required LogScope scope,
    required LogFilter filter,
    int? sinceId,
  });
}
