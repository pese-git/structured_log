import 'package:cherrypick/cherrypick.dart';
import 'package:dio/dio.dart';
// fluent_ui, not flutter/widgets: the latter re-exports dart:ui's TextBox —
// a text geometry rectangle, not a widget — and `find.byType(TextBox)` would
// then compile and match nothing at all.
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_client/app/app.dart';
import 'package:structured_log_admin_client/shared/auth/session_controller.dart';
import 'package:structured_log_admin_client/shared/auth/token_pair.dart';
import 'package:structured_log_admin_client/shared/auth/token_storage.dart';
import 'package:structured_log_admin_client/shared/config/app_config.dart';
import 'package:structured_log_admin_client/shared/di/app_module.dart';
import 'package:structured_log_admin_client/shared/logging/setup.dart';

import '../../shared/api/fake_adapter.dart';

const _config = AppConfig(baseUrl: 'https://logs.example.test');

const _tokens = FakeReply(
  200,
  body: {
    'access_token': 'access-1',
    'refresh_token': 'refresh-1',
    'token_type': 'Bearer',
    'expires_in': 900,
  },
);

/// The whole app over a scripted server, composed the way `main()` composes
/// it — scope, session controller and all — so these exercise the wiring and
/// not a screen in isolation.
({Widget app, SessionController session, InMemoryTokenStorage storage})
_buildApp(
  FakeReply Function(RequestOptions options) handler, {
  TokenPair? storedSession,
  String? baseUrl,
}) {
  final session = SessionController();
  final storage = InMemoryTokenStorage(storedSession);
  final scope = openAppScope(
    config: baseUrl == null ? _config : AppConfig(baseUrl: baseUrl),
    logger: configureClientLogging(),
    tokenStorage: storage,
    httpAdapter: FakeAdapter(handler),
    onSessionExpired: session.expire,
  );
  return (
    app: AdminApp(scope: scope, session: session),
    session: session,
    storage: storage,
  );
}

