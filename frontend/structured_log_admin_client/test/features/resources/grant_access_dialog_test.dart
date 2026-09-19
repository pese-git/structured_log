import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_client/features/resources/presentation/resource_dialogs.dart';
import 'package:structured_log_admin_client/shared/api/dto/resource_dto.dart';
import 'package:structured_log_admin_client/shared/api/dto/user_dto.dart';

import '../../support/localized_app.dart';
import 'package:structured_log_admin_client/shared/api/cursor_page.dart';

/// The «Предоставить доступ» dialog's own behaviour (13.5, full version):
/// the recipient can now be a user or a team, and the role choices narrow to
/// what an `owner` may grant unless the caller's own token claims `admin`.
///
/// Team/user search and the role-choice narrowing are exercised here in
/// isolation, against fakes — whether the *values* they narrow by are
/// actually correct (an owner's own group, the caller's real claim) is a
/// question for `resources_test.dart` (the cubit) and
/// `resources_integration_test.dart` (the wire), not this dialog, which only
/// ever does what its parameters tell it to.
void main() {
  UserDto user(int id, String username) => UserDto(
    id: id,
    username: username,
    mustChangePassword: false,
    isActive: true,
    isPrimaryAdmin: false,
    createdAt: DateTime.utc(2026, 2, 14),
  );

  TeamDto team(int id, String name) => TeamDto(
    id: id,
    groupId: 1,
    name: name,
    createdAt: DateTime.utc(2026, 2, 14),
  );

  Future<void> pump(
    WidgetTester tester, {
    bool isGlobalAdmin = false,
    bool moreUsers = false,
    ValueChanged<AccessGrantValues>? onGrant,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      localizedApp(
        home: ScaffoldPage(
          content: Center(
            child: GrantAccessDialog(
              scopeLabel: 'Группа: payments',
              isGlobalAdmin: isGlobalAdmin,
              searchUsers: (query) async =>
                  CursorPage([user(9, 'alice')], moreUsers ? '9' : null),
              searchTeams: (query) async => [team(3, 'on-call')],
              onGrant: onGrant ?? (_) {},
              onCancel: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an owner is not offered the admin role', (tester) async {
    await pump(tester, isGlobalAdmin: false);

    await tester.tap(find.byType(ComboBox<String>).last);
    await tester.pumpAndSettle();

    expect(find.text('admin'), findsNothing);
    expect(find.text('owner'), findsWidgets);
    expect(find.text('user'), findsWidgets);
  });

  testWidgets('a global admin is offered the admin role too', (tester) async {
    await pump(tester, isGlobalAdmin: true);

    await tester.tap(find.byType(ComboBox<String>).last);
    await tester.pumpAndSettle();

    expect(find.text('admin'), findsWidgets);
  });

  testWidgets('the recipient picker defaults to searching users', (
    tester,
  ) async {
    late AccessGrantValues submitted;
    await pump(tester, onGrant: (values) => submitted = values);

    await tester.enterText(find.byType(TextBox), 'ali');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.text('alice').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Предоставить'));
    await tester.pumpAndSettle();

    expect(submitted.subjectType, 'user');
    expect(submitted.subjectId, 9);
  });

  testWidgets('says so when the search matched more than it shows', (
    tester,
  ) async {
    await pump(tester, moreUsers: true);

    await tester.enterText(find.byType(TextBox), 'a');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    // The overlay first opened before the answer; for a frame two rows
    // overflow it, which is `AutoSuggestBox`'s and not what is asserted here.
    tester.takeException();

    expect(find.text('alice'), findsWidgets);
    expect(
      find.text('Показаны первые совпадения — уточните запрос'),
      findsOneWidget,
      reason: 'a silently cut list reads as "these are all the people"',
    );
  });

  testWidgets('a complete result carries no such line', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextBox), 'a');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(
      find.text('Показаны первые совпадения — уточните запрос'),
      findsNothing,
    );
  });

  testWidgets('switching the recipient to a team searches teams and submits '
      'subject_type: team', (tester) async {
    late AccessGrantValues submitted;
    await pump(tester, onGrant: (values) => submitted = values);

    // The recipient-kind picker is the first ComboBox<String> — the role
    // picker is the second.
    await tester.tap(find.byType(ComboBox<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Команда').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextBox), 'on');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.text('on-call').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Предоставить'));
    await tester.pumpAndSettle();

    expect(submitted.subjectType, 'team');
    expect(submitted.subjectId, 3);
  });

  testWidgets('switching recipient kind clears the previous pick — submitting '
      'without choosing again does nothing', (tester) async {
    var grantCalls = 0;
    await pump(tester, onGrant: (_) => grantCalls++);

    await tester.enterText(find.byType(TextBox), 'ali');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.text('alice').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ComboBox<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Команда').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Предоставить'));
    await tester.pumpAndSettle();

    expect(
      grantCalls,
      0,
      reason:
          'the old pick was a user, the field now searches teams, and '
          'submitting the stale id would grant to whoever happens to '
          'hold it',
    );
  });
}
