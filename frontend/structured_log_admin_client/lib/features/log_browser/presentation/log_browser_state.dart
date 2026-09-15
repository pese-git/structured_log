import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../shared/api/api_failure.dart';
import '../../../shared/api/dto/log_dto.dart';
import '../domain/log_filter.dart';
import '../domain/log_scope.dart';

part 'log_browser_state.freezed.dart';

/// What the log browser is showing.
///
/// A data class: the screen is one thing in several simultaneous conditions —
/// a scope chosen, a page loading, an entry selected — not one of a closed set
/// of shapes. `scope == null` is the whole "no scope yet" state, and nothing
/// queries the server while it holds.
@freezed
abstract class LogBrowserState with _$LogBrowserState {
  const factory LogBrowserState({
    /// `null` until the selector's contents have been fetched.
    ScopeOptions? options,
    @Default(true) bool loadingOptions,

    /// The one scope being read. Until it is set the selector stands in place
    /// of the list and no request goes out (`specs/admin-client-log-browser`).
    LogScope? scope,

    @Default(LogFilter()) LogFilter filter,
    @Default(<LogEntryDto>[]) List<LogEntryDto> entries,

    /// Cursor for the page after the oldest one held. `null` means the
    /// beginning of the log has been reached.
    String? nextCursor,

    /// The first page for the current scope and filter is on its way.
    @Default(false) bool loading,

    /// An older page is being appended.
    @Default(false) bool loadingMore,

    /// The entry the detail pane is showing, by id — not the object, so a
    /// reloaded page cannot leave the pane holding a stale copy.
    int? selectedEntryId,

    ApiFailure? failure,
  }) = _LogBrowserState;

  const LogBrowserState._();

  bool get hasScope => scope != null;

  /// There is an older page to fetch, and nothing is fetching it.
  bool get canLoadMore => nextCursor != null && !loading && !loadingMore;

  LogEntryDto? get selectedEntry {
    final id = selectedEntryId;
    if (id == null) return null;
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }
}
