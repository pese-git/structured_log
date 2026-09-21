import 'dart:convert';

import 'package:drift/drift.dart';

import '../storage/database.dart';
import '../storage/query.dart' show logLevelOrder;

/// One entry `POST /v1/logs` rejected instead of storing — reported inside
/// the batch's `202` response body, never as a top-level HTTP error
/// (`log-server-api`).
class RejectedEntry {
  final int index;
  final String error;
  final String message;

  const RejectedEntry({
    required this.index,
    required this.error,
    required this.message,
  });

  Map<String, Object?> toJson() => {
    'index': index,
    'error': error,
    'message': message,
  };
}

/// The result of validating and quota-checking a submitted batch —
/// [accepted] is ready to hand to [LogStore.insertBatch]; [entryCountDelta]/
/// [bytesDelta] is what `project_usage` grows by for the accepted entries.
class IngestOutcome {
  final List<LogEntriesCompanion> accepted;
  final List<RejectedEntry> rejected;
  final int entryCountDelta;
  final int bytesDelta;

  const IngestOutcome({
    required this.accepted,
    required this.rejected,
    required this.entryCountDelta,
    required this.bytesDelta,
  });
}

/// Validates and quota-checks [rawEntries] (the parsed `POST /v1/logs` JSON
/// array) against a project's current `project_usage` and quota
/// (`log-server-api`, `log-server-quotas`). Entries are processed strictly
/// in order — quota limits apply cumulatively within the batch, not just
/// against the pre-batch usage snapshot (`log-server-quotas`: "Записи
/// внутри одного батча учитываются последовательно").
IngestOutcome processIngestBatch({
  required List<Object?> rawEntries,
  required int? maxEntries,
  required int? maxBytes,
  required int currentEntryCount,
  required int currentTotalBytes,
  required DateTime receivedAt,
}) {
  final accepted = <LogEntriesCompanion>[];
  final rejected = <RejectedEntry>[];
  var entryCount = currentEntryCount;
  var totalBytes = currentTotalBytes;

  for (var index = 0; index < rawEntries.length; index++) {
    final validated = _validateEntry(rawEntries[index], receivedAt);
    if (validated.error != null) {
      rejected.add(
        RejectedEntry(
          index: index,
          error: 'validation_error',
          message: validated.error!,
        ),
      );
      continue;
    }

    final sizeBytes = validated.sizeBytes!;
    final wouldExceedEntries =
        maxEntries != null && entryCount + 1 > maxEntries;
    final wouldExceedBytes =
        maxBytes != null && totalBytes + sizeBytes > maxBytes;
    if (wouldExceedEntries || wouldExceedBytes) {
      rejected.add(
        RejectedEntry(
          index: index,
          error: 'quota_exceeded',
          message: wouldExceedEntries
              ? 'project max_entries limit reached'
              : 'project max_bytes limit reached',
        ),
      );
      continue;
    }

    accepted.add(validated.companion!);
    entryCount += 1;
    totalBytes += sizeBytes;
  }

  return IngestOutcome(
    accepted: accepted,
    rejected: rejected,
    entryCountDelta: entryCount - currentEntryCount,
    bytesDelta: totalBytes - currentTotalBytes,
  );
}

class _ValidatedEntry {
  final LogEntriesCompanion? companion;
  final int? sizeBytes;
  final String? error;

  const _ValidatedEntry.ok(this.companion, this.sizeBytes) : error = null;
  const _ValidatedEntry.invalid(this.error)
    : companion = null,
      sizeBytes = null;
}

/// Names the server assigns to an entry when it reads one back.
///
/// An application cannot use them for its own fields: the query response is
/// built as `{...context, id, project_id, received_at}`, so anything sharing
/// one of these names would be overwritten on the way out.
const reservedEntryFieldNames = {'id', 'project_id', 'received_at'};

_ValidatedEntry _validateEntry(Object? raw, DateTime receivedAt) {
  if (raw is! Map) {
    return const _ValidatedEntry.invalid('entry must be a JSON object');
  }
  final map = Map<String, Object?>.from(raw);

  // `GET /v1/logs` returns an entry as its stored context with the server's
  // own three fields merged on top (`logs_route.dart`'s `logEntryJson`), so a
  // field of the same name would be shadowed at read: stored intact, never
  // visible again, and nothing would say so. Refusing it here is what makes
  // that loss impossible rather than silent.
  for (final reserved in reservedEntryFieldNames) {
    if (map.containsKey(reserved)) {
      return _ValidatedEntry.invalid(
        '$reserved: is a reserved field name and cannot be used in an entry',
      );
    }
  }

  final level = map['level'];
  if (level is! String || !logLevelOrder.contains(level)) {
    return _ValidatedEntry.invalid(
      'level: must be one of ${logLevelOrder.join(', ')}',
    );
  }

  final event = map['event'];
  if (event is! String || event.isEmpty) {
    return const _ValidatedEntry.invalid('event: is required');
  }

  final timestampRaw = map['timestamp'];
  final timestamp = timestampRaw is String
      ? DateTime.tryParse(timestampRaw)
      : null;
  if (timestamp == null) {
    return const _ValidatedEntry.invalid(
      'timestamp: must be a valid ISO 8601 string',
    );
  }

  for (final key in const [
    'category',
    'logger',
    'session_id',
    'request_id',
    'tool_call_id',
    'message_id',
    'operation_id',
  ]) {
    final value = map[key];
    if (value != null && value is! String) {
      return _ValidatedEntry.invalid('$key: must be a string');
    }
  }
  final connectionGeneration = map['connection_generation'];
  if (connectionGeneration != null && connectionGeneration is! int) {
    return const _ValidatedEntry.invalid(
      'connection_generation: must be an integer',
    );
  }

  final sizeBytes = utf8.encode(jsonEncode(map)).length;
  final companion = LogEntriesCompanion.insert(
    projectId: 0, // overwritten by the caller once the batch is accepted
    receivedAt: receivedAt,
    timestamp: timestamp,
    level: level,
    event: event,
    category: Value(map['category'] as String?),
    logger: Value(map['logger'] as String?),
    sessionId: Value(map['session_id'] as String?),
    requestId: Value(map['request_id'] as String?),
    connectionGeneration: Value(connectionGeneration as int?),
    toolCallId: Value(map['tool_call_id'] as String?),
    messageId: Value(map['message_id'] as String?),
    operationId: Value(map['operation_id'] as String?),
    sizeBytes: sizeBytes,
    contextJson: jsonEncode(map),
  );
  return _ValidatedEntry.ok(companion, sizeBytes);
}
