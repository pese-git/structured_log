import 'package:meta/meta.dart';

/// Typed correlation identifiers commonly needed by non-trivial clients
/// (sessions, requests, reconnects, async operations).
///
/// All fields are optional — pass only the ones you have at hand. Fields are
/// serialized under fixed snake_case keys: `session_id`, `request_id`,
/// `connection_generation`, `tool_call_id`, `message_id`, `operation_id`.
///
/// You rarely construct this directly — [BoundLogger.withCorrelation]
/// builds and merges it for you:
///
/// ```dart
/// final sessionLog = getLogger().withCorrelation(
///   sessionId: 's-14',
///   requestId: 'r-42',
/// );
/// sessionLog.info('processing_request');
/// // entry includes: {"session_id": "s-14", "request_id": "r-42"}
/// ```
@immutable
class LogCorrelation {
  final String? sessionId;
  final String? requestId;
  final int? connectionGeneration;
  final String? toolCallId;
  final String? messageId;
  final String? operationId;

  const LogCorrelation({
    this.sessionId,
    this.requestId,
    this.connectionGeneration,
    this.toolCallId,
    this.messageId,
    this.operationId,
  });

  /// Returns a new [LogCorrelation] where each field of [other] overrides
  /// the corresponding field here, wherever [other]'s field is non-null.
  /// Fields [other] leaves `null` fall back to this instance's value — this
  /// is how [BoundLogger.withCorrelation] lets a child scope add or replace
  /// just a few fields while inheriting the rest from its parent.
  ///
  /// ```dart
  /// const parent = LogCorrelation(sessionId: 's-14', requestId: 'r-42');
  /// const child = LogCorrelation(toolCallId: 'tc-3');
  /// final merged = parent.merge(child);
  /// // merged: sessionId: 's-14', requestId: 'r-42', toolCallId: 'tc-3'
  /// ```
  LogCorrelation merge(LogCorrelation other) {
    return LogCorrelation(
      sessionId: other.sessionId ?? sessionId,
      requestId: other.requestId ?? requestId,
      connectionGeneration: other.connectionGeneration ?? connectionGeneration,
      toolCallId: other.toolCallId ?? toolCallId,
      messageId: other.messageId ?? messageId,
      operationId: other.operationId ?? operationId,
    );
  }

  /// Non-null fields as a context map under fixed snake_case keys, ready to
  /// merge into a log entry. Fields left `null` are omitted entirely
  /// (rather than included as `null`), so this map never needs
  /// [dropNullValues] run on it.
  ///
  /// ```dart
  /// const correlation = LogCorrelation(sessionId: 's-14', requestId: 'r-42');
  /// print(correlation.toContext());
  /// // {session_id: s-14, request_id: r-42}
  /// ```
  Map<String, dynamic> toContext() => {
        if (sessionId != null) 'session_id': sessionId,
        if (requestId != null) 'request_id': requestId,
        if (connectionGeneration != null)
          'connection_generation': connectionGeneration,
        if (toolCallId != null) 'tool_call_id': toolCallId,
        if (messageId != null) 'message_id': messageId,
        if (operationId != null) 'operation_id': operationId,
      };
}
