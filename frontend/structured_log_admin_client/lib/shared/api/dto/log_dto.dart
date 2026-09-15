/// One entry as `GET /v1/logs` returns it.
///
/// **Hand-written, not generated.** The server spreads the stored context
/// across the top level of the object — `{...context, id, project_id,
/// received_at}` — so an entry's own fields sit beside arbitrary ones the
/// application logged. `json_serializable` has no way to express "these keys
/// are mine, keep the rest", and dropping the rest would throw away exactly
/// what the detail pane exists to show (`specs/admin-client-log-browser`).
class LogEntryDto {
  final int id;
  final int projectId;

  /// When the server accepted the entry — not when the application logged it.
  final DateTime receivedAt;

  final String event;
  final String level;

  /// The application's own timestamp. Absent on entries sent without one.
  final DateTime? timestamp;

  final String? category;
  final String? logger;

  /// Correlation. The spec counts these among an entry's standard fields
  /// rather than among its arbitrary ones (`specs/admin-client-log-browser`),
  /// so the detail view shows them in their own block — which it cannot do if
  /// they arrive mixed into [context].
  final String? sessionId;
  final String? requestId;
  final String? toolCallId;
  final String? messageId;
  final String? operationId;

  /// The only correlation value that is not a string.
  final int? connectionGeneration;

  /// Everything the entry carried that is none of the fields above — whatever
  /// the application bound itself. Shown in the detail pane on equal footing
  /// with the standard fields, which is the whole reason it is kept.
  final Map<String, dynamic> context;

  const LogEntryDto({
    required this.id,
    required this.projectId,
    required this.receivedAt,
    required this.event,
    required this.level,
    required this.context,
    this.timestamp,
    this.category,
    this.logger,
    this.sessionId,
    this.requestId,
    this.toolCallId,
    this.messageId,
    this.operationId,
    this.connectionGeneration,
  });

  /// Keys lifted into named fields; everything else stays in [context].
  static const _ownKeys = {
    'id',
    'project_id',
    'received_at',
    'event',
    'level',
    'timestamp',
    'category',
    'logger',
    'session_id',
    'request_id',
    'tool_call_id',
    'message_id',
    'operation_id',
    'connection_generation',
  };

  factory LogEntryDto.fromJson(Map<String, dynamic> json) {
    return LogEntryDto(
      id: json['id'] as int,
      projectId: json['project_id'] as int,
      receivedAt: DateTime.parse(json['received_at'] as String),
      // Defaulted rather than required: an entry that reached storage without
      // one is still worth showing, and a parse that threw would take the
      // whole page down with it.
      event: json['event'] as String? ?? '',
      level: json['level'] as String? ?? 'info',
      timestamp: json['timestamp'] is String
          ? DateTime.tryParse(json['timestamp'] as String)
          : null,
      category: json['category'] as String?,
      logger: json['logger'] as String?,
      sessionId: json['session_id'] as String?,
      requestId: json['request_id'] as String?,
      toolCallId: json['tool_call_id'] as String?,
      messageId: json['message_id'] as String?,
      operationId: json['operation_id'] as String?,
      connectionGeneration: json['connection_generation'] as int?,
      context: {
        for (final entry in json.entries)
          if (!_ownKeys.contains(entry.key)) entry.key: entry.value,
      },
    );
  }
}

/// One page of `GET /v1/logs`.
class LogPageDto {
  final List<LogEntryDto> items;

  /// Opaque; pass it back as `cursor` for the next page. `null` means this
  /// was the last one.
  final String? nextCursor;

  const LogPageDto({required this.items, this.nextCursor});

  factory LogPageDto.fromJson(Map<String, dynamic> json) {
    return LogPageDto(
      items: (json['items'] as List<dynamic>)
          .map((item) => LogEntryDto.fromJson(item as Map<String, dynamic>))
          .toList(),
      nextCursor: json['next_cursor'] as String?,
    );
  }
}
