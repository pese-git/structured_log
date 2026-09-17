import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_client/shared/api/api_client.dart';
import 'package:structured_log_admin_client/shared/auth/token_storage.dart';
import 'package:structured_log_admin_client/shared/config/app_config.dart';

import 'fake_adapter.dart';

const _config = AppConfig(baseUrl: 'https://logs.example.test');

/// Bodies copied from a running server, not invented here.
///
/// That distinction is the whole point of this file. These endpoints were
/// declared as returning a bare array, the server has always wrapped them in
/// `{"items": [...]}`, and dio's cast of a `Map` to a `List` surfaced as
/// `ApiFailure.network` — the screen said "the server is unreachable" while
/// the server answered 200. Nothing failed, because nothing put a real body
/// through this layer: `logs_api_test.dart` did, and `GET /v1/logs` was
/// therefore the one list endpoint that worked.
const _groupsBody = {
  'items': [
    {'id': 1, 'name': 'payments', 'created_at': '2026-09-15T12:05:45.000Z'},
  ],
};

const _projectsBody = {
  'items': [
    {
      'id': 1,
      'group_id': 1,
      'name': 'checkout',
      'retention_days': 30,
      'max_entries': 1000000,
      'max_bytes': null,
      'is_blocked': false,
      'created_at': '2026-09-15T12:05:45.000Z',
    },
  ],
};

const _teamsBody = {
  'items': [
    {
      'id': 1,
      'group_id': 1,
      'name': 'on-call',
      'created_at': '2026-09-15T12:05:45.000Z',
    },
  ],
};

const _teamMembersBody = {
  'items': [
    {'user_id': 1, 'username': 'alice'},
  ],
};

const _secretKeysBody = {
  'items': [
    {
      'id': 1,
      'project_id': 1,
      'label': 'local',
      'created_at': '2026-09-15T12:05:45.000Z',
      'revoked_at': null,
    },
  ],
};

(ApiClient, FakeAdapter) _client(Map<String, Object?> body) {
  final adapter = FakeAdapter((_) => FakeReply(200, body: body));
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
  test('the group list is read out of the envelope', () async {
    final (client, _) = _client(_groupsBody);

    final groups = await client.groups.list();

    expect(groups.items, hasLength(1));
    expect(groups.items.single.name, 'payments');
  });

  test('the project list is read out of the envelope', () async {
    final (client, adapter) = _client(_projectsBody);

    final projects = await client.projects.list(groupId: 1);

    expect(projects.items.single.name, 'checkout');
    expect(projects.items.single.isBlocked, isFalse);
    expect(
      projects.items.single.maxBytes,
      isNull,
      reason: 'an unset quota is unlimited, not zero',
    );
    expect(adapter.requests.single.queryParameters, {'group_id': 1});
  });

  test('the team list is read out of the envelope', () async {
    final (client, _) = _client(_teamsBody);

    final teams = await client.teams.list(1);

    expect(teams.items.single.name, 'on-call');
    expect(teams.items.single.groupId, 1);
  });

  test('the team member list is read out of the envelope', () async {
    final (client, _) = _client(_teamMembersBody);

    final members = await client.teams.members(1);

    expect(members.items.single.username, 'alice');
  });

  test('the secret key list is read out of the envelope', () async {
    final (client, _) = _client(_secretKeysBody);

    final keys = await client.secretKeys.list(1);

    expect(keys.items.single.label, 'local');
    expect(
      keys.items.single.revokedAt,
      isNull,
      reason: 'a live key has no revocation date',
    );
    expect(
      keys.items.single.secret,
      isNull,
      reason:
          'the listing is metadata only — the secret is shown once, at '
          'creation, and never again',
    );
  });

  test('an empty collection is an empty list, not a missing one', () async {
    final (client, _) = _client(const {'items': <Object?>[]});

    expect((await client.groups.list()).items, isEmpty);
  });
}
