import 'package:cherrypick/cherrypick.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_client/shared/auth/token_storage.dart';

import 'app_harness.dart';
import 'package:structured_log_admin_client/testing/mock_server.dart';

/// One operator's path through a deployment, in the order they would walk it:
/// a server that has just been started, a temporary password, the first group,
/// the first project, the key an application will ship with, the entries that
/// arrive, and the way out.
///
/// The other integration files ask one question each. This one asks whether
/// the answers join up — whether the screen the gate chooses is reachable from
/// the login form, whether the key the reveal dialog shows is the key entries
/// arrive under, whether a project created on one screen is selectable on
/// another. Every one of those crossings is a place where two correct halves
/// can still fail to meet, and none of them is visible from inside either
/// half.
///
/// The steps run in order and build on each other — one deployment being set
/// up, not five independent cases — and each opens the app again, which is
/// what coming back to it looks like. The session survives between them
/// because the token store does, exactly as a real one would.
void main() {
  late MockServer server;
  late InMemoryTokenStorage storage;

  /// Captured from the reveal dialog in the second step. The only copy: the
  /// server keeps a hash.
  late String secretKey;

  const temporaryPassword = 'issued-by-the-administrator';
  const operatorPassword = 'chosen-by-the-operator';

  setUpAll(() {
    // A server that has just been started for the first time: one account,
    // the password an administrator generated for it, and the gate that
    // password brings with it (design.md decisions 42/49).
    server = MockServer(username: 'admin', password: temporaryPassword)
      ..mustChangePassword = true;
    storage = InMemoryTokenStorage();
  });

  tearDown(CherryPick.closeRootScope);

  testWidgets('a fresh deployment asks for a new password before it opens', (
    tester,
  ) async {
    await pumpApp(tester, server, storage: storage);
    expect(find.text('Вход в систему'), findsOneWidget);

    await signIn(tester, username: 'admin', password: temporaryPassword);

    expect(
      find.text('Смените пароль'),
      findsOneWidget,
      reason:
          'the sign-in succeeded — it is the first request behind it that '
          'ran into the gate, and the gate chooses the screen',
    );
    expect(find.text('Группы'), findsNothing);
    expect(
      find.textContaining('Вошли как admin'),
      findsOneWidget,
      reason:
          'the name comes out of the access token: there is no '
          'GET /v1/users/me in this stage',
    );

    final fields = find.byType(TextBox);
    await tester.enterText(fields.at(0), temporaryPassword);
    await tester.enterText(fields.at(1), operatorPassword);
    await tester.enterText(fields.at(2), operatorPassword);
    await tester.tap(find.text('Сменить пароль и продолжить'));
    await tester.pumpAndSettle();

    expect(find.text('Пароль изменён'), findsOneWidget);
    await tester.tap(find.text('Перейти в приложение'));
    await tester.pumpAndSettle();

    // The change retires the access token in hand but not the refresh token,
    // so the request that was refused a moment ago is renewed by the
    // interceptor rather than sending the operator back to sign in.
    expect(find.text('Групп пока нет'), findsOneWidget);
    expect(find.text('Вход в систему'), findsNothing);
    expect(server.password, operatorPassword);
    await closeApp(tester);
  });

  testWidgets('the operator sets up a group, a project and a key', (
    tester,
  ) async {
    await pumpApp(tester, server, storage: storage);
    expect(
      find.text('Вход в систему'),
      findsNothing,
      reason: 'the session held between visits',
    );

    await tester.tap(find.text('Создать группу'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextBox).first, 'payments');
    await tester.tap(find.text('Создать группу').last);
    await tester.pumpAndSettle();
    expect(find.text('payments'), findsOneWidget);

    await tester.tap(find.text('Открыть').first);
    await tester.pumpAndSettle();
    expect(find.text('Проектов пока нет'), findsOneWidget);

    await tester.tap(find.text('Проект'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextBox).first, 'checkout');
    await tester.tap(find.text('Создать проект'));
    await tester.pumpAndSettle();
    expect(find.text('checkout'), findsOneWidget);

    await tester.tap(find.text('Открыть').first);
    await tester.pumpAndSettle();
    expect(find.text('Секретных ключей пока нет'), findsOneWidget);

    await tester.tap(find.text('Создать ключ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextBox).first, 'ci');
    await tester.tap(find.text('Создать ключ').last);
    await tester.pumpAndSettle();

    expect(find.text('Ключ создан'), findsOneWidget);
    // Read off the screen rather than out of the response: this dialog is the
    // only place the value exists, so taking it from here is both how the
    // rest of the flow gets a key and the proof that what is shown is the
    // usable one.
    secretKey = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .data!;
    expect(secretKey, startsWith('slk_'));

    await tester.tap(find.text('Я сохранил(а) ключ — закрыть'));
    await tester.pumpAndSettle();

    expect(find.text('ci'), findsOneWidget);
    expect(find.text('Активен'), findsOneWidget);
    expect(
      find.text(secretKey),
      findsNothing,
      reason: 'nothing in the app holds the value once the dialog is gone',
    );
    await closeApp(tester);
  });

  testWidgets('an entry the application shipped is on the log screen', (
    tester,
  ) async {
    // Someone else's process, with the key the operator just copied.
    server.acceptEntry(
      mockLogEntry(
        id: 1,
        projectId: server.projects.single['id'] as int,
        event: 'webhook_delivery_failed',
        level: 'error',
        category: 'webhooks',
        logger: 'checkout.service',
        requestId: 'req-1',
        context: const {'attempt': 3, 'status_code': 504},
      ),
      secret: secretKey,
    );

    await pumpApp(tester, server, storage: storage);
    await openLogs(tester);

    expect(
      find.text('Выберите область'),
      findsOneWidget,
      reason: 'nothing is queried before one scope is chosen',
    );
    await tester.tap(find.text('checkout'));
    await tester.pumpAndSettle();

    expect(find.text('webhook_delivery_failed'), findsOneWidget);
    expect(find.text('ERR'), findsOneWidget);
    expect(find.text('Проект: checkout'), findsOneWidget);

    await tester.tap(find.text('webhook_delivery_failed'));
    await tester.pumpAndSettle();

    expect(find.text('СТАНДАРТНЫЕ ПОЛЯ'), findsOneWidget);
    expect(
      find.text('request_id'),
      findsOneWidget,
      reason: 'correlation is a standard field, not part of the free context',
    );
    expect(
      find.text('attempt'),
      findsOneWidget,
      reason:
          'whatever the application bound survives the trip and is shown '
          'beside the fields the server knows about',
    );
    expect(find.text('status_code'), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('an entry that arrives while the feed is open simply appears', (
    tester,
  ) async {
    await pumpApp(tester, server, storage: storage);
    await openLogs(tester);
    await tester.tap(find.text('checkout'));
    await tester.pumpAndSettle();
    expect(find.text('webhook_delivery_failed'), findsOneWidget);

    server.acceptEntry(
      mockLogEntry(
        id: 2,
        projectId: server.projects.single['id'] as int,
        event: 'payment_authorized',
        logger: 'checkout.service',
      ),
      secret: secretKey,
    );
    await tester.pumpAndSettle();

    expect(
      find.text('payment_authorized'),
      findsOneWidget,
      reason: 'no reload: the subscription the screen opened delivered it',
    );
    expect(
      find.text('webhook_delivery_failed'),
      findsOneWidget,
      reason: 'the new entry joins the list rather than replacing it',
    );
    expect(find.text('В реальном времени'), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('signing out ends the session, and it does not come back', (
    tester,
  ) async {
    await pumpApp(tester, server, storage: storage);

    await tester.tap(find.text('Аккаунт'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выйти из аккаунта'));
    await tester.pumpAndSettle();

    expect(find.text('Вход в систему'), findsOneWidget);
    expect(
      find.textContaining('Сессия завершена'),
      findsNothing,
      reason: 'leaving on purpose is not something going wrong',
    );
    expect(await storage.read(), isNull);
    await closeApp(tester);

    await pumpApp(tester, server, storage: storage);
    expect(
      find.text('Вход в систему'),
      findsOneWidget,
      reason: 'there is nothing left to restore',
    );
    await closeApp(tester);
  });
}
