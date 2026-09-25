import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_admin_client/features/auth/application/change_password.dart';
import 'package:structured_log_admin_client/features/auth/infrastructure/auth_repository_impl.dart';
import 'package:structured_log_admin_client/features/resources/domain/resources_repository.dart';
import 'package:structured_log_admin_client/features/resources/infrastructure/resources_repository_impl.dart';
import 'package:structured_log_admin_client/shared/api/api_client.dart';
import 'package:structured_log_admin_client/shared/api/dto/auth_dto.dart';
import 'package:structured_log_admin_client/shared/auth/token_pair.dart';
import 'package:structured_log_admin_client/shared/auth/token_storage.dart';
import 'package:structured_log_admin_client/shared/config/app_config.dart';

import 'harness.dart';

/// Changing your own password on a session whose access token has already
/// aged out.
///
/// The one operation documented to leave the caller signed in
/// (`log-server-forced-password-change`), and the one whose *body* names a
/// credential: `current_refresh_token` tells the server which session to
/// spare while it sweeps the rest. That makes it the one request a token
/// renewal can spoil — the body is built from what the session holds, a 401
/// on the way out rotates the refresh token, and a replay of the original
/// body then asks the server to spare a token that was just revoked while it
/// sweeps the live one. The reader comes back to the sign-in screen from the
/// operation that is supposed to be survivable.
///
/// It lives here rather than only in the client's own suite because it is a
/// seam: the client's mock agrees with the server about the sweep by hand,
/// and the rotation that breaks it is the server's, not the mock's. Found by
/// driving a real deployment on 2026-09-25; the client's tests were green,
/// because none of them had a session old enough.
void main() {
  late ServerProcess server;

  late ApiClient readerApi;
  late InMemoryTokenStorage readerStorage;
  late ResourcesRepository readerResources;
  late ChangePassword readerChangePassword;

  /// Raised by the reader's interceptor if the session is ever declared over.
  var readerSessionsEnded = 0;

  late ApiClient otherApi;
  late InMemoryTokenStorage otherStorage;

  const chosenPassword = 'chosen-by-the-operator';
  const changedElsewhere = 'changed-on-the-other-device';
  const changedHere = 'changed-back-on-this-one';

  setUpAll(() async {
    StructlogConfiguration.configure(
      sinks: [LogSink(name: 'silent', output: (_, _) {})],
    );
    server = await ServerProcess.start();

    readerStorage = InMemoryTokenStorage();
    readerApi = ApiClient(
      config: AppConfig(baseUrl: server.baseUrl),
      storage: readerStorage,
      onSessionExpired: () => readerSessionsEnded++,
    );
    readerResources = ResourcesRepositoryImpl(readerApi);
    readerChangePassword = ChangePassword(
      AuthRepositoryImpl(
        api: readerApi.auth,
        storage: readerStorage,
        logger: getLogger('e2e'),
      ),
    );

    otherStorage = InMemoryTokenStorage();
    otherApi = ApiClient(
      config: AppConfig(baseUrl: server.baseUrl),
      storage: otherStorage,
    );
  });

  tearDownAll(() async {
    await server.stop();
    StructlogConfiguration.reset();
  });

  Future<void> signIn(
    ApiClient api,
    InMemoryTokenStorage storage,
    String password,
  ) async {
    final tokens = await api.auth.signIn('password', 'admin', password);
    await storage.write(
      TokenPair(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      ),
    );
  }

  test('an access token that aged out does not cost the session that changes '
      'the password', () async {
    // Out of the temporary password the server generated, the way the forced
    // screen does it.
    await signIn(readerApi, readerStorage, server.bootstrapPassword);
    await readerApi.auth.changePassword(
      ChangePasswordRequestDto(
        currentPassword: server.bootstrapPassword,
        newPassword: chosenPassword,
        keepOtherSessions: false,
        currentRefreshToken: (await readerStorage.read())!.refreshToken,
      ),
    );
    // Settles the reader onto a fresh access token, which is what the first
    // screen after the forced change does.
    expect((await readerResources.groups()).isRight(), isTrue);

    // Ageing the session without waiting out the fifteen-minute lifetime:
    // another device changes the password, and `incrementTokenVersion` runs
    // whether or not the sweep does. `keep_other_sessions` keeps this
    // reader's refresh token alive while retiring its access token — exactly
    // the state a session reaches on its own after sitting idle.
    await signIn(otherApi, otherStorage, chosenPassword);
    await otherApi.auth.changePassword(
      ChangePasswordRequestDto(
        currentPassword: chosenPassword,
        newPassword: changedElsewhere,
        keepOtherSessions: true,
        currentRefreshToken: (await otherStorage.read())!.refreshToken,
      ),
    );

    final held = (await readerStorage.read())!.refreshToken;

    // The reader now changes the password from its own settings screen. The
    // request goes out on a token the server has stopped accepting, so the
    // renewal happens underneath this call.
    final result = await readerChangePassword(
      currentPassword: changedElsewhere,
      newPassword: changedHere,
      keepOtherSessions: false,
    );
    expect(result.isRight(), isTrue);

    expect(
      (await readerStorage.read())!.refreshToken,
      isNot(held),
      reason:
          'the renewal this test is about has to have happened — without a '
          'rotation underneath the change there is nothing here to break',
    );

    // The proof the reader would recognise: the next screen, which needs a
    // renewal of its own now that the change retired every access token.
    expect(
      (await readerResources.groups()).isRight(),
      isTrue,
      reason:
          'the replayed body has to name the token the renewal produced. '
          'Naming the one it spent spares nothing and sweeps this session',
    );
    expect(readerSessionsEnded, 0);

    // And the sweep still did its job: the other device is out.
    await expectLater(
      otherApi.auth.refresh(
        'refresh_token',
        (await otherStorage.read())!.refreshToken,
      ),
      throwsA(anything),
      reason: 'only the caller is spared, which is the point of the sweep',
    );
  });
}
