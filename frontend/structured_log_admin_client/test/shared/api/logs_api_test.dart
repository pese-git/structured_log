import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_client/shared/api/api_client.dart';
import 'package:structured_log_admin_client/shared/api/logs_api.dart';
import 'package:structured_log_admin_client/shared/auth/token_storage.dart';
import 'package:structured_log_admin_client/shared/config/app_config.dart';

import 'fake_adapter.dart';

const _config = AppConfig(baseUrl: 'https://logs.example.test');

const _emptyPage = FakeReply(
  200,
  body: {'items': <Object?>[], 'next_cursor': null},
);

(ApiClient, FakeAdapter) _client() {
  final adapter = FakeAdapter((_) => _emptyPage);
  return (
    ApiClient(
      config: _config,
      storage: InMemoryTokenStorage(),
      adapter: adapter,
    ),
    adapter,
  );
}

void main() {
  test('correlation filters go out under the names the server reads', () async {
    final (client, adapter) = _client();

    await client.logs.query(
      projectId: 42,
      sessionId: 'sess-1',
      requestId: 'req-2',
      toolCallId: 'tool-3',
      messageId: 'msg-4',
      operationId: 'op-5',
      connectionGeneration: 7,
    );

    expect(adapter.requests.single.queryParameters, {
      'project_id': 42,
      'session_id': 'sess-1',
      'request_id': 'req-2',
      'tool_call_id': 'tool-3',
      'message_id': 'msg-4',
      'operation_id': 'op-5',
      'connection_generation': 7,
    });
  });

  test('contextQuery prefixes arbitrary keys', () {
    expect(contextQuery({'user_id': '7', 'tenant': 'acme'}), {
      'context.user_id': '7',
      'context.tenant': 'acme',
    });
    expect(contextQuery(const {}), isEmpty);
  });

  test(
    'context filters reach the query string alongside the named ones',
    () async {
      final (client, adapter) = _client();

      await client.logs.query(
        projectId: 42,
        level: 'warning',
        contextFilters: contextQuery({'user_id': '7'}),
      );

      expect(adapter.requests.single.queryParameters, {
        'project_id': 42,
        'level': 'warning',
        'context.user_id': '7',
      });
    },
  );

  test('filters that were not set are absent, not sent as null', () async {
    final (client, adapter) = _client();

    await client.logs.query(projectId: 42);

    // A `category=null` in the query string would be read as the literal
    // string and match nothing.
    expect(adapter.requests.single.queryParameters, {'project_id': 42});
  });

  test('a group-scoped query carries the group and no project', () async {
    final (client, adapter) = _client();

    await client.logs.query(groupId: 3, cursor: '918272', limit: 50);

    expect(adapter.requests.single.queryParameters, {
      'group_id': 3,
      'cursor': '918272',
      'limit': 50,
    });
  });
}
