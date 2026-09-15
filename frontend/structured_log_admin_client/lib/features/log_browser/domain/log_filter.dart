import 'package:freezed_annotation/freezed_annotation.dart';

part 'log_filter.freezed.dart';

/// Everything `GET /v1/logs` can narrow by, as one value.
///
/// One object rather than a pile of arguments so that "the filters changed"
/// is a single comparison — which is what resets pagination and, later, the
/// live subscription (`specs/admin-client-log-browser`).
@freezed
abstract class LogFilter with _$LogFilter {
  const factory LogFilter({
    /// Minimum severity, not an exact match: `warning` also returns errors.
    String? minLevel,
    String? category,
    String? logger,

    /// Full-text. The server runs it as `LIKE` over the event and the raw
    /// stored JSON, so it matches field names as well as values.
    String? search,
    DateTime? from,
    DateTime? to,
    String? sessionId,
    String? requestId,
    String? toolCallId,
    String? messageId,
    String? operationId,
    int? connectionGeneration,

    /// Equality on arbitrary context keys, without the `context.` prefix —
    /// the API client adds it.
    @Default(<String, String>{}) Map<String, String> context,
  }) = _LogFilter;

  const LogFilter._();

  /// Whether anything is narrowing the query. Drives the "clear filters"
  /// affordance and the empty state's wording: "nothing matched" and "nothing
  /// here yet" are different things to say.
  bool get isActive =>
      minLevel != null ||
      category != null ||
      logger != null ||
      (search != null && search!.isNotEmpty) ||
      from != null ||
      to != null ||
      sessionId != null ||
      requestId != null ||
      toolCallId != null ||
      messageId != null ||
      operationId != null ||
      connectionGeneration != null ||
      context.isNotEmpty;
}
