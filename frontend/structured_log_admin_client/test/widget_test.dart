import 'package:cherrypick/cherrypick.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_client/app/app.dart';
import 'package:structured_log_admin_client/shared/api/api_client.dart';
import 'package:structured_log_admin_client/shared/auth/token_storage.dart';
import 'package:structured_log_admin_client/shared/auth/session_controller.dart';
import 'package:structured_log_admin_client/shared/config/app_config.dart';
import 'package:structured_log_admin_client/shared/di/app_module.dart';
import 'package:structured_log_admin_client/shared/logging/setup.dart';

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
      AdminApp(scope: scope, session: SessionController()),
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
}
