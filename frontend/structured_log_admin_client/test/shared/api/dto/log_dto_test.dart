import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_client/shared/api/dto/log_dto.dart';

/// One entry as `GET /v1/logs` actually sends it: the application's own
/// object with the server's three fields merged on top, no nesting anywhere.
Map<String, dynamic> _entry([Map<String, dynamic> extra = const {}]) => {
  'event': 'Webhook delivery failed after 3 attempts',
  'level': 'error',
  'timestamp': '2026-09-15T09:12:55.000Z',
  'category': 'webhooks',
  'logger': 'webhook.sender',
  'request_id': 'req-9f2c',
  'session_id': 'sess-4ab1',
  'operation_id': 'op-8e77',
  'connection_generation': 3,
  ...extra,
  'id': 918273,
  'project_id': 42,
  'received_at': '2026-09-15T09:12:55.120Z',
};

void main() {
  test('standard fields are lifted out of the flat object', () {
    final entry = LogEntryDto.fromJson(_entry());

    expect(entry.id, 918273);
    expect(entry.projectId, 42);
    expect(entry.event, 'Webhook delivery failed after 3 attempts');
    expect(entry.level, 'error');
    expect(entry.category, 'webhooks');
    expect(entry.logger, 'webhook.sender');
    expect(entry.receivedAt.isUtc, isTrue);
    expect(entry.timestamp, isNotNull);
  });

  test('correlation is standard, not arbitrary context', () {
    final entry = LogEntryDto.fromJson(_entry());

    expect(entry.requestId, 'req-9f2c');
    expect(entry.sessionId, 'sess-4ab1');
    expect(entry.operationId, 'op-8e77');
    expect(entry.connectionGeneration, 3);
    // The detail view shows correlation in its own block
    // (`specs/admin-client-log-browser`), which it cannot do if these arrive
    // mixed in with the application's own fields.
    expect(entry.context, isEmpty);
  });

  test('everything the application bound itself is kept', () {
    final entry = LogEntryDto.fromJson(
      _entry({
        'webhook_url': 'https://example.test/hooks/42',
        'attempt': 3,
        'status_code': 504,
        'duration_ms': 1200.5,
      }),
    );

    expect(entry.context, {
      'webhook_url': 'https://example.test/hooks/42',
      'attempt': 3,
      'status_code': 504,
      'duration_ms': 1200.5,
    });
  });

  test('an entry missing event or level still parses', () {
    // Better a row with an empty event than a page that throws: one damaged
    // entry must not take down the whole result set.
    final entry = LogEntryDto.fromJson({
      'id': 1,
      'project_id': 42,
      'received_at': '2026-09-15T09:12:55.120Z',
    });

    expect(entry.event, isEmpty);
    expect(entry.level, 'info');
    expect(entry.timestamp, isNull);
    expect(entry.context, isEmpty);
  });

  test('a page carries its cursor, and null means the last one', () {
    final page = LogPageDto.fromJson({
      'items': [_entry()],
      'next_cursor': '918272',
    });
    expect(page.items, hasLength(1));
    expect(page.nextCursor, '918272');

    final last = LogPageDto.fromJson({'items': [], 'next_cursor': null});
    expect(last.items, isEmpty);
    expect(last.nextCursor, isNull);
  });
}
