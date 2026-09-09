import 'package:meta/meta.dart';

/// Typed correlation identifiers commonly needed by non-trivial clients
/// (sessions, requests, reconnects, async operations).
///
/// All fields are optional — pass only the ones you have at hand. Fields are
/// serialized under fixed snake_case keys: `session_id`, `request_id`,
/// `connection_generation`, `tool_call_id`, `message_id`, `operation_id`.
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

  /// Non-null fields as a context map under fixed snake_case keys.
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
