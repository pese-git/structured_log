import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_client/shared/api/api_client.dart';
import 'package:structured_log_admin_client/shared/api/api_failure.dart';
import 'package:structured_log_admin_client/shared/api/failure_mapper.dart';
import 'package:structured_log_admin_client/shared/auth/token_pair.dart';
import 'package:structured_log_admin_client/shared/auth/token_storage.dart';
import 'package:structured_log_admin_client/shared/config/app_config.dart';

import 'fake_adapter.dart';

const _config = AppConfig(baseUrl: 'https://logs.example.test');

/// What the server actually answers to a collection endpoint.
///
/// A bare `[]` stood here until 2026-09-15, and that is what let
/// `GroupsApi.list()` be declared as returning a bare list: the fixture agreed
/// with the mistake, so the suite was green while the real client reported
/// every scope lookup as "the server is unreachable". The shape belongs to
/// `resources_api_test.dart` now; here it only has to be right.
const _emptyCollection = {'items': <Object?>[]};

const _session = TokenPair(accessToken: 'access-1', refreshToken: 'refresh-1');

Map<String, Object?> _tokenBody(String access, String refresh) => {
  'access_token': access,
  'refresh_token': refresh,
  'token_type': 'Bearer',
  'expires_in': 900,
};

void main() {
  test('attaches the access token to an ordinary request', () async {
    final adapter = FakeAdapter(
      (options) => const FakeReply(200, body: _emptyCollection),
    );
    final client = ApiClient(
      config: _config,
      storage: InMemoryTokenStorage(_session),
      adapter: adapter,
    );

    await client.groups.list();

    expect(adapter.requests.single.headers['Authorization'], 'Bearer access-1');
  });

  test('sends no token when there is no session', () async {
    final adapter = FakeAdapter(
      (options) => const FakeReply(200, body: _emptyCollection),
    );
    final client = ApiClient(
      config: _config,
      storage: InMemoryTokenStorage(),
      adapter: adapter,
    );

    await client.groups.list();

    expect(
      adapter.requests.single.headers.containsKey('Authorization'),
      isFalse,
    );
  });

  test('a 401 is refreshed and the original request replayed once', () async {
    final storage = InMemoryTokenStorage(_session);
    var groupsCalls = 0;

    final adapter = FakeAdapter((options) {
      if (options.path == '/v1/auth/token') {
        return FakeReply(200, body: _tokenBody('access-2', 'refresh-2'));
      }
      groupsCalls++;
      // Refused while the old token is presented, accepted once it is new.
      return options.headers['Authorization'] == 'Bearer access-2'
          ? const FakeReply(200, body: _emptyCollection)
          : const FakeReply(401, body: {'error': 'invalid_token'});
    });

    final client = ApiClient(
      config: _config,
      storage: storage,
      adapter: adapter,
    );

    final groups = await client.groups.list();

    expect(groups.items, isEmpty);
    expect(groupsCalls, 2, reason: 'the original request, then one replay');
    expect(
      await storage.read(),
      const TokenPair(accessToken: 'access-2', refreshToken: 'refresh-2'),
      reason: 'the renewed pair is persisted, not just used once',
    );
  });

  test('a refused refresh ends the session', () async {
    final storage = InMemoryTokenStorage(_session);
    var expired = 0;

    final adapter = FakeAdapter((options) {
      if (options.path == '/v1/auth/token') {
        return const FakeReply(400, body: {'error': 'invalid_grant'});
      }
      return const FakeReply(401, body: {'error': 'invalid_token'});
    });

    final client = ApiClient(
      config: _config,
      storage: storage,
      adapter: adapter,
      onSessionExpired: () => expired++,
    );

    await expectLater(client.groups.list(), throwsA(isA<DioException>()));
    expect(await storage.read(), isNull, reason: 'tokens are cleared');
    expect(expired, 1);
  });

  test(
    'a replay that is refused again does not refresh a second time',
    () async {
      var refreshes = 0;
      final adapter = FakeAdapter((options) {
        if (options.path == '/v1/auth/token') {
          refreshes++;
          return FakeReply(200, body: _tokenBody('access-2', 'refresh-2'));
        }
        // Always 401, even with the new token: the refusal is about this
        // request, not the session.
        return const FakeReply(401, body: {'error': 'insufficient_scope'});
      });

      final client = ApiClient(
        config: _config,
        storage: InMemoryTokenStorage(_session),
        adapter: adapter,
      );

      await expectLater(client.groups.list(), throwsA(isA<DioException>()));
      expect(refreshes, 1, reason: 'exactly one renewal per original request');
    },
  );

  test('a refused sign-in is not treated as an expired session', () async {
    var expired = 0;
    final adapter = FakeAdapter(
      (options) => const FakeReply(400, body: {'error': 'invalid_grant'}),
    );

    final client = ApiClient(
      config: _config,
      storage: InMemoryTokenStorage(),
      adapter: adapter,
      onSessionExpired: () => expired++,
    );

    await expectLater(
      client.auth.signIn('password', 'root', 'wrong'),
      throwsA(isA<DioException>()),
    );
    expect(adapter.requests, hasLength(1), reason: 'no refresh was attempted');
    expect(expired, 0);
  });

  test('a 429 is handed to the caller rather than retried', () async {
    var expired = 0;
    final adapter = FakeAdapter(
      (options) => const FakeReply(
        429,
        body: {'error': 'too_many_requests'},
        headers: {
          'retry-after': ['43'],
        },
      ),
    );

    final client = ApiClient(
      config: _config,
      storage: InMemoryTokenStorage(_session),
      adapter: adapter,
      onSessionExpired: () => expired++,
    );

    final refusal = await client.groups.list().then<DioException?>(
      (_) => null,
      onError: (Object error) => error as DioException,
    );

    expect(
      adapter.requests,
      hasLength(1),
      reason:
          'the limiter counts attempts per subject, so a retry the caller did '
          'not ask for spends their next one and extends the wait they are '
          'already serving (`specs/admin-client-auth`)',
    );
    expect(expired, 0, reason: 'being throttled is not a session ending');

    // And it reaches the screen as a wait rather than as something generic:
    // the failure carries how long, out of `Retry-After`.
    final failure = mapDioException(refusal!);
    expect(failure, isA<RateLimitedFailure>());
    expect(
      (failure as RateLimitedFailure).retryAfter,
      const Duration(seconds: 43),
    );
  });

  test('a 429 from the token endpoint is not turned into a refresh', () async {
    var expired = 0;
    final adapter = FakeAdapter(
      (options) => const FakeReply(429, body: {'error': 'too_many_requests'}),
    );

    final client = ApiClient(
      config: _config,
      storage: InMemoryTokenStorage(_session),
      adapter: adapter,
      onSessionExpired: () => expired++,
    );

    await expectLater(
      client.auth.signIn('password', 'root', 'correct'),
      throwsA(isA<DioException>()),
    );

    // The token endpoint is exempt by path, and this is the case that shows
    // why it has to be: a throttled sign-in answered by spending the refresh
    // token would turn one refused attempt into two.
    expect(adapter.requests, hasLength(1));
    expect(expired, 0);
  });

  test('parallel 401s share a single refresh', () async {
    var refreshes = 0;
    final adapter = FakeAdapter((options) {
      if (options.path == '/v1/auth/token') {
        refreshes++;
        return FakeReply(200, body: _tokenBody('access-2', 'refresh-2'));
      }
      return options.headers['Authorization'] == 'Bearer access-2'
          ? const FakeReply(200, body: _emptyCollection)
          : const FakeReply(401, body: {'error': 'invalid_token'});
    });

    final client = ApiClient(
      config: _config,
      storage: InMemoryTokenStorage(_session),
      adapter: adapter,
    );

    await Future.wait([
      client.groups.list(),
      client.groups.list(),
      client.groups.list(),
    ]);

    // Without single-flight each request would spend the refresh token, and
    // on a server that rotates them the later ones would present a token that
    // had just been revoked.
    expect(refreshes, 1);
  });
}
