import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_admin_client/features/auth/domain/auth_failure.dart';
import 'package:structured_log_admin_client/features/auth/infrastructure/auth_repository_impl.dart';
import 'package:structured_log_admin_client/shared/api/api_client.dart';
import 'package:structured_log_admin_client/shared/auth/session_store.dart';
import 'package:structured_log_admin_client/shared/auth/token_pair.dart';
import 'package:structured_log_admin_client/shared/auth/token_storage.dart';
import 'package:structured_log_admin_client/shared/config/app_config.dart';

import '../../shared/api/fake_adapter.dart';

const _config = AppConfig(baseUrl: 'https://logs.example.test');

/// A secret store that already holds a token, as a shared one does for a tab
/// that was not the one to sign in.
class _HeldSecret implements SecretStore {
  String? value;

  _HeldSecret(this.value);

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String? next) async => value = next;
}

/// The token endpoint answers in the RFC 6749 shape, not the API's general
/// envelope — which is exactly why this repository maps its own errors.
FakeReply _rfcError(String code, {String? reason, int status = 400}) =>
    FakeReply(
      status,
      body: {
        'error': code,
        'error_description': 'whatever the server says',
        'reason': ?reason,
      },
    );

(AuthRepositoryImpl, InMemoryTokenStorage, FakeAdapter) _repository(
  FakeReply Function(RequestOptions options) handler,
) {
  final adapter = FakeAdapter(handler);
  final storage = InMemoryTokenStorage();
  final client = ApiClient(config: _config, storage: storage, adapter: adapter);
  return (
    AuthRepositoryImpl(
      api: client.auth,
      storage: storage,
      logger: getLogger('test'),
    ),
    storage,
    adapter,
  );
}

