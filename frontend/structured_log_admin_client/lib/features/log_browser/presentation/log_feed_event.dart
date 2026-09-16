import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../shared/api/api_failure.dart';
import '../../../shared/api/dto/log_dto.dart';
import '../domain/log_filter.dart';
import '../domain/log_scope.dart';

part 'log_feed_event.freezed.dart';

/// Everything that can move the log feed.
///
/// One list, whatever the source: what the reader does, and what the live
/// subscription delivers, arrive the same way. That is the point of using a
/// `Bloc` here rather than a `Cubit` with methods — the transitions of
/// design.md decision 30 are written once, as handlers, instead of being
/// spread across call sites (decision 36).
///
/// The `live*` events are raised by the bloc's own subscription rather than
/// by a screen. They are not private, because the tests that hold the
/// transition diagram drive them directly.
@freezed
sealed class LogFeedEvent with _$LogFeedEvent {
  /// Fetch what the scope selector may offer. Nothing is queried yet.
  const factory LogFeedEvent.started() = LogFeedStarted;

  /// The one scope to read. Loads the newest page and opens the subscription.
  const factory LogFeedEvent.scopeSelected(LogScope scope) =
      LogFeedScopeSelected;

  /// Back to the selector — the list and the subscription are dropped.
  const factory LogFeedEvent.scopeCleared() = LogFeedScopeCleared;

  /// Replace the whole filter. Callers build the new value from the old one
  /// with `copyWith`, so a screen never has to know which fields exist.
  const factory LogFeedEvent.filterChanged(LogFilter filter) =
      LogFeedFilterChanged;

  /// The page before the oldest one held — raised by scrolling to the top.
  const factory LogFeedEvent.olderRequested() = LogFeedOlderRequested;

  /// Load the newest page again and resubscribe, keeping scope and filter.
  const factory LogFeedEvent.reloadRequested() = LogFeedReloadRequested;

  /// Open an entry in the detail pane, or close it with `null`.
  const factory LogFeedEvent.entrySelected(int? entryId) = LogFeedEntrySelected;

  /// The list is at its end again: follow the live edge and clear the unseen
  /// count.
  const factory LogFeedEvent.scrolledToBottom() = LogFeedScrolledToBottom;

  /// The reader scrolled off the live edge. New entries stop moving the view.
  const factory LogFeedEvent.scrolledAwayFromBottom() =
      LogFeedScrolledAwayFromBottom;

  /// Freeze the visible list. The subscription stays open (decision 30).
  const factory LogFeedEvent.pauseRequested() = LogFeedPauseRequested;

  /// Show what arrived during the pause and return to the live edge — or, if
  /// the buffer overflowed, reload the newest page instead.
  const factory LogFeedEvent.resumeRequested() = LogFeedResumeRequested;

  /// One entry off the live subscription.
  const factory LogFeedEvent.liveEntryArrived(LogEntryDto entry) =
      LogFeedLiveEntryArrived;

  /// The server ended the subscription for a reason reconnecting cannot fix.
  const factory LogFeedEvent.liveEnded(String reason) = LogFeedLiveEnded;

  /// The subscription could not be opened at all.
  const factory LogFeedEvent.liveFailed(ApiFailure failure) = LogFeedLiveFailed;
}
