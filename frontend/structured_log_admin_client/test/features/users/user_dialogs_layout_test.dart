import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_client/features/users/presentation/user_dialogs.dart';

import '../../support/localized_app.dart';

/// The same invariant `dialog_layout_test.dart` checks for the resources
/// dialogs: `ContentDialog` hands its content a **loose** `Flexible`, so a
/// bare `Column` takes the whole window unless it is wrapped in a
/// `SingleChildScrollView` — `CreateUserDialog` is.
///
/// The old `EditUserDialog`'s version of this check moved to
/// `user_detail_page_test.dart`/`edit_user_page_test.dart`: both are now
/// full pages, not dialogs, so they scroll by the same convention
/// `ProjectDetailPage`/`GroupDetailPage` already use — a page-level
/// `SingleChildScrollView`, not `ContentDialog`'s loose `Flexible`.
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
      localizedApp(
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
}