void main() {
  test('a successful sign-in stores the pair', () async {
    final (repository, storage, _) = _repository(
      (_) => const FakeReply(
        200,
        body: {
          'access_token': 'access-1',
          'refresh_token': 'refresh-1',
          'token_type': 'Bearer',
          'expires_in': 900,
        },
      ),
    );

    final result = await repository.signIn(
      username: 'root',
      password: 'correct',
    );

    expect(result.isRight(), isTrue);
    expect(
      await storage.read(),
      const TokenPair(accessToken: 'access-1', refreshToken: 'refresh-1'),
    );
  });

  test('invalid_grant without a reason is wrong credentials', () async {
    final (repository, storage, _) = _repository(
      (_) => _rfcError('invalid_grant'),
    );

    final result = await repository.signIn(username: 'root', password: 'no');

    expect(
      result.getLeft().toNullable(),
      const AuthFailure.invalidCredentials(),
    );
    expect(
      await storage.read(),
      isNull,
      reason: 'a refused sign-in stores nothing',
    );
  });

  test('invalid_grant with email_not_verified is its own outcome', () async {
    final (repository, _, _) = _repository(
      (_) => _rfcError('invalid_grant', reason: 'email_not_verified'),
    );

    final result = await repository.signIn(username: 'root', password: 'ok');

    expect(
      result.getLeft().toNullable(),
      const AuthFailure.emailNotVerified(),
      reason: 'the screen offers to resend rather than saying "wrong password"',
    );
  });

  test('429 carries the wait from the header', () async {
    final (repository, _, _) = _repository(
      (_) => const FakeReply(
        429,
        body: {'error': 'too_many_requests'},
        headers: {
          'retry-after': ['43'],
        },
      ),
    );

    final result = await repository.signIn(username: 'root', password: 'ok');

    expect(
      result.getLeft().toNullable(),
      const AuthFailure.rateLimited(Duration(seconds: 43)),
    );
  });

  test(
    'an unreachable server is a network failure, not bad credentials',
    () async {
      final adapter = FakeAdapter((_) => throw const SocketLikeError());
      final storage = InMemoryTokenStorage();
      final repository = AuthRepositoryImpl(
        api: ApiClient(
          config: _config,
          storage: storage,
          adapter: adapter,
        ).auth,
        storage: storage,
        logger: getLogger('test'),
      );

      final result = await repository.signIn(username: 'root', password: 'ok');

      expect(result.getLeft().toNullable(), isA<NetworkAuthFailure>());
    },
  );

  test('signing out revokes the token and clears the session', () async {
    final requests = <RequestOptions>[];
    final adapter = FakeAdapter((options) {
      requests.add(options);
      return const FakeReply(200);
    });
    final storage = InMemoryTokenStorage(
      const TokenPair(accessToken: 'access-1', refreshToken: 'refresh-1'),
    );
    final repository = AuthRepositoryImpl(
      api: ApiClient(config: _config, storage: storage, adapter: adapter).auth,
      storage: storage,
      logger: getLogger('test'),
    );

    await repository.signOut();

    expect(requests.single.method, 'DELETE');
    expect(await storage.read(), isNull);
  });

  test(
    'signing out clears the session even when the server is unreachable',
    () async {
      final storage = InMemoryTokenStorage(
        const TokenPair(accessToken: 'access-1', refreshToken: 'refresh-1'),
      );
      final repository = AuthRepositoryImpl(
        api: ApiClient(
          config: _config,
          storage: storage,
          adapter: FakeAdapter((_) => throw const SocketLikeError()),
        ).auth,
        storage: storage,
        logger: getLogger('test'),
      );

      // Must not throw: leaving the user signed in because the network was down
      // is the worse failure (`specs/admin-client-auth`).
      await repository.signOut();

      expect(await storage.read(), isNull);
    },
  );

  group('restoreSession', () {
    test('an access token already in this tab costs no request', () async {
      final (repository, storage, adapter) = _repository(
        (_) => const FakeReply(200),
      );
      await storage.write(const TokenPair(accessToken: 'a', refreshToken: 'r'));

      expect(await repository.restoreSession(), isTrue);
      expect(
        adapter.requests,
        isEmpty,
        reason:
            'reloading a page must not cost a renewal — that is what '
            'keeps the reload off the cross-tab race entirely',
      );
    });

    test('a new tab asks the server, because only it knows', () async {
      // The refresh token is in an `HttpOnly` cookie, so this page cannot
      // read it and cannot tell a live session from none. Trying is the only
      // way to find out.
      final (repository, storage, adapter) = _repository(
        (options) => FakeReply(
          200,
          body: {
            'access_token': 'fresh-access',
            'refresh_token': 'fresh-refresh',
            'token_type': 'Bearer',
            'expires_in': 900,
            'refresh_token_cookie_set': true,
          },
        ),
      );

      expect(await repository.restoreSession(), isTrue);
      expect(adapter.requests.single.path, '/v1/auth/token');
      expect(
        (adapter.requests.single.data as Map)['grant_type'],
        'refresh_token',
      );
      final held = await storage.read();
      expect(held!.accessToken, 'fresh-access');
      expect(
        held.refreshToken,
        'fresh-refresh',
        reason:
            'the server set a cookie, but this host keeps none — so the copy '
            'from the body is the only credential there is. Letting go of it '
            'is what a browser does (`sessionFrom`)',
      );
    });

    test('a cookie-less tab presents the token it holds', () async {
      // The secret store is shared between tabs, the per-tab one is not — so
      // a new tab in a deployment without the cookie starts with a refresh
      // token and no access token, and must use the one it has rather than
      // renewing with nothing.
      final adapter = FakeAdapter(
        (_) => const FakeReply(
          200,
          body: {
            'access_token': 'fresh-access',
            'refresh_token': 'fresh-refresh',
            'token_type': 'Bearer',
            'expires_in': 900,
          },
        ),
      );
      final storage = SplitTokenStorage(
        accessStore: InMemorySessionStore(),
        refreshStore: _HeldSecret('held-refresh'),
      );
      final repository = AuthRepositoryImpl(
        api: ApiClient(
          config: _config,
          storage: storage,
          adapter: adapter,
        ).auth,
        storage: storage,
        logger: getLogger('test'),
      );

      expect(await repository.restoreSession(), isTrue);
      expect(
        (adapter.requests.single.data as Map)['refresh_token'],
        'held-refresh',
      );
    });

    test(
      'no session at all lands on the login screen, not on an error',
      () async {
        final (repository, _, _) = _repository(
          (_) => _rfcError('invalid_grant'),
        );

        expect(await repository.restoreSession(), isFalse);
      },
    );

    test('an unreachable server is no session either', () async {
      final (repository, _, _) = _repository(
        (_) => throw DioException.connectionError(
          requestOptions: RequestOptions(),
          reason: 'offline',
        ),
      );

      expect(await repository.restoreSession(), isFalse);
    });
  });
  group('changePassword and the other sessions', () {
    /// The body as it went on the wire — retrofit hands dio the DTO's
    /// `toJson()`, so this is the JSON the server would parse.
    Future<Map<String, Object?>> bodyOf(
      Future<void> Function(AuthRepositoryImpl repository) call, {
      TokenPair? held,
    }) async {
      late Map<String, Object?> sent;
      final (repository, storage, _) = _repository((options) {
        sent = Map<String, Object?>.from(options.data as Map);
        return const FakeReply(200, body: {});
      });
      if (held != null) await storage.write(held);
      await call(repository);
      return sent;
    }

    test('asks for the other sessions to end, naming its own token', () async {
      final sent = await bodyOf(
        held: const TokenPair(accessToken: 'a-1', refreshToken: 'r-1'),
        (repository) => repository.changePassword(
          currentPassword: 'old-password',
          newPassword: 'new-password-1',
          keepOtherSessions: false,
        ),
      );

      expect(sent['keep_other_sessions'], isFalse);
      expect(
        sent['current_refresh_token'],
        'r-1',
        reason:
            'the server cannot otherwise tell which session is asking, and '
            'would sign this one out along with the rest',
      );
    });

    test('passes the opt-out through when the reader ticked it', () async {
      final sent = await bodyOf(
        held: const TokenPair(accessToken: 'a-1', refreshToken: 'r-1'),
        (repository) => repository.changePassword(
          currentPassword: 'old-password',
          newPassword: 'new-password-1',
          keepOtherSessions: true,
        ),
      );

      expect(sent['keep_other_sessions'], isTrue);
    });

    test(
      'omits the token rather than sending null when none is held',
      () async {
        final sent = await bodyOf(
          (repository) => repository.changePassword(
            currentPassword: 'old-password',
            newPassword: 'new-password-1',
            keepOtherSessions: false,
          ),
        );

        expect(sent.containsKey('current_refresh_token'), isFalse);
      },
    );

    test('never sends either password under the new field names', () async {
      final sent = await bodyOf(
        held: const TokenPair(accessToken: 'a-1', refreshToken: 'r-1'),
        (repository) => repository.changePassword(
          currentPassword: 'old-password',
          newPassword: 'new-password-1',
          keepOtherSessions: false,
        ),
      );

      expect(sent['current_password'], 'old-password');
      expect(sent['new_password'], 'new-password-1');
      expect(sent['current_refresh_token'], isNot('old-password'));
    });
  });

  group('changePassword refusals', () {
    FakeReply envelope(String error, {Map<String, Object?>? details}) =>
        FakeReply(
          400,
          body: {
            'error': error,
            'message': 'English, for a developer.',
            'details': ?details,
          },
        );

    test('a too-short new password keeps the server\'s limit', () async {
      final (repository, _, _) = _repository(
        (_) => envelope(
          'invalid_request',
          details: {
            'field': 'new_password',
            'reason': 'too_short',
            'min_length': 8,
          },
        ),
      );

      final result = await repository.changePassword(
        currentPassword: 'old-password',
        newPassword: 'short',
        keepOtherSessions: false,
      );

      final failure = result.getLeft().toNullable();
      expect(failure, isA<PasswordRejectedAuthFailure>());
      expect((failure as PasswordRejectedAuthFailure).details['min_length'], 8);
    });

    test('a too-long one is a password refusal too', () async {
      final (repository, _, _) = _repository(
        (_) => envelope(
          'invalid_request',
          details: {'reason': 'too_long', 'max_bytes': 72},
        ),
      );
      final result = await repository.changePassword(
        currentPassword: 'old-password',
        newPassword: 'x' * 80,
        keepOtherSessions: false,
      );
      expect(result.getLeft().toNullable(), isA<PasswordRejectedAuthFailure>());
    });

    test('another 400 is still unexpected, not a password refusal', () async {
      final (repository, _, _) = _repository(
        (_) => envelope(
          'invalid_request',
          details: {'field': 'current_password', 'reason': 'required'},
        ),
      );
      final result = await repository.changePassword(
        currentPassword: '',
        newPassword: 'long-enough-1',
        keepOtherSessions: false,
      );
      expect(result.getLeft().toNullable(), isA<UnexpectedAuthFailure>());
    });
  });
}

/// Stands in for a connection that never happened.
class SocketLikeError implements Exception {
  const SocketLikeError();
}
