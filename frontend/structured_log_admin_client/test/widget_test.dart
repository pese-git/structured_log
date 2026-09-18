import 'package:cherrypick/cherrypick.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_client/shared/l10n/locale_controller.dart';
import 'package:structured_log_admin_client/shared/auth/token_pair.dart';
import 'package:structured_log_admin_client/app/app.dart';
import 'package:structured_log_admin_client/shared/api/api_client.dart';
import 'package:structured_log_admin_client/shared/auth/token_storage.dart';
import 'package:structured_log_admin_client/shared/auth/session_controller.dart';
import 'package:structured_log_admin_client/shared/config/app_config.dart';
import 'package:structured_log_admin_client/shared/di/app_module.dart';
import 'package:structured_log_admin_client/shared/logging/setup.dart';

import 'shared/api/fake_adapter.dart';

void main() {
  tearDown(CherryPick.closeRootScope);

  testWidgets('the app boots and puts something on screen', (tester) async {
    final scope = openAppScope(
      config: const AppConfig(baseUrl: 'https://logs.example.test'),
      logger: configureClientLogging(),
      // No keychain in a widget test — that is what the override exists for
      // (design.md decision 20 / Risks).
      tokenStorage: InMemoryTokenStorage(),
    );

    await tester.pumpWidget(
      AdminApp(
        scope: scope,
        session: SessionController(),
        localeController: LocaleController(initial: const Locale('ru')),
      ),
    );
    await tester.pumpAndSettle();

    // With no stored session the shell lands on sign-in.
    expect(find.text('Вход в систему'), findsOneWidget);
  });

  test('the scope wires the data layer as singletons', () {
    final scope = openAppScope(
      config: const AppConfig(baseUrl: 'https://logs.example.test'),
      logger: configureClientLogging(),
      tokenStorage: InMemoryTokenStorage(),
    );

    final client = scope.resolve<ApiClient>();
    expect(
      identical(client, scope.resolve<ApiClient>()),
      isTrue,
      reason: 'a second ApiClient would mean a second set of interceptors',
    );

    final storage = scope.resolve<TokenStorage>();
    expect(identical(storage, scope.resolve<TokenStorage>()), isTrue);
    expect(
      storage,
      isA<InMemoryTokenStorage>(),
      reason: 'the override is what a test and the web build get',
    );

    expect(
      client.dio.options.baseUrl,
      'https://logs.example.test',
      reason: 'the base URL comes from AppConfig, not from a constant',
    );
  });

  testWidgets('the gate the server puts up reaches the screen', (tester) async {
    // The wiring this covers has three steps in three files and no other
    // test touches all three: the interceptor spots `403
    // must_change_password`, the session records it, and `AuthGate` swaps the
    // app for the change-password screen. Each half could be right on its own
    // and still leave a fresh deployment stuck on an error message — which is
    // exactly what it did before section 27.
    final session = SessionController();
    final storage = InMemoryTokenStorage();
    await storage.write(
      const TokenPair(accessToken: 'access', refreshToken: 'refresh'),
    );

    final scope = openAppScope(
      config: const AppConfig(baseUrl: 'https://logs.example.test'),
      logger: configureClientLogging(),
      tokenStorage: storage,
      httpAdapter: FakeAdapter(
        (_) => const FakeReply(
          403,
          body: {'error': 'must_change_password', 'message': 'no'},
        ),
      ),
      onSessionExpired: session.expire,
      onPasswordChangeRequired: session.passwordChangeRequired,
    );

    await tester.pumpWidget(
      AdminApp(
        scope: scope,
        session: session,
        localeController: LocaleController(initial: const Locale('ru')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Смените пароль'), findsOneWidget);
    expect(
      find.text('Группы'),
      findsNothing,
      reason: 'the rest of the app is not reachable from behind the gate',
    );
    expect(find.text('Выйти'), findsOneWidget, reason: 'except the way out');
  });
}
