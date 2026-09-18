import 'package:cherrypick/cherrypick.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:structured_log_admin_client/app/app.dart';
import 'package:structured_log_admin_client/shared/auth/session_controller.dart';
import 'package:structured_log_admin_client/shared/auth/token_storage.dart';
import 'package:structured_log_admin_client/shared/config/app_config.dart';
import 'package:structured_log_admin_client/shared/di/app_module.dart';
import 'package:structured_log_admin_client/shared/logging/setup.dart';
import 'package:structured_log_admin_client/testing/mock_server.dart';

/// One operator's path through the app, performed rather than simulated.
///
/// The difference from `test/integration/user_flow_test.dart` is the binding.
/// `flutter test` runs on `TestWidgetsFlutterBinding`, which stands in for two
/// things a user is: it registers a fake text input, so `enterText` writes
/// into a field nobody focused, and it answers 400 to every `HttpClient`
/// request. `IntegrationTestWidgetsFlutterBinding` does neither
/// (`registerTestTextInput => false`, `overrideHttpClient => false`): the app
/// runs in a browser with its own renderer and its own keyboard, and text
/// arrives through the same platform channel a keystroke uses.
///
/// So every action below is the action itself. A field is focused by being
/// tapped, at its own coordinates; characters arrive one at a time, so
/// anything listening to `onChanged` sees what a typist produces rather than
/// one paste; a button is pressed where it is drawn, which means a button that
/// has drifted off-screen or under another widget fails the test instead of
/// being found by name anyway.
///
/// The network stays mocked, and deliberately: the contract with the real
/// server is `packages/e2e`'s job, and this run is about the operator.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late MockServer server;
  late InMemoryTokenStorage storage;
  late String secretKey;

  const temporaryPassword = 'issued-by-the-administrator';
  const operatorPassword = 'chosen-by-the-operator';

  setUpAll(() {
    server = MockServer(username: 'admin', password: temporaryPassword)
      ..mustChangePassword = true;
    storage = InMemoryTokenStorage();
  });

  tearDown(CherryPick.closeRootScope);

  /// Opens the app the way `main()` does, on a mocked network.
  Future<void> openApp(WidgetTester tester) async {
    // The artboards are 1160–1440 wide, and the shell trades its labelled
    // navigation for a rail below 900. A window narrower than that would be a
    // different test.
    //
    // Inside the test, not in `setUpAll`: this binding asserts that a test is
    // running, and the assertion failure there leaves the driver waiting for a
    // result that never comes rather than reporting anything.
    await binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => binding.setSurfaceSize(null));

    final session = SessionController();
    final scope = openAppScope(
      config: const AppConfig(baseUrl: 'https://logs.example.test'),
      logger: configureClientLogging(),
      tokenStorage: storage,
      httpAdapter: server,
      onSessionExpired: session.expire,
      onPasswordChangeRequired: session.passwordChangeRequired,
    );
    await tester.pumpWidget(AdminApp(scope: scope, session: session));
    await tester.pumpAndSettle();
  }

  /// Unmounts the app inside the test, so a live subscription a screen opened
  /// is cancelled while the tester can still run the frames that finish it.
  Future<void> closeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('a fresh deployment asks for a new password before it opens', (
    tester,
  ) async {
    await openApp(tester);
    await _waitFor(tester, find.text('Вход в систему'));

    await _type(tester, find.byType(TextBox).first, 'admin');
    await _type(tester, find.byType(TextBox).last, temporaryPassword);
    await _press(tester, find.text('Войти'));

    await _waitFor(
      tester,
      find.text('Смените пароль'),
      reason:
          'the sign-in succeeded — it is the first request behind it that '
          'ran into the gate, and the gate chooses the screen',
    );
    expect(find.text('Группы'), findsNothing);
    // The username is read off the access token asynchronously
    // (`ChangePasswordCubit`'s own lookup), so it can lag a frame or two
    // behind the gate's static copy above it — worth a wait of its own,
    // not a bare `expect` right after the screen appears.
    await _waitFor(
      tester,
      find.textContaining('Вошли как admin'),
      reason: 'the name comes out of the access token the sign-in returned',
    );

    final fields = find.byType(TextBox);
    await _type(tester, fields.at(0), temporaryPassword);
    await _type(tester, fields.at(1), operatorPassword);
    await _type(tester, fields.at(2), operatorPassword);
    await _press(tester, find.text('Сменить пароль и продолжить'));

    await _waitFor(tester, find.text('Пароль изменён'));
    await _press(tester, find.text('Перейти в приложение'));

    // The change retires the access token in hand but not the refresh token,
    // so the request that was refused a moment ago is renewed by the
    // interceptor rather than sending the operator back to sign in.
    await _waitFor(tester, find.text('Групп пока нет'));
    expect(server.password, operatorPassword);
    await closeApp(tester);
  });

  testWidgets('the operator sets up a group, a project and a key', (
    tester,
  ) async {
    await openApp(tester);
    expect(
      find.text('Вход в систему'),
      findsNothing,
      reason: 'the session held between visits',
    );

    await _press(tester, find.text('Создать группу'));
    await _type(tester, find.byType(TextBox).first, 'payments');
    await _press(tester, find.text('Создать группу').last);
    await _waitFor(tester, find.text('payments'));

    await _press(tester, find.text('Открыть').first);
    await _waitFor(tester, find.text('Проектов пока нет'));

    await _press(tester, find.text('Проект'));
    await _type(tester, find.byType(TextBox).first, 'checkout');
    await _press(tester, find.text('Создать проект'));
    await _waitFor(tester, find.text('checkout'));

    await _press(tester, find.text('Открыть').first);
    await _waitFor(tester, find.text('Секретных ключей пока нет'));

    await _press(tester, find.text('Создать ключ'));
    await _type(tester, find.byType(TextBox).first, 'ci');
    await _press(tester, find.text('Создать ключ').last);

    await _waitFor(tester, find.text('Ключ создан'));
    // Read off the screen rather than out of the response: this dialog is the
    // only place the value exists, so taking it from here is both how the rest
    // of the flow gets a key and the proof that what is shown is usable.
    secretKey = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .data!;
    expect(secretKey, startsWith('slk_'));

    await _press(tester, find.text('Я сохранил(а) ключ — закрыть'));
    await _waitFor(tester, find.text('ci'));
    await _waitFor(tester, find.text('Активен'));
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

    await openApp(tester);
    await _press(tester, find.text('Поиск логов'));
    await _waitFor(tester, find.text('Выберите область'));

    await _press(tester, find.text('checkout'));
    await _waitFor(tester, find.text('webhook_delivery_failed'));
    await _waitFor(tester, find.text('ERR'));

    await _press(tester, find.text('webhook_delivery_failed'));
    await _waitFor(tester, find.text('СТАНДАРТНЫЕ ПОЛЯ'));
    expect(find.text('request_id'), findsOneWidget);
    expect(find.text('attempt'), findsOneWidget);
    expect(find.text('status_code'), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('a search typed into the filter bar narrows the feed', (
    tester,
  ) async {
    server.acceptEntry(
      mockLogEntry(
        id: 2,
        projectId: server.projects.single['id'] as int,
        event: 'payment_authorized',
        logger: 'checkout.service',
      ),
      secret: secretKey,
    );

    await openApp(tester);
    await _press(tester, find.text('Поиск логов'));
    await _press(tester, find.text('checkout'));
    await _waitFor(tester, find.text('payment_authorized'));
    await _waitFor(tester, find.text('webhook_delivery_failed'));

    // Typed, then submitted — the search is applied on the button rather than
    // on every keystroke, because each change is a query plus a fresh
    // subscription. The gap between the two is the assertion below.
    await _type(tester, find.byType(TextBox).first, 'payment');
    expect(
      find.text('webhook_delivery_failed'),
      findsOneWidget,
      reason: 'typing alone changes nothing; the request is what filters',
    );

    await _press(tester, find.text('Найти'));
    await _waitFor(tester, find.text('payment_authorized'));
    await _waitForGone(tester, find.text('webhook_delivery_failed'));
    await closeApp(tester);
  });

  testWidgets('an entry that arrives while the feed is open simply appears', (
    tester,
  ) async {
    await openApp(tester);
    await _press(tester, find.text('Поиск логов'));
    await _press(tester, find.text('checkout'));
    await _waitFor(tester, find.text('payment_authorized'));

    server.acceptEntry(
      mockLogEntry(
        id: 3,
        projectId: server.projects.single['id'] as int,
        event: 'refund_issued',
        logger: 'checkout.service',
      ),
      secret: secretKey,
    );
    await _waitFor(
      tester,
      find.text('refund_issued'),
      reason: 'no reload: the subscription the screen opened delivered it',
    );
    await _waitFor(tester, find.text('В реальном времени'));
    await closeApp(tester);
  });

  testWidgets('the administrator creates another operator account', (
    tester,
  ) async {
    await openApp(tester);
    await _press(tester, find.text('Пользователи'));
    await _waitFor(tester, find.text('Создать пользователя'));

    await _press(tester, find.text('Создать пользователя'));
    final fields = find.byType(TextBox);
    await _type(tester, fields.at(0), 'operator');
    await _type(tester, fields.at(1), 'issued-by-the-administrator');
    await _type(tester, fields.at(2), 'Operator One');
    await _press(tester, find.text('Создать пользователя').last);

    await _waitFor(tester, find.text('Operator One'));
    await _waitFor(tester, find.text('Временный пароль'));
    await closeApp(tester);
  });

  testWidgets(
    'the administrator grants the operator owner access to the group, '
    'then revokes it',
    (tester) async {
      await openApp(tester);
      // The default destination on a fresh open is the groups list — the one
      // group set up earlier in this file ("payments").
      await _press(tester, find.text('Открыть').first);
      await _waitFor(tester, find.text('Предоставить доступ'));
      await _waitFor(
        tester,
        find.text('Доступа пока никому не выдано'),
        reason: 'nothing has been granted on this group yet',
      );

      await _press(tester, find.text('Предоставить доступ'));
      await _waitFor(tester, find.text('Пользователь'));

      // A name search (`AdminSearchPicker`), not a raw id box — type the
      // username and let the debounce fire. `AdminSearchPicker` itself
      // reopens the suggestions overlay once the search answers (see its
      // doc comment on the `fluent_ui` staleness bug this works around), but
      // that only fires while the field is still focused — and this
      // binding's automated browser window is not the foreground window, so
      // it can lose focus of its own accord during an idle real-time wait
      // like the one the debounce needs. Tapping the field again is enough
      // to pick focus back up; nothing here depends on the tap doing more
      // than that.
      await _type(tester, find.byType(AutoSuggestBox<int>), 'operator');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AutoSuggestBox<int>));
      await tester.pumpAndSettle();
      await _press(tester, find.text('operator').last);

      // Two ComboBox<String> live in this dialog since 13.5 (full version)
      // added the recipient-kind picker above this one — the role picker,
      // this one's target, is the second.
      await _press(tester, find.byType(ComboBox<String>).last);
      await _press(tester, find.text('owner').last);

      await _press(tester, find.text('Предоставить'));
      await _waitFor(
        tester,
        find.text('operator'),
        reason: 'the dialog closes on success and the granted row appears',
      );
      await _waitFor(tester, find.text('owner'));

      await _press(tester, find.text('Отозвать'));
      await _waitFor(tester, find.textContaining('Отозвать доступ у'));
      await _press(tester, find.text('Отозвать').last);

      await _waitFor(tester, find.text('Доступа пока никому не выдано'));
      await _waitForGone(tester, find.text('operator'));
      await closeApp(tester);
    },
  );

  testWidgets('signing out ends the session, and it does not come back', (
    tester,
  ) async {
    await openApp(tester);

    await _press(tester, find.text(server.username));
    await _press(tester, find.text('Выйти'));

    await _waitFor(tester, find.text('Вход в систему'));
    expect(
      find.textContaining('Сессия завершена'),
      findsNothing,
      reason: 'leaving on purpose is not something going wrong',
    );
    expect(await storage.read(), isNull);
    await closeApp(tester);

    await openApp(tester);
    await _waitFor(tester, find.text('Вход в систему'));
    await closeApp(tester);
  });
}

