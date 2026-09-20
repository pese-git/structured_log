import 'package:cherrypick/cherrypick.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';
import 'package:structured_log_admin_client/testing/mock_server.dart';

/// User management, driven through the screens and answered over the wire —
/// the users counterpart of `resources_integration_test.dart`, for the same
/// reason: a fake repository can agree with the screen about a wire shape
/// neither of them gets right, and only a mock speaking the server's actual
/// body catches that.
void main() {
  late MockServer server;

  setUp(() {
    server = MockServer();
    server.users.add({
      'id': 5,
      'username': 'bob',
      'display_name': null,
      'email': null,
      'email_verified_at': null,
      'must_change_password': true,
      'is_active': true,
      'deleted_at': null,
      'is_primary_admin': false,
      'created_at': '2026-09-10T00:00:00.000Z',
    });
  });

  tearDown(CherryPick.closeRootScope);

  RecordedRequest lastRequest(String method, String path) => server.requests
      .lastWhere((request) => request.method == method && request.path == path);

  testWidgets('the user page is read out of the server\'s own cursor '
      'envelope', (tester) async {
    await pumpApp(tester, server, signedIn: true);
    await openUsers(tester);

    // Twice: the row shows the username both as its monospaced identifier
    // and, absent a display name, as its title.
    expect(find.text('bob'), findsWidgets);
    expect(find.text('Пользователей пока нет'), findsNothing);
    await closeApp(tester);
  });

  testWidgets('a non-admin is not offered the section at all', (tester) async {
    final server = MockServer(
      roles: [
        {'role': 'user', 'scope_type': 'project', 'scope_id': 1},
      ],
    );
    await pumpApp(tester, server, signedIn: true);

    expect(find.text('Пользователи'), findsNothing);
    await closeApp(tester);
  });

  testWidgets('a created account is prepended and sent without an email '
      'field', (tester) async {
    await pumpApp(tester, server, signedIn: true);
    await openUsers(tester);

    await tester.tap(find.text('Создать пользователя').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextBox).at(0), 'newbie');
    await tester.enterText(find.byType(TextBox).at(1), 'temp-123');
    await tester.tap(find.text('Создать пользователя').last);
    await tester.pumpAndSettle();

    final sent = lastRequest('POST', '/v1/users').json;
    expect(sent, {'username': 'newbie', 'password': 'temp-123'});
    expect(sent.containsKey('email'), isFalse);
    expect(find.text('newbie'), findsWidgets);
    await closeApp(tester);
  });

  testWidgets('a taken username is explained without closing the dialog', (
    tester,
  ) async {
    await pumpApp(tester, server, signedIn: true);
    await openUsers(tester);

    await tester.tap(find.text('Создать пользователя').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextBox).at(0), 'bob');
    await tester.enterText(find.byType(TextBox).at(1), 'temp-1234');
    await tester.tap(find.text('Создать пользователя').last);
    await tester.pumpAndSettle();

    expect(
      find.text('Такое имя пользователя уже занято. Выберите другое.'),
      findsOneWidget,
    );
    await closeApp(tester);
  });

  testWidgets('a password that is too short is explained in the dialog', (
    tester,
  ) async {
    await pumpApp(tester, server, signedIn: true);
    await openUsers(tester);

    await tester.tap(find.text('Создать пользователя').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextBox).at(0), 'newbie');
    await tester.enterText(find.byType(TextBox).at(1), 'short');
    await tester.tap(find.text('Создать пользователя').last);
    await tester.pumpAndSettle();

    // In the reader's language and with the limit, not the server's English
    // sentence — and the dialog stays open to be corrected.
    expect(
      find.text('Пароль должен быть не короче 8 символов.'),
      findsOneWidget,
    );
    expect(find.text('Новый пользователь'), findsOneWidget);

    await tester.enterText(find.byType(TextBox).at(1), 'long-enough-1');
    await tester.tap(find.text('Создать пользователя').last);
    await tester.pumpAndSettle();
    expect(find.text('Новый пользователь'), findsNothing);
    // Now it exists: the refused attempt did not create it, the second did.
    expect(find.text('newbie'), findsWidgets);
    await closeApp(tester);
  });

  testWidgets('a password too long for bcrypt is explained as well', (
    tester,
  ) async {
    await pumpApp(tester, server, signedIn: true);
    await openUsers(tester);

    await tester.tap(find.text('Создать пользователя').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextBox).at(0), 'newbie');
    // Forty Cyrillic letters: short in characters, 80 bytes.
    await tester.enterText(find.byType(TextBox).at(1), 'Ж' * 40);
    await tester.tap(find.text('Создать пользователя').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('не более 72 байт'), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('blocking requires confirmation, unblocking does not', (
    tester,
  ) async {
    await pumpApp(tester, server, signedIn: true);
    await openUsers(tester);

    await tester.tap(find.text('Заблокировать'));
    await tester.pumpAndSettle();
    expect(
      find.text('Заблокировать «bob»?'),
      findsOneWidget,
      reason: 'a destructive action is confirmed before it reaches the wire',
    );
    await tester.tap(find.text('Заблокировать').last);
    await tester.pumpAndSettle();

    expect(lastRequest('POST', '/v1/users/5/block').body, isNull);
    expect(find.text('Заблокирован'), findsOneWidget);

    await tester.tap(find.text('Разблокировать'));
    await tester.pumpAndSettle();

    expect(
      find.text('Заблокирован'),
      findsNothing,
      reason: 'no confirmation needed to undo a block',
    );
    await closeApp(tester);
  });

  testWidgets('the primary administrator cannot be deleted from this '
      'screen', (tester) async {
    server.users.add({
      'id': 1,
      'username': 'root',
      'display_name': null,
      'email': null,
      'email_verified_at': null,
      'must_change_password': false,
      'is_active': true,
      'deleted_at': null,
      'is_primary_admin': true,
      'created_at': '2026-09-01T00:00:00.000Z',
    });
    await pumpApp(tester, server, signedIn: true);
    await openUsers(tester);

    // `bob`'s row offers it, `root`'s does not — one "Удалить" for the one
    // deletable account, not zero and not two.
    expect(find.text('Удалить'), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('a deletion refused as sole_group_owner names the blocking '
      'group', (tester) async {
    server.simulateSoleGroupOwner(5, [
      {'id': 3, 'name': 'checkout-team'},
    ]);
    await pumpApp(tester, server, signedIn: true);
    await openUsers(tester);

    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить').last);
    await tester.pumpAndSettle();

    expect(find.text('Сначала передайте владение'), findsOneWidget);
    expect(find.text('checkout-team'), findsOneWidget);
    expect(
      find.text('bob'),
      findsWidgets,
      reason: 'the refused deletion changed nothing',
    );
    await closeApp(tester);
  });

  testWidgets('a successful deletion removes the row', (tester) async {
    await pumpApp(tester, server, signedIn: true);
    await openUsers(tester);

    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить').last);
    await tester.pumpAndSettle();

    expect(lastRequest('DELETE', '/v1/users/5').method, 'DELETE');
    expect(find.text('bob'), findsNothing);
    await closeApp(tester);
  });

  testWidgets('saving the display name and a new password together reaches the '
      'server in one request and returns to the detail page', (tester) async {
    await pumpApp(tester, server, signedIn: true);
    await openUsers(tester);

    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Изменить'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextBox).at(0), 'Bob Diaz');
    await tester.enterText(find.byType(TextBox).at(1), 'new-temp-pw');
    await tester.tap(find.text('Сохранить изменения'));
    await tester.pumpAndSettle();

    expect(lastRequest('PATCH', '/v1/users/5').json, {
      'display_name': 'Bob Diaz',
      'password': 'new-temp-pw',
    });
    expect(
      find.text('Изменить учётную запись'),
      findsNothing,
      reason: 'a successful save returns to the detail page it came from',
    );
    expect(find.text('Bob Diaz'), findsWidgets);
    await closeApp(tester);
  });

  testWidgets('granting a global role sends no scope_id', (tester) async {
    await pumpApp(tester, server, signedIn: true);
    await openUsers(tester);

    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Выдать роль').last);
    await tester.pumpAndSettle();

    final sent = lastRequest('POST', '/v1/role-assignments').json;
    expect(sent, {
      'subject_type': 'user',
      'subject_id': 5,
      'role': 'user',
      'scope_type': 'global',
    });
    // The page shows no one-shot banner — the grant reloads the list above
    // the form, and the new row is the proof it succeeded.
    expect(find.text('вся система'), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('granting a role scoped to a group sends its id', (tester) async {
    server.groups.add({
      'id': 3,
      'name': 'checkout-team',
      'created_at': '2026-09-10T00:00:00.000Z',
    });
    await pumpApp(tester, server, signedIn: true);
    await openUsers(tester);

    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();

    // The scope-type picker is the second `ComboBox<String>` on the page —
    // the role picker is the first.
    await tester.tap(find.byType(ComboBox<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('group').last);
    await tester.pumpAndSettle();

    // The scope field is a name search (`AdminSearchPicker`), not a raw id
    // box: type a name, let the debounce fire, and pick the match from the
    // overlay it opens.
    await tester.enterText(find.byType(TextBox).last, 'check');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.text('checkout-team').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Выдать роль').last);
    await tester.pumpAndSettle();

    final sent = lastRequest('POST', '/v1/role-assignments').json;
    expect(sent, {
      'subject_type': 'user',
      'subject_id': 5,
      'role': 'user',
      'scope_type': 'group',
      'scope_id': 3,
    });
    await closeApp(tester);
  });

  testWidgets('the group picker resets when scope type changes away and back', (
    tester,
  ) async {
    server.groups.add({
      'id': 3,
      'name': 'checkout-team',
      'created_at': '2026-09-10T00:00:00.000Z',
    });
    server.projects.add({
      'id': 9,
      'group_id': 3,
      'name': 'checkout-api',
      'retention_days': 30,
      'max_entries': null,
      'max_bytes': null,
      'is_blocked': false,
      'created_at': '2026-09-10T00:00:00.000Z',
    });
    await pumpApp(tester, server, signedIn: true);
    await openUsers(tester);

    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ComboBox<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('group').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextBox).last, 'checkout-team');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.text('checkout-team').last);
    await tester.pumpAndSettle();

    // Switching to project must not silently grant on the group id typed
    // a moment ago for a different kind of scope.
    await tester.tap(find.byType(ComboBox<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('project').last);
    await tester.pumpAndSettle();

    expect(
      find.text('checkout-team'),
      findsNothing,
      reason: 'a fresh project picker carries none of the group text',
    );

    await tester.enterText(find.byType(TextBox).last, 'checkout-api');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.text('checkout-api').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Выдать роль').last);
    await tester.pumpAndSettle();

    final sent = lastRequest('POST', '/v1/role-assignments').json;
    expect(sent['scope_type'], 'project');
    expect(sent['scope_id'], 9);
    await closeApp(tester);
  });

  testWidgets('the detail page lists existing grants, and revoking one '
      'reaches the server', (tester) async {
    server.roleAssignments.add({
      'id': 4,
      'subject_type': 'user',
      'subject_id': 5,
      'role': 'owner',
      'scope_type': 'global',
      'scope_id': null,
      'created_at': '2026-09-10T00:00:00.000Z',
    });
    await pumpApp(tester, server, signedIn: true);
    await openUsers(tester);

    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();

    expect(find.text('owner'), findsOneWidget);
    expect(find.text('вся система'), findsOneWidget);

    await tester.tap(find.text('Отозвать'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отозвать').last);
    await tester.pumpAndSettle();

    expect(lastRequest('DELETE', '/v1/role-assignments/4'), isNotNull);
    expect(find.text('owner'), findsNothing);
    expect(find.text('Ролей пока не выдано.'), findsOneWidget);
    await closeApp(tester);
  });
}
