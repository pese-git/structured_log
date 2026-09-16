import 'package:cherrypick/cherrypick.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_client/shared/api/api_client.dart';
import 'package:structured_log_admin_client/shared/auth/token_pair.dart';
import 'package:structured_log_admin_client/shared/auth/token_storage.dart';
import 'package:structured_log_admin_client/shared/config/app_config.dart';
import 'package:structured_log_admin_client/testing/mock_server.dart';

import 'app_harness.dart';

/// The mock's own audit endpoint, driven through the real client.
///
/// Worth testing in its own right rather than only through a screen: the screen
/// tests that follow assume this answers the way the server does, and a mock
/// that quietly disagreed would make them pass about nothing.
void main() {
  late MockServer server;
  late ApiClient api;

  ApiClient clientFor(MockServer server) {
    final issued = server.issueSession();
    return ApiClient(
      config: const AppConfig(baseUrl: testBaseUrl),
      storage: InMemoryTokenStorage(
        TokenPair(
          accessToken: issued.accessToken,
          refreshToken: issued.refreshToken,
        ),
      ),
      adapter: server,
    );
  }

  setUp(() {
    server = MockServer();
    for (var i = 1; i <= 5; i++) {
      server.auditEntries.add(
        mockAuditEntry(
          id: i,
          action: i.isEven ? 'auth.login_failed' : 'group.created',
          targetType: i.isEven ? 'user' : 'group',
          actorUserId: i.isEven ? null : 1,
          targetId: i.isEven ? null : i,
          createdAt: DateTime.utc(2026, 9, 10 + i),
        ),
      );
    }
    api = clientFor(server);
  });

  tearDown(CherryPick.closeRootScope);

  test('records come back newest first', () async {
    final page = await api.audit.query();

    expect(page.items.map((e) => e.id), [5, 4, 3, 2, 1]);
  });

  test('a filter narrows, and an unknown action is refused', () async {
    final failures = await api.audit.query(action: 'auth.login_failed');
    expect(failures.items.map((e) => e.id), [4, 2]);

    await expectLater(
      api.audit.query(action: 'group.renamed'),
      throwsA(
        isA<DioException>().having(
          (e) => e.response?.statusCode,
          'statusCode',
          400,
        ),
      ),
    );
  });

  test('a time range narrows to the records inside it', () async {
    final page = await api.audit.query(
      from: DateTime.utc(2026, 9, 13).toIso8601String(),
      to: DateTime.utc(2026, 9, 14).toIso8601String(),
    );

    expect(page.items.map((e) => e.id), [4, 3]);
  });

  test('pages walk backwards without overlapping', () async {
    final first = await api.audit.query(limit: 2);
    final second = await api.audit.query(limit: 2, cursor: first.nextCursor);
    final third = await api.audit.query(limit: 2, cursor: second.nextCursor);

    final seen = [
      ...first.items,
      ...second.items,
      ...third.items,
    ].map((e) => e.id).toList();

    expect(seen, [5, 4, 3, 2, 1]);
    expect(third.nextCursor, isNull);
  });

  test('the retention policy comes back with the page', () async {
    expect((await api.audit.query()).auditRetentionDays, isNull);

    server
      ..auditRetentionDays = 365
      ..authEventRetentionDays = 30;

    final page = await api.audit.query();
    expect(page.auditRetentionDays, 365);
    expect(page.authEventRetentionDays, 30);
  });

  test('a caller who is not a global admin is refused', () async {
    // The only way to arrange this: no endpoint in this stage creates a second
    // user, so the account's own roles are what a test varies.
    final owner = MockServer(
      roles: const [
        {'role': 'owner', 'scope_type': 'group', 'scope_id': 1},
      ],
    );
    owner.auditEntries.add(mockAuditEntry(id: 1, action: 'group.created'));

    await expectLater(
      clientFor(owner).audit.query(),
      throwsA(
        isA<DioException>().having(
          (e) => e.response?.statusCode,
          'statusCode',
          403,
        ),
      ),
    );
  });
}
