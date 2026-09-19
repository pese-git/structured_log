import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../shared/api/api_failure.dart';
import '../../../shared/api/dto/log_dto.dart';
import '../domain/log_filter.dart';
import '../domain/log_scope.dart';

part 'log_feed_state.freezed.dart';

/// How the feed is following the live edge (design.md decision 30).
///
/// These three are genuinely exclusive — the feed is doing exactly one of
/// them — so they are a union, and the transition diagram of decision 30 is
/// the set of moves between them:
///
/// ```text
///                scrolled away from bottom
///   Following ─────────────────────────────▶ ScrolledUp(unseen: n)
///       ▲                                          │
///       └────────── back at the bottom ────────────┘
///       │                                          │
///       │  resume (buffer flushed, or reloaded)    │  pause
///       └──────────────── Paused(buffered: n) ◀────┘
/// ```
///
/// Pausing from [FeedScrolledUp] loses the unseen count on purpose: resuming
/// returns to the live edge, where there is nothing unseen left to count.
@freezed
sealed class LogFeedMode with _$LogFeedMode {
  /// At the live edge: new entries are appended and the list follows them.
  const factory LogFeedMode.following() = FeedFollowing;

  /// Reading history. New entries are still appended — they are simply below
  /// the fold — and [unseen] counts them for the "N new entries" indicator.
  /// Nothing moves the reader's scroll position.
  const factory LogFeedMode.scrolledUp({@Default(0) int unseen}) =
      FeedScrolledUp;

  /// Explicitly paused. The visible list is frozen; entries keep arriving on
  /// the open subscription and wait in a bounded buffer.
  ///
  /// [overflowed] means that buffer filled and the oldest waiting entries
  /// were dropped, so resuming reloads the newest page instead of showing a
  /// list with a hole in it (`specs/admin-client-log-browser`).
  const factory LogFeedMode.paused({
    @Default(0) int buffered,
    @Default(false) bool overflowed,
  }) = FeedPaused;

  const LogFeedMode._();

  bool get isPaused => this is FeedPaused;
}

/// What the log screen is showing.
///
/// A data class carrying one union, not a union itself. Having a scope, a page
/// in flight, an entry selected and a failure are simultaneous conditions
/// rather than alternatives — only the live-follow mode is a genuine
/// either/or, and that is [mode]. Modelling the whole screen as a union would
/// have meant repeating `entries`/`nextCursor`/`selectedEntryId` in every
/// variant and reaching them through a `switch`.
///
/// `scope == null` is the whole "no scope yet" state, and nothing is queried
/// while it holds.
@freezed
abstract class LogFeedState with _$LogFeedState {
  const factory LogFeedState({
    /// `null` until the selector's contents have been fetched.
    ScopeOptions? options,
    @Default(true) bool loadingOptions,

    /// A further page of the selector's groups or projects is on its way.
    @Default(false) bool loadingMoreScopes,

    /// The one scope being read. Until it is set the selector stands in place
    /// of the list and no request goes out (`specs/admin-client-log-browser`).
    LogScope? scope,

    @Default(LogFilter()) LogFilter filter,

    /// Oldest first, as a chat history reads. The live edge is the end.
    @Default(<LogEntryDto>[]) List<LogEntryDto> entries,

    /// Cursor for the page after the oldest one held. `null` means the
    /// beginning of the log has been reached.
    String? nextCursor,

    /// The first page for the current scope and filter is on its way.
    @Default(false) bool loading,

    /// An older page is being appended at the top.
    @Default(false) bool loadingMore,

    /// The entry the detail pane is showing, by id — not the object, so a
    /// reloaded page cannot leave the pane holding a stale copy.
    int? selectedEntryId,

    @Default(LogFeedMode.following()) LogFeedMode mode,

    /// Why the server closed the live subscription for good, if it did —
    /// `project_blocked` and nothing else today. The list keeps whatever it
    /// held; only the live half stopped, and the screen has to say so rather
    /// than look like a quiet project.
    String? liveEndReason,

    ApiFailure? failure,
  }) = _LogFeedState;

  const LogFeedState._();

  bool get hasScope => scope != null;

  /// There is an older page to fetch, and nothing is fetching it.
  bool get canLoadMore => nextCursor != null && !loading && !loadingMore;

  /// Entries waiting out an explicit pause, or unseen below the fold.
  int get pendingCount => switch (mode) {
    FeedFollowing() => 0,
    FeedScrolledUp(:final unseen) => unseen,
    FeedPaused(:final buffered) => buffered,
  };

  LogEntryDto? get selectedEntry {
    final id = selectedEntryId;
    if (id == null) return null;
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }
}
