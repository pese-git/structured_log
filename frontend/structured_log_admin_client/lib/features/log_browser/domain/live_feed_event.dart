import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../shared/api/api_failure.dart';
import '../../../shared/api/dto/log_dto.dart';

part 'live_feed_event.freezed.dart';

/// What the live subscription hands to the feed.
///
/// The stream itself never errors: a subscription that cannot continue says so
/// with [LiveFeedEnded] or [LiveFeedFailed] and then closes. A `Stream` that
/// errors would make every consumer carry an `onError`, and the two terminal
/// cases here are expected outcomes rather than defects (design.md decision
/// 33) — the same reason the rest of the client returns `Either`.
///
/// Recoverable trouble — a dropped socket, a timed-out read, a 5xx, a
/// `token_revoked` the refresh can fix — never reaches here at all: the client
/// reconnects underneath (`LogStreamClient`), so a consumer sees an
/// uninterrupted run of entries.
@freezed
sealed class LiveFeedEvent with _$LiveFeedEvent {
  /// One entry, as `event: log` delivered it.
  const factory LiveFeedEvent.entry(LogEntryDto entry) = LiveFeedEntry;

  /// The server closed the subscription with `event: end` and a reason this
  /// client cannot resolve by reconnecting — `project_blocked` today.
  const factory LiveFeedEvent.ended(String reason) = LiveFeedEnded;

  /// The subscription could not be opened, and retrying would not help:
  /// the caller may not read this scope, or the session is over.
  const factory LiveFeedEvent.failed(ApiFailure failure) = LiveFeedFailed;
}