/// Presses a control where it is drawn.
///
/// `warnIfMissed: true` is the default and is left on purpose: a control that
/// has scrolled out of view, or sits under something else, is one a person
/// could not have pressed either, and a test that quietly "taps" it would
/// report a screen nobody can use as working.
Future<void> _press(WidgetTester tester, Finder control) async {
  await _waitFor(tester, control, matcher: findsWidgets);
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  await tester.tap(control);
  await tester.pumpAndSettle();
}

/// Types into a field, having first focused it by tapping it.
///
/// The tap is the part that matters and the part a widget test skips:
/// `enterText` on its own focuses the field through the framework, so a field
/// sitting under another widget, or scrolled out of view, takes text a person
/// could never have given it. Here the pointer lands at the field's own
/// coordinates first, focus is checked, and the text is read back out of the
/// field's state — on this binding the text input is the platform's rather
/// than a mock, so text that failed to arrive would otherwise be a silent
/// no-op instead of a failure.
///
/// The whole value goes in one call rather than a character at a time, and the
/// reason is worth writing down: `AdminSearchField` wraps its `TextBox` in a
/// `ValueListenableBuilder` and grows a clear button the moment the text stops
/// being empty. That rebuild replaces the input connection, so a second
/// keystroke aimed at the connection the first one used lands nowhere and the
/// field stays at one character. A real keyboard re-attaches and a person
/// notices nothing; a test that re-sends the value does not, and would be
/// asserting about its own plumbing rather than about the app.
Future<void> _type(WidgetTester tester, Finder field, String text) async {
  await _waitFor(tester, field, matcher: findsWidgets);
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.pumpAndSettle();

  final editable = find.descendant(
    of: field,
    matching: find.byType(EditableText),
  );
  expect(
    tester.state<EditableTextState>(editable).widget.focusNode.hasFocus,
    isTrue,
    reason: 'the tap did not move focus — what follows would type elsewhere',
  );

  await tester.enterText(field, text);
  await tester.pumpAndSettle();

  expect(
    tester.state<EditableTextState>(editable).textEditingValue.text,
    text,
    reason: 'the field did not take what was typed',
  );
}

