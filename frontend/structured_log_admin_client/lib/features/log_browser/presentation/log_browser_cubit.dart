import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../shared/api/dto/log_dto.dart';
import '../application/load_scopes.dart';
import '../application/query_logs.dart';
import '../domain/log_filter.dart';
import '../domain/log_scope.dart';
import 'log_browser_state.dart';

/// The log browser's state.
///
/// Holds the rule the spec is built around: **nothing is queried until a
/// scope is chosen**, and changing the scope or any filter starts again from
/// the newest page rather than continuing a query that no longer matches.
class LogBrowserCubit extends Cubit<LogBrowserState> {
  final LoadScopes _loadScopes;
  final QueryLogs _queryLogs;

  /// Guards against an answer from a superseded request overwriting a newer
  /// one. Two filter changes in quick succession produce two requests, and
  /// the first can land second.
  int _generation = 0;

  LogBrowserCubit({
    required LoadScopes loadScopes,
    required QueryLogs queryLogs,
  }) : _loadScopes = loadScopes,
       _queryLogs = queryLogs,
       super(const LogBrowserState());

  Future<void> start() async {
    final result = await _loadScopes();
    if (isClosed) return;
    result.match(
      (failure) =>
          emit(state.copyWith(loadingOptions: false, failure: failure)),
      (options) => emit(
        state.copyWith(loadingOptions: false, options: options, failure: null),
      ),
    );
  }

  /// Picks the one scope to read. Choosing the same one again is ignored, so
  /// re-selecting from a menu does not throw away a loaded list.
  Future<void> selectScope(LogScope scope) async {
    if (state.scope == scope) return;
    emit(state.copyWith(scope: scope, selectedEntryId: null));
    await _reload();
  }

  /// Replaces the whole filter. Callers build the new value from the old one
  /// with `copyWith`, so a screen never has to know which fields exist.
  Future<void> applyFilter(LogFilter filter) async {
    if (state.filter == filter) return;
    emit(state.copyWith(filter: filter, selectedEntryId: null));
    await _reload();
  }

  Future<void> clearFilter() => applyFilter(const LogFilter());

  /// Fetches the page before the oldest one held, appending it.
  ///
  /// Cursor-based, so two calls cannot return overlapping entries the way an
  /// offset would after new entries arrived.
  Future<void> loadMore() async {
    if (!state.canLoadMore) return;
    final scope = state.scope;
    if (scope == null) return;

    final generation = _generation;
    emit(state.copyWith(loadingMore: true));
    final result = await _queryLogs(
      scope: scope,
      filter: state.filter,
      cursor: state.nextCursor,
    );
    if (isClosed || generation != _generation) return;

    result.match(
      (failure) => emit(state.copyWith(loadingMore: false, failure: failure)),
      (page) => emit(
        state.copyWith(
          loadingMore: false,
          // Reversed, then prepended. `GET /v1/logs` answers newest-first
          // (`ORDER BY id DESC`) and its cursor walks backwards in time,
          // while the feed reads as a chat history — oldest at the top. So
          // each page is flipped, and an older page goes above what is
          // already there.
          entries: [..._chronological(page.entries), ...state.entries],
          nextCursor: page.nextCursor,
          failure: null,
        ),
      ),
    );
  }

  /// Opens an entry in the detail pane, or closes it when given `null`.
  void select(int? entryId) => emit(state.copyWith(selectedEntryId: entryId));

  Future<void> refresh() => _reload();

  /// Server order (newest first) into reading order (oldest first).
  ///
  /// Kept in one place because getting it wrong is invisible until someone
  /// reads a list of timestamps and finds them counting down.
  static List<LogEntryDto> _chronological(List<LogEntryDto> page) =>
      page.reversed.toList();

  Future<void> _reload() async {
    final scope = state.scope;
    if (scope == null) return;

    final generation = ++_generation;
    emit(
      state.copyWith(
        loading: true,
        // Cleared with the request, not when it answers: leaving the previous
        // scope's entries on screen while another scope loads shows one
        // scope's logs under another's name.
        entries: const [],
        nextCursor: null,
        failure: null,
      ),
    );

    final result = await _queryLogs(scope: scope, filter: state.filter);
    if (isClosed || generation != _generation) return;

    result.match(
      (failure) => emit(state.copyWith(loading: false, failure: failure)),
      (page) => emit(
        state.copyWith(
          loading: false,
          entries: _chronological(page.entries),
          nextCursor: page.nextCursor,
          failure: null,
        ),
      ),
    );
  }
}
