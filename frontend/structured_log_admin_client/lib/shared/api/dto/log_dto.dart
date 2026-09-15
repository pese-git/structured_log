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

  /// Everything the entry carried that is not one of the fields above —
  /// correlation ids and whatever else the application bound. Shown in the
  /// detail pane on equal footing with the standard fields.
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
