import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_client/features/resources/presentation/resource_dialogs.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

/// A dialog is as tall as what it holds.
///
/// Easy to get wrong and invisible in every other test, because nothing else
/// looks at size: `ContentDialog` hands its content a **loose** `Flexible` —
/// a maximum height, not a tight one — and a `Column` defaults to
/// `MainAxisSize.max`, so a content column written the obvious way takes the
/// whole window. Two of these dialogs did, standing 876 tall on a 900 screen
/// to show a text field and a sentence.
///
/// The measurements below are of the decorated box people actually see.
/// `ContentDialog` itself fills the area it is given and says nothing about
/// how big the dialog looks.
void main() {
  /// The visible box, not the widget that centres it.
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

  Widget nameDialog() => NameDialog(
    title: 'Новая группа',
    fieldLabel: 'Название группы',
    confirmLabel: 'Создать группу',
    description:
        'Проекты создаются внутри группы. Создавать группы может только '
        'администратор.',
    onSubmit: (_) {},
    onCancel: () {},
  );

  Widget revealDialog() => const SecretKeyRevealDialog(
    projectName: 'checkout',
    label: 'ci',
    secret: 'slk_live_1',
    onClose: _nothing,
  );

  Widget teamMembersDialog() => TeamMembersDialog(
    teamName: 'Backend Team',
    groupName: 'Acme Corp',
    members: const [],
    searchUsers: (_) async => const [],
    onAdd: (_) {},
    onRemove: (_) {},
    onClose: _nothing,
  );

  /// Half the window is already far more than any of these need; the point is
  /// to catch a dialog that has stopped measuring itself at all, and a bound
  /// that tracked the current pixel counts would fail on every restyling.
  void expectSizedToContent(WidgetTester tester, Size window) {
    final height = boxOf(tester).height;
    expect(
      height,
      lessThan(window.height / 2),
      reason:
          'a dialog holding a field and a sentence is standing ${height.round()} '
          'tall on a ${window.height.round()} window — it is filling the space '
          'rather than measuring its content',
    );
  }

  testWidgets('the name dialog is as tall as its field and its sentence', (
    tester,
  ) async {
    await show(tester, nameDialog());

    expectSizedToContent(tester, const Size(1440, 900));
  });

  testWidgets('the secret key dialog is as tall as the key and the warning', (
    tester,
  ) async {
    await show(tester, revealDialog());

    expectSizedToContent(tester, const Size(1440, 900));
  });

  testWidgets('the quota dialog is as tall as its three fields', (
    tester,
  ) async {
    await show(
      tester,
      EditQuotaDialog(
        projectName: 'checkout',
        retentionDays: 30,
        maxEntries: null,
        maxBytes: null,
        onSave: (_) {},
        onCancel: () {},
      ),
    );

    expectSizedToContent(tester, const Size(1440, 900));
  });

  testWidgets('the team members dialog names the group the team is in', (
    tester,
  ) async {
    await show(tester, teamMembersDialog());

    expect(find.text('Состав команды «Backend Team»'), findsOneWidget);
    expect(find.text('Группа: Acme Corp'), findsOneWidget);
  });

  testWidgets('a window too short for the content scrolls it', (tester) async {
    // Shorter than the dialog needs. The assertion is that this pumps at all:
    // a column that cannot fit overflows, and an overflow fails the test on
    // its own.
    await show(tester, revealDialog(), window: const Size(1440, 320));

    expect(
      boxOf(tester).height,
      lessThanOrEqualTo(320),
      reason: 'the dialog stays inside the window rather than overflowing it',
    );
    expect(find.byType(SelectableText), findsOneWidget);
  });
}

void _nothing() {}
