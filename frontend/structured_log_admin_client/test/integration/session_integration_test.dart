import 'package:cherrypick/cherrypick.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';
import 'package:structured_log_admin_client/testing/mock_server.dart';

/// The session, end to end over the network layer: signing in, being renewed,
/// being refused, and the gate that stands in front of everything else.
///
/// What these add over `login_flow_test.dart` is everything behind the login
/// screen. The interceptor's refresh-and-replay, in particular, has no
/// observable effect anywhere else — a screen that is renewed correctly looks
/// exactly like one that never needed renewing — so the only way to see it
/// work is to age a token out under a running app and watch the screen carry
/// on.
void main() {
  late MockServer server;

  setUp(() {
    server = MockServer()
      ..groups.add({
        'id': 7,
        'name': 'acme',
        'created_at': '2026-02-14T00:00:00.000Z',
      });
  });

  tearDown(CherryPick.closeRootScope);

  /// Requests to the token endpoint, by grant.
  Iterable<RecordedRequest> tokenCalls(String grant) => server.requests.where(
    (request) =>
        request.path == '/v1/auth/token' &&
        request.method == 'POST' &&
        request.form['grant_type'] == grant,
  );

  testWidgets('signing in reaches the app, and the pair is what was issued', (
    tester,
  ) async {
    final harness = await pumpApp(tester, server);
    expect(find.text('Вход в систему'), findsOneWidget);

    await signIn(tester);

    final granted = tokenCalls('password').single;
    expect(
      granted.form['username'],
      'root',
      reason: 'RFC 6749: the grant travels as a form body, not as JSON',
    );
    expect(harness.storage.read(), completion(isNotNull));
    expect(find.text('Группы'), findsWidgets);
    await closeApp(tester);
  });

  testWidgets('an aged-out access token is renewed once and the screen never '
      'sees the refusal', (tester) async {
    await pumpApp(tester, server, signedIn: true);
    expect(find.text('acme'), findsOneWidget);

    server.expireAccessTokens();
    await openLogs(tester);

    expect(
      tokenCalls('refresh_token'),
      hasLength(1),
      reason:
          'the scope selector makes two requests, and both 401s share one '
          'refresh — spending the token twice would revoke it on a server '
          'that rotates',
    );
    expect(
      find.text('Выберите область'),
      findsOneWidget,
      reason: 'the replayed requests answered, so the screen loaded',
    );
    expect(find.textContaining('Не удалось'), findsNothing);
    await closeApp(tester);
  });

  testWidgets('a refresh that is refused returns to the login screen and says '
      'so', (tester) async {
    final harness = await pumpApp(tester, server, signedIn: true);

    server
      ..expireAccessTokens()
      ..revokeRefreshTokens();
    await openLogs(tester);

    expect(find.text('Вход в систему'), findsOneWidget);
    expect(find.textContaining('Сессия завершена'), findsOneWidget);
    expect(
      await harness.storage.read(),
      isNull,
      reason: 'a session that cannot be renewed is cleared, not kept',
    );
    await closeApp(tester);
  });

  testWidgets('signing out revokes the refresh token and ends the session '
      'locally', (tester) async {
    final harness = await pumpApp(tester, server, signedIn: true);

    await tester.tap(find.text('Аккаунт'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выйти из аккаунта'));
    await tester.pumpAndSettle();

    expect(
      server.requests.where(
        (request) =>
            request.method == 'DELETE' && request.path == '/v1/auth/token',
      ),
      hasLength(1),
    );
    expect(await harness.storage.read(), isNull);
    expect(find.text('Вход в систему'), findsOneWidget);
    expect(
      find.textContaining('Сессия завершена'),
      findsNothing,
      reason: 'leaving on purpose is not something going wrong',
    );
    await closeApp(tester);
  });

  group('the must_change_password gate', () {
    setUp(() => server.mustChangePassword = true);

    testWidgets('closes the app from whatever request ran into it', (
      tester,
    ) async {
      final harness = await pumpApp(tester, server, signedIn: true);

      expect(
        find.text('Смените пароль'),
        findsOneWidget,
        reason: 'the group list asked, and the 403 chose the screen',
      );
      expect(find.text('acme'), findsNothing);
      expect(
        harness.session.signedIn,
        isTrue,
        reason: 'the session is fine — it is the account that is gated',
      );
      expect(await harness.storage.read(), isNotNull);
      await closeApp(tester);
    });

    testWidgets('is opened by changing the password, without ending the '
        'session', (tester) async {
      final harness = await pumpApp(tester, server, signedIn: true);

      final fields = find.byType(TextBox);
      await tester.enterText(fields.at(0), 'correct');
      await tester.enterText(fields.at(1), 'chosen-by-me');
      await tester.enterText(fields.at(2), 'chosen-by-me');
      await tester.tap(find.text('Сменить пароль и продолжить'));
      await tester.pumpAndSettle();

      expect(find.text('Пароль изменён'), findsOneWidget);
      await tester.tap(find.text('Перейти в приложение'));
      await tester.pumpAndSettle();

      expect(
        find.text('acme'),
        findsOneWidget,
        reason: 'the gated request is made again and answered this time',
      );
      expect(server.password, 'chosen-by-me');
      expect(
        await harness.storage.read(),
        isNotNull,
        reason:
            'the server retires the access token but not the refresh one, so '
            'the session continues through the interceptor',
      );
      expect(tokenCalls('refresh_token'), hasLength(1));
      await closeApp(tester);
    });

    testWidgets('a wrong current password is not mistaken for a stale token', (
      tester,
    ) async {
      await pumpApp(tester, server, signedIn: true);

      final fields = find.byType(TextBox);
      await tester.enterText(fields.at(0), 'not-the-password');
      await tester.enterText(fields.at(1), 'chosen-by-me');
      await tester.enterText(fields.at(2), 'chosen-by-me');
      await tester.tap(find.text('Сменить пароль и продолжить'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Текущий пароль неверен'), findsOneWidget);
      expect(
        tokenCalls('refresh_token'),
        isEmpty,
        reason:
            'the server spells this 401 `invalid_grant`; refreshing would '
            'replay the attempt and spend a second try against the per-user '
            'limiter',
      );
      expect(find.text('Смените пароль'), findsOneWidget);
      await closeApp(tester);
    });
  });
}
