import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_client/features/users/presentation/user_dialogs.dart';
import 'package:structured_log_admin_client/shared/api/dto/user_dto.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

/// The same invariant `dialog_layout_test.dart` checks for the resources
/// dialogs: `ContentDialog` hands its content a **loose** `Flexible`, so a
/// bare `Column` takes the whole window unless it is wrapped in a
/// `SingleChildScrollView` — both dialogs here are.
void main() {
  Size boxOf(WidgetTester tester) => tester.getSize(
    find
        .descendant(
          of: find.byType(ContentDialog),
          matching: find.byType(Container),
        )
        .first,
  );

  Future<void> show(
    WidgetTester tester,
    Widget dialog, {
    Size window = const Size(1440, 900),
  }) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      FluentApp(
        theme: AdminTheme.light(),
        home: ScaffoldPage(content: Center(child: dialog)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the create dialog is as tall as its three fields', (
    tester,
  ) async {
    await show(
      tester,
      CreateUserDialog(onCreate: (_, _, _) {}, onCancel: () {}),
    );

    final height = boxOf(tester).height;
    expect(
      height,
      lessThan(900 / 2),
      reason:
          'a dialog holding three fields and a sentence is standing '
          '${height.round()} tall on a 900 window — it is filling the space '
          'rather than measuring its content',
    );
  });

  testWidgets('a window too short for the edit dialog scrolls it instead of '
      'overflowing', (tester) async {
    await show(
      tester,
      EditUserDialog(
        user: UserDto(
          id: 1,
          username: 'bob',
          mustChangePassword: false,
          isActive: true,
          isPrimaryAdmin: false,
          createdAt: DateTime.utc(2026, 9, 16),
        ),
        onSaveDisplayName: (_) {},
        onSetPassword: (_) {},
        onGrantRole: (_) {},
        onClose: () {},
      ),
      // Three sections — profile, password, role grant — comfortably
      // exceed this on purpose: the assertion is that it scrolls rather
      // than overflows, not that it stays small.
      window: const Size(1440, 320),
    );

    expect(
      boxOf(tester).height,
      lessThanOrEqualTo(320),
      reason:
          'the dialog stays inside the window rather than overflowing '
          'it',
    );
    expect(find.text('Профиль'), findsOneWidget);
  });
}