/// Waits for the screen to catch up, instead of assuming the frame after an
/// action is the one carrying its result.
///
/// Nothing in a running app is synchronous the way a widget test's fake clock
/// makes it look: a press starts a request, the answer lands some frames
/// later, and a dialog that replaces another does it a frame after that. A
/// deadline in wall-clock time rather than a fixed number of frames, because
/// how long that takes is not something a test should assert on by accident.
Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Matcher? matcher,
  String? reason,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline) && !_matches(finder)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (!_matches(finder)) {
    fail(
      [
        ?reason,
        'gave up waiting for $finder',
        'on screen: ${_visibleText(tester)}',
      ].join('\n'),
    );
  }
  expect(
    finder,
    matcher ?? findsOneWidget,
    // What is on screen instead. A driven app reports a failure as a stack
    // trace in the browser and nothing else, and "found 0 widgets" says
    // nothing about which screen the flow actually ended up on.
    reason: [?reason, 'on screen: ${_visibleText(tester)}'].join('\n'),
  );
}

/// Whether the finder has anything, without throwing when it does not.
///
/// `.first` and `.last` raise `StateError` when the finder they wrap matched
/// nothing, rather than reporting no match — so "is it on screen yet" cannot be
/// asked with `evaluate().isNotEmpty` alone. Asking it that way turned a screen
/// that was merely slow into an immediate failure that never waited at all, and
/// reported it as `Bad state: No element`, which says nothing about what the
/// test was looking for.
bool _matches(Finder finder) {
  try {
    return finder.evaluate().isNotEmpty;
  } on StateError {
    return false;
  }
}

/// Every piece of text the app is currently showing, deduplicated and
/// shortened — enough to recognise the screen from a log.
String _visibleText(WidgetTester tester) {
  final seen = <String>{};
  for (final widget in tester.widgetList<Text>(find.byType(Text))) {
    final data = widget.data;
    if (data == null || data.trim().isEmpty) continue;
    seen.add(data.length > 40 ? '${data.substring(0, 40)}…' : data);
  }
  return seen.join(' | ');
}

/// The other direction: waits for something to leave the screen.
Future<void> _waitForGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline) && finder.evaluate().isNotEmpty) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsNothing);
}
