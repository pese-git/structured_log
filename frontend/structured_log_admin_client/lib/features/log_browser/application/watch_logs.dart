import '../domain/live_feed_event.dart';
import '../domain/log_browser_repository.dart';
import '../domain/log_filter.dart';
import '../domain/log_scope.dart';

/// The live subscription for a scope and a filter.
///
/// Opened right after the first page, with [sinceId] set to the newest entry
/// that page held — that is what closes the gap between the two without
/// repeating an entry (`log-server-live-stream`).
class WatchLogs {
  final LogBrowserRepository _repository;

  const WatchLogs(this._repository);

  Stream<LiveFeedEvent> call({
    required LogScope scope,
    required LogFilter filter,
    int? sinceId,
  }) {
    return _repository.watch(scope: scope, filter: filter, sinceId: sinceId);
  }
}
