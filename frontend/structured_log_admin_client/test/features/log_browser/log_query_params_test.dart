import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_admin_client/features/log_browser/domain/log_filter.dart';
import 'package:structured_log_admin_client/features/log_browser/domain/log_scope.dart';
import 'package:structured_log_admin_client/features/log_browser/infrastructure/log_browser_repository_impl.dart';
import 'package:structured_log_admin_client/features/log_browser/infrastructure/log_query_params.dart';
import 'package:structured_log_admin_client/features/log_browser/infrastructure/log_stream_client.dart';
import 'package:structured_log_admin_client/shared/api/api_client.dart';
import 'package:structured_log_admin_client/shared/auth/token_storage.dart';
import 'package:structured_log_admin_client/shared/config/app_config.dart';

import '../../shared/api/fake_adapter.dart';

const _config = AppConfig(baseUrl: 'https://logs.example.test');

const _emptyPage = FakeReply(
  200,
  body: {'items': <Object?>[], 'next_cursor': null},
);

/// Everything at once, so a filter field that is only carried by one of the
/// two paths shows up as a difference rather than as a silent omission.
final _everything = LogFilter(
  minLevel: 'warning',
  category: 'payments',
  logger: 'webhook.sender',
  search: 'failed',
  from: DateTime.utc(2026, 9, 15, 6),
  to: DateTime.utc(2026, 9, 15, 7),
  sessionId: 'sess-1',
  requestId: 'req-2',
  toolCallId: 'tool-3',
  messageId: 'msg-4',
  operationId: 'op-5',
  connectionGeneration: 7,
  context: const {'user_id': '99'},
);

void main() {
  setUp(
    () => StructlogConfiguration.configure(
      sinks: [LogSink(name: 'silent', output: (_, _) {})],
    ),
  );
  tearDown(StructlogConfiguration.reset);

  /// The query `GET /v1/logs` actually goes out with, for [scope] and
  /// [_everything] — taken off the wire rather than from the mapping code.
  Future<Map<String, dynamic>> pagedQuery(LogScope scope) async {
    final adapter = FakeAdapter((_) => _emptyPage);
    final api = ApiClient(
      config: _config,
      storage: InMemoryTokenStorage(),
      adapter: adapter,
    );
    await LogBrowserRepositoryImpl(
      api,
      LogStreamClient(api.dio, logger: getLogger('test')),
    ).query(scope: scope, filter: _everything);
    return Map<String, dynamic>.from(adapter.requests.single.queryParameters)
      // Paging belongs to the list alone; the subscription has no cursor.
      ..remove('cursor')
      ..remove('limit');
  }

  /// Both halves of the screen have to narrow by the same thing, or the live
  /// feed delivers entries the list would never have shown — and the two
  /// spell the parameters in different places: the list through the generated
  /// `LogsApi`, the stream through [logQueryParameters]. Nothing but this test
  /// notices when one grows a field the other does not.
  for (final (name, scope) in [
    ('a project', const LogScope.project(id: 42, name: 'payments')),
    ('a group', const LogScope.group(id: 7, name: 'acme')),
  ]) {
    test(
      'the list and the live stream ask for the same thing — $name',
      () async {
        final paged = await pagedQuery(scope);
        final streamed = logQueryParameters(scope: scope, filter: _everything);

        expect(streamed, paged);
      },
    );
  }

  test('since_id is the stream\'s alone', () {
    final withSince = logQueryParameters(
      scope: const LogScope.project(id: 42, name: 'payments'),
      filter: const LogFilter(),
      sinceId: 918273,
    );

    expect(withSince['since_id'], 918273);
    expect(
      logQueryParameters(
        scope: const LogScope.project(id: 42, name: 'payments'),
        filter: const LogFilter(),
      ),
      isNot(contains('since_id')),
      reason: 'a first subscription starts from now, not from zero',
    );
  });
}
