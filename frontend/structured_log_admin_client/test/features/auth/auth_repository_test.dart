import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_admin_client/features/auth/domain/auth_failure.dart';
import 'package:structured_log_admin_client/features/auth/infrastructure/auth_repository_impl.dart';
import 'package:structured_log_admin_client/shared/api/api_client.dart';
import 'package:structured_log_admin_client/shared/auth/token_pair.dart';
import 'package:structured_log_admin_client/shared/auth/token_storage.dart';
import 'package:structured_log_admin_client/shared/config/app_config.dart';

import '../../shared/api/fake_adapter.dart';

const _config = AppConfig(baseUrl: 'https://logs.example.test');

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

  test(
    'hasSession reports what is stored, without asking the server',
    () async {
      final adapter = FakeAdapter((_) => const FakeReply(200));
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

      expect(await repository.hasSession(), isFalse);
      await storage.write(const TokenPair(accessToken: 'a', refreshToken: 'r'));
      expect(await repository.hasSession(), isTrue);
      expect(adapter.requests, isEmpty);
    },
  );
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
      );
      expect(result.getLeft().toNullable(), isA<UnexpectedAuthFailure>());
    });
  });
}

/// Stands in for a connection that never happened.
class SocketLikeError implements Exception {
  const SocketLikeError();
}