Future<void> _signIn(
  WidgetTester tester, {
  String username = 'root',
  String password = 'correct',
}) async {
  await tester.enterText(find.byType(TextBox).first, username);
  await tester.enterText(find.byType(TextBox).last, password);
  await tester.tap(find.text('Войти'));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(CherryPick.closeRootScope);

  /// The artboard is 1160 wide. At the default 800 the form sits past the
  /// right edge, and a tap on a button that is off-screen warns and does
  /// nothing rather than failing outright.
  void useArtboardSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1160, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('a correct sign-in stores the pair and leaves the login screen', (
    tester,
  ) async {
    useArtboardSurface(tester);
    final built = _buildApp((_) => _tokens);

    await tester.pumpWidget(built.app);
    await tester.pumpAndSettle();
    expect(find.text('Вход в систему'), findsOneWidget);

    await _signIn(tester);

    expect(
      await built.storage.read(),
      const TokenPair(accessToken: 'access-1', refreshToken: 'refresh-1'),
    );
    expect(built.session.signedIn, isTrue);
    expect(
      find.text('Вход в систему'),
      findsNothing,
      reason: 'the shell moves on without asking again',
    );
  });

  testWidgets('wrong credentials keep the screen and store nothing', (
    tester,
  ) async {
    useArtboardSurface(tester);
    final built = _buildApp(
      (_) => const FakeReply(400, body: {'error': 'invalid_grant'}),
    );

    await tester.pumpWidget(built.app);
    await tester.pumpAndSettle();
    await _signIn(tester, password: 'wrong');

    expect(find.text('Вход в систему'), findsOneWidget);
    expect(
      find.textContaining('Неверное имя пользователя или пароль'),
      findsOneWidget,
    );
    expect(await built.storage.read(), isNull);
  });

  testWidgets('an unverified email is explained on its own terms', (
    tester,
  ) async {
    useArtboardSurface(tester);
    final built = _buildApp(
      (_) => const FakeReply(
        400,
        body: {'error': 'invalid_grant', 'reason': 'email_not_verified'},
      ),
    );

    await tester.pumpWidget(built.app);
    await tester.pumpAndSettle();
    await _signIn(tester);

    expect(find.textContaining('Email этой учётной записи'), findsOneWidget);
    expect(
      find.textContaining('Неверное имя пользователя'),
      findsNothing,
      reason: 'a verified-email problem is not a credentials problem',
    );
  });

  testWidgets('a rate limit shows the wait and disables the button', (
    tester,
  ) async {
    useArtboardSurface(tester);
    final built = _buildApp(
      (_) => const FakeReply(
        429,
        body: {'error': 'too_many_requests'},
        headers: {
          'retry-after': ['43'],
        },
      ),
    );

    await tester.pumpWidget(built.app);
    await tester.pumpAndSettle();
    await _signIn(tester);

    expect(find.textContaining('Слишком много попыток'), findsOneWidget);
    expect(find.textContaining('00:43'), findsWidgets);
    expect(
      find.textContaining('Неверное имя пользователя'),
      findsNothing,
      reason: 'a limiter is not a credentials error',
    );
    // The countdown is live; leaving it running would fail the test with a
    // pending timer.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a stored session skips the login screen', (tester) async {
    final built = _buildApp(
      (_) => _tokens,
      storedSession: const TokenPair(
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
      ),
    );

    await tester.pumpWidget(built.app);
    await tester.pumpAndSettle();

    expect(find.text('Вход в систему'), findsNothing);
    expect(built.session.signedIn, isTrue);
  });

  testWidgets(
    'an unrenewable session returns to the login screen and says so',
    (tester) async {
      final built = _buildApp(
        (_) => _tokens,
        storedSession: const TokenPair(
          accessToken: 'access-1',
          refreshToken: 'refresh-1',
        ),
      );

      await tester.pumpWidget(built.app);
      await tester.pumpAndSettle();
      expect(find.text('Вход в систему'), findsNothing);

      // What the interceptor does once a refresh is refused.
      built.session.expire();
      await tester.pumpAndSettle();

      expect(find.text('Вход в систему'), findsOneWidget);
      expect(find.textContaining('Сессия завершена'), findsOneWidget);
    },
  );

  testWidgets('an unreachable server is explained in plain language', (
    tester,
  ) async {
    useArtboardSurface(tester);
    final built = _buildApp(
      (_) => throw DioException.connectionError(
        requestOptions: RequestOptions(path: '/v1/auth/token'),
        // What dio actually produces in a browser: a paragraph about
        // XMLHttpRequest and CORS preflights.
        reason:
            'The XMLHttpRequest onError callback was called. This '
            'typically indicates an error on the network layer...',
      ),
    );

    await tester.pumpWidget(built.app);
    await tester.pumpAndSettle();
    await _signIn(tester);

    expect(
      find.textContaining('Не удалось связаться с сервером'),
      findsOneWidget,
    );
    expect(
      find.textContaining('XMLHttpRequest'),
      findsNothing,
      reason: 'the client library\'s diagnostic belongs in the log',
    );
  });

  testWidgets('the server the window points at is shown', (tester) async {
    final built = _buildApp((_) => _tokens);

    await tester.pumpWidget(built.app);
    await tester.pumpAndSettle();

    expect(find.textContaining('logs.example.test'), findsOneWidget);
  });

  testWidgets('an empty base URL leaves out the server line entirely', (
    tester,
  ) async {
    useArtboardSurface(tester);
    // What the bundled deployment builds with: the client is served beside the
    // API and addresses it relative to the page. A label with nothing after it
    // says less than no label, which is what this pins.
    final built = _buildApp((_) => _tokens, baseUrl: '');

    await tester.pumpWidget(built.app);
    await tester.pumpAndSettle();

    expect(find.textContaining('Сервер:'), findsNothing);
  });
}
