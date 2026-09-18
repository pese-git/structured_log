import 'package:cherrypick/cherrypick.dart';
// fluent_ui, not flutter/widgets: the latter re-exports dart:ui's TextBox — a
// text geometry rectangle, not a widget.
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';
import 'package:structured_log_admin_client/shared/l10n/locale_controller.dart';
import 'package:structured_log_admin_client/testing/mock_server.dart';

/// `AccountSettings.dc.html`, reached as a page rather than the dialog it
/// used to be — profile, password, and self-deletion, over the network
/// layer.
void main() {
  late MockServer server;

  setUp(() {
    server = MockServer();
  });

  tearDown(CherryPick.closeRootScope);

  testWidgets('the profile card shows the username, and "—" for what the '
      'server has nowhere to get', (tester) async {
    await pumpApp(tester, server, signedIn: true);
    await openAccountSettings(tester);

    expect(find.text('root'), findsNWidgets(2));
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Отображаемое имя'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2));
    await closeApp(tester);
  });

  testWidgets('the language card switches the whole app, and remembers it', (
    tester,
  ) async {
    final store = InMemoryLocaleStore('ru');
    final controller = LocaleController(store: store);
    await pumpApp(tester, server, signedIn: true, localeController: controller);
    await openAccountSettings(tester);

    expect(find.text('Язык'), findsOneWidget);
    expect(find.text('Группы'), findsOneWidget);

    await tester.tap(find.byType(ComboBox<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();

    expect(controller.locale, const Locale('en'));
    expect(store.read(), 'en', reason: 'the choice outlives the window');
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Groups'), findsOneWidget);
    expect(find.text('Группы'), findsNothing);
    expect(find.text('Account settings'), findsWidgets);
    await closeApp(tester);
  });

  testWidgets('the password form here does not call the current password '
      'temporary, or send anyone to the administrator', (tester) async {
    await pumpApp(tester, server, signedIn: true);
    await openAccountSettings(tester);

    await tester.tap(find.text('Сменить пароль').last);
    await tester.pumpAndSettle();

    expect(find.text('Текущий пароль'), findsOneWidget);
    expect(find.textContaining('временный'), findsNothing);

    final fields = find.byType(TextBox);
    await tester.enterText(fields.at(0), 'not-the-password');
    await tester.enterText(fields.at(1), 'a-new-password-1');
    await tester.enterText(fields.at(2), 'a-new-password-1');
    await tester.tap(find.text('Сменить пароль').last);
    await tester.pumpAndSettle();

    expect(find.text('Текущий пароль неверен.'), findsOneWidget);
    expect(find.textContaining('администратор'), findsNothing);
    await closeApp(tester);
  });

  testWidgets('deleting the account with the right password signs out', (
    tester,
  ) async {
    await pumpApp(tester, server, signedIn: true);
    await openAccountSettings(tester);

    await tester.tap(find.text('Удалить аккаунт').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextBox), server.password);
    await tester.tap(find.text('Удалить аккаунт').last);
    await tester.pumpAndSettle();

    expect(
      server.requests,
      contains(
        isA<RecordedRequest>()
            .having((r) => r.method, 'method', 'DELETE')
            .having((r) => r.path, 'path', '/v1/users/me'),
      ),
      reason: 'the last request is the sign-out this deletion leads into',
    );
    expect(find.text('Вход в систему'), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('a wrong password is shown inline, and the dialog stays open', (
    tester,
  ) async {
    await pumpApp(tester, server, signedIn: true);
    await openAccountSettings(tester);

    await tester.tap(find.text('Удалить аккаунт').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextBox), 'not-the-password');
    await tester.tap(find.text('Удалить аккаунт').last);
    await tester.pumpAndSettle();

    expect(find.text('Текущий пароль неверен.'), findsOneWidget);
    expect(
      find.text('Удалить аккаунт?'),
      findsOneWidget,
      reason: 'the confirmation dialog is still open, field and all',
    );
    await closeApp(tester);
  });

  testWidgets('409 sole_group_owner opens the conflict dialog naming the '
      'group, without a way to resolve it as a non-admin owner', (
    tester,
  ) async {
    // A group `owner`, not the mock's default global `admin` — a caller
    // with no admin screen to reach `GrantAccessDialog` from, even though
    // `role_assignments_route.dart` would actually let an owner grant a
    // role within their own group.
    final owner = MockServer(
      roles: const [
        {'role': 'owner', 'scope_type': 'group', 'scope_id': 3},
      ],
    );
    owner.simulateMeSoleGroupOwner([
      {'id': 3, 'name': 'checkout-team'},
    ]);
    await pumpApp(tester, owner, signedIn: true);
    await openAccountSettings(tester);

    await tester.tap(find.text('Удалить аккаунт').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextBox), owner.password);
    await tester.tap(find.text('Удалить аккаунт').last);
    await tester.pumpAndSettle();

    expect(find.text('Сначала передайте владение'), findsOneWidget);
    expect(
      find.textContaining('Вы — единственный владелец'),
      findsOneWidget,
      reason: 'it is the reader\'s own account, not "the user"',
    );
    expect(find.text('checkout-team'), findsOneWidget);
    expect(
      find.text('Выдать роль'),
      findsNothing,
      reason:
          'this screen only offers the button when it is sure to work — an '
          '`admin` — not for every caller who technically could grant one',
    );
    await closeApp(tester);
  });
}
