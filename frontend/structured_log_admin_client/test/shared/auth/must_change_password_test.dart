import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_client/shared/api/api_client.dart';
import 'package:structured_log_admin_client/shared/api/dto/auth_dto.dart';
import 'package:structured_log_admin_client/shared/auth/access_token_claims.dart';
import 'package:structured_log_admin_client/shared/auth/session_controller.dart';
import 'package:structured_log_admin_client/shared/auth/token_pair.dart';
import 'package:structured_log_admin_client/shared/auth/token_storage.dart';
import 'package:structured_log_admin_client/shared/config/app_config.dart';

import '../api/fake_adapter.dart';

const _config = AppConfig(baseUrl: 'https://logs.example.test');

/// The gate the server puts in front of an account that still carries the
/// password an administrator gave it.
const _gate = FakeReply(
  403,
  body: {
    'error': 'must_change_password',
    'message': 'This account must change its password before continuing.',
  },
);

/// What `POST /v1/auth/change-password` answers to a wrong current password:
/// 401, but `invalid_grant` rather than the `unauthorized` a stale token
/// gets.
const _wrongPassword = FakeReply(
  401,
  body: {'error': 'invalid_grant', 'message': 'Current password is incorrect.'},
);

void main() {
  group('the must_change_password gate', () {
    test('is reported from whatever request ran into it', () async {
      var raised = 0;
      final client = ApiClient(
        config: _config,
        storage: InMemoryTokenStorage(),
        onPasswordChangeRequired: () => raised++,
        adapter: FakeAdapter((_) => _gate),
      );

      await expectLater(client.groups.list(), throwsA(isA<Object>()));

      expect(raised, 1);
    });

    test('does not end the session — the tokens are still good', () async {
      var expired = 0;
      final storage = InMemoryTokenStorage();
      await storage.write(
        const TokenPair(accessToken: 'access', refreshToken: 'refresh'),
      );
      final client = ApiClient(
        config: _config,
        storage: storage,
        onSessionExpired: () => expired++,
        adapter: FakeAdapter((_) => _gate),
      );

      await expectLater(client.groups.list(), throwsA(isA<Object>()));

      expect(expired, 0);
      expect(await storage.read(), isNotNull);
    });
  });

  test('a wrong current password is not mistaken for a stale token', () async {
    final storage = InMemoryTokenStorage();
    await storage.write(
      const TokenPair(accessToken: 'access', refreshToken: 'refresh'),
    );
    final adapter = FakeAdapter((_) => _wrongPassword);
    final client = ApiClient(
      config: _config,
      storage: storage,
      adapter: adapter,
    );

    await expectLater(
      client.auth.changePassword(
        const ChangePasswordRequestDto(
          currentPassword: 'wrong',
          newPassword: 'chosen',
          keepOtherSessions: false,
        ),
      ),
      throwsA(isA<Object>()),
    );

    expect(
      adapter.requests.map((r) => r.path),
      ['/v1/auth/change-password'],
      reason:
          'no refresh and no replay: the server would count the replay as '
          'a second failed attempt against the per-user rate limiter, and a '
          'handful of typos would lock the account out',
    );
  });

  group('the session state', () {
    test('the gate is a third state, not a kind of signed out', () {
      final session = SessionController(signedIn: true);

      session.passwordChangeRequired();

      expect(session.mustChangePassword, isTrue);
      expect(session.signedIn, isTrue);
    });

    test('changing the password lifts it', () {
      final session = SessionController(signedIn: true)
        ..passwordChangeRequired();

      session.passwordChanged();

      expect(session.mustChangePassword, isFalse);
      expect(session.signedIn, isTrue);
    });

    test('signing out from behind the gate leaves it behind', () {
      final session = SessionController(signedIn: true)
        ..passwordChangeRequired();

      session.signedOutNow();

      expect(session.signedIn, isFalse);
      expect(session.mustChangePassword, isFalse);
    });
  });

  group('the username in the access token', () {
    test('is read for display', () {
      // {"preferred_username":"admin","tv":0}
      const token =
          'eyJhbGciOiJIUzI1NiJ9.'
          'eyJwcmVmZXJyZWRfdXNlcm5hbWUiOiJhZG1pbiIsInR2IjowfQ.'
          'signature-not-checked';

      expect(usernameFromAccessToken(token), 'admin');
    });

    test('a token this client cannot read costs only the name', () {
      expect(usernameFromAccessToken('not-a-token'), isNull);
      expect(usernameFromAccessToken('a.b.c'), isNull);
    });
  });
}
