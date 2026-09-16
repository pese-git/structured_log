import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_client/shared/api/api_client.dart';
import 'package:structured_log_admin_client/shared/auth/token_storage.dart';
import 'package:structured_log_admin_client/shared/config/app_config.dart';

import 'fake_adapter.dart';

const _config = AppConfig(baseUrl: 'https://logs.example.test');

/// A body copied from a running server, not invented here.
///
/// The same discipline as `resources_api_test.dart`, for the same reason: the
/// defect that file exists because of was a list endpoint declared as returning
/// a bare array, which no test noticed because no test put the server's actual
/// body through this layer.
///
/// This one carries the shapes worth getting wrong on a first pass — a nested
/// `metadata` object rather than a string, a record with no actor, and the two
/// retention fields the page carries alongside its items.
const _page = {
  'items': [
    {
      'id': 42,
      'actor_user_id': 1,
      'action': 'project.quota_updated',
      'target_type': 'project',
      'target_id': 7,
      'metadata': {
        'before': {'retention_days': 30, 'max_entries': null},
        'after': {'retention_days': 30, 'max_entries': 1000},
      },
      'created_at': '2026-09-16T08:14:02.000Z',
    },
    {
      'id': 41,
      'actor_user_id': null,
      'action': 'auth.login_failed',
      'target_type': 'user',
      'target_id': null,
      'metadata': {
        'reason': 'unknown_user',
        'unknown_user': true,
        'client_ip': '203.0.113.9',
        'user_agent': null,
      },
      'created_at': '2026-09-16T08:13:51.000Z',
    },
  ],
  'next_cursor': '41',
  'audit_retention_days': 365,
  'auth_event_retention_days': 30,
};

/// What a server with retention switched off answers — the default, and the
/// one an operator sees until they turn it on.
const _pageWithoutRetention = {
  'items': <Object?>[],
  'next_cursor': null,
  'audit_retention_days': null,
  'auth_event_retention_days': null,
};

void main() {
  ApiClient clientFor(FakeAdapter adapter) => ApiClient(
    config: _config,
    storage: InMemoryTokenStorage(),
    adapter: adapter,
  );

  test('a page of records parses, metadata and all', () async {
    final client = clientFor(
      FakeAdapter((_) => const FakeReply(200, body: _page)),
    );

    final page = await client.audit.query();

    expect(page.items, hasLength(2));
    expect(page.nextCursor, '41');
    expect(page.auditRetentionDays, 365);
    expect(page.authEventRetentionDays, 30);

    final quota = page.items.first;
    expect(quota.action, 'project.quota_updated');
    expect(quota.actorUserId, 1);
    expect(quota.targetId, 7);
    expect(quota.metadata['after'], {
      'retention_days': 30,
      'max_entries': 1000,
    }, reason: 'a nested object, kept as one — not flattened, not stringified');
    expect(quota.createdAt, DateTime.utc(2026, 9, 16, 8, 14, 2));
  });

  test('a record with nobody behind it keeps its nulls', () async {
    // The screen renders this as "an attempt under an account that does not
    // exist". A DTO that refused the null, or defaulted it to zero, would make
    // that impossible to tell from an attempt by user 0.
    final client = clientFor(
      FakeAdapter((_) => const FakeReply(200, body: _page)),
    );

    final failure = (await client.audit.query()).items.last;

    expect(failure.actorUserId, isNull);
    expect(failure.targetId, isNull);
    expect(failure.metadata['unknown_user'], isTrue);
    expect(failure.metadata['user_agent'], isNull);
  });

  test(
    'retention switched off arrives as null, not as a missing field',
    () async {
      final client = clientFor(
        FakeAdapter((_) => const FakeReply(200, body: _pageWithoutRetention)),
      );

      final page = await client.audit.query();

      expect(page.items, isEmpty);
      expect(page.nextCursor, isNull);
      expect(page.auditRetentionDays, isNull);
      expect(page.authEventRetentionDays, isNull);
    },
  );

  test(
    'every filter reaches the wire under the name the server reads',
    () async {
      // The names are a contract with a server that ignores what it does not
      // recognise: a misspelled parameter would widen the query silently rather
      // than fail, and the reader would be shown more than they asked for.
      final adapter = FakeAdapter((_) => const FakeReply(200, body: _page));

      await clientFor(adapter).audit.query(
        actorUserId: 1,
        action: 'group.created',
        targetType: 'group',
        targetId: 7,
        from: '2026-09-01T00:00:00.000Z',
        to: '2026-09-16T00:00:00.000Z',
        cursor: '99',
        limit: 25,
      );

      expect(adapter.requests.single.uri.queryParameters, {
        'actor_user_id': '1',
        'action': 'group.created',
        'target_type': 'group',
        'target_id': '7',
        'from': '2026-09-01T00:00:00.000Z',
        'to': '2026-09-16T00:00:00.000Z',
        'cursor': '99',
        'limit': '25',
      });
    },
  );

  test('an unset filter is left off rather than sent empty', () async {
    final adapter = FakeAdapter((_) => const FakeReply(200, body: _page));

    await clientFor(adapter).audit.query(action: 'group.created');

    expect(
      adapter.requests.single.uri.queryParameters,
      {'action': 'group.created'},
      reason:
          'an empty `target_type=` is a filter the server would try to match, '
          'not the absence of one',
    );
  });
}
