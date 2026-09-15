import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

/// Every atom is drawn inside a real `FluentTheme`, because they all read the
/// brightness from it to choose a palette.
Widget _host(Widget child, {Brightness brightness = Brightness.light}) {
  return FluentApp(
    theme: AdminTheme.of(brightness),
    home: ScaffoldPage(content: Center(child: child)),
  );
}

void main() {
  group('AdminLogLevelBadge', () {
    testWidgets('shows the level abbreviation', (tester) async {
      await tester.pumpWidget(
        _host(const AdminLogLevelBadge(level: AdminLogLevel.warning)),
      );
      expect(find.text('WRN'), findsOneWidget);
    });

    testWidgets('keeps one width across levels so a column aligns',
        (tester) async {
      for (final level in AdminLogLevel.values) {
        await tester.pumpWidget(_host(AdminLogLevelBadge(level: level)));
        final size = tester.getSize(find.byType(AdminLogLevelBadge));
        expect(size.width, AdminSizes.levelBadgeWidth);
      }
    });

    testWidgets('picks a different palette in dark', (tester) async {
      Color paint(Brightness b) => AdminLogLevelColors.foreground(
            AdminLogLevel.error,
            b,
          );
      expect(paint(Brightness.light), isNot(paint(Brightness.dark)));
    });
  });

  group('AdminButton', () {
    testWidgets('calls back when pressed', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(
        _host(AdminButton(label: 'Создать', onPressed: () => pressed++)),
      );
      await tester.tap(find.text('Создать'));
      // settle, not pump: Fluent's HoverButton starts a 100ms timer on
      // tap-up, and leaving it pending fails the test after the callback has
      // already run.
      await tester.pumpAndSettle();
      expect(pressed, 1);
    });

    testWidgets('a null callback disables it', (tester) async {
      await tester.pumpWidget(
        const _host2(AdminButton(label: 'Создать', onPressed: null)),
      );
      final button = tester.widget<Button>(find.byType(Button));
      expect(button.onPressed, isNull);
    });

    testWidgets('the tonal variant is the shorter one', (tester) async {
      await tester.pumpWidget(
        _host(
          AdminButton(
            label: 'Открыть',
            onPressed: () {},
            variant: AdminButtonVariant.tonal,
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(AdminButton)).height,
        AdminSizes.tonalButtonHeight,
      );
    });

    testWidgets('renders a leading icon when given one', (tester) async {
      await tester.pumpWidget(
        _host(
          AdminButton(
            label: 'Добавить',
            onPressed: () {},
            icon: FluentIcons.add,
          ),
        ),
      );
      expect(find.byType(Icon), findsOneWidget);
      expect(find.text('Добавить'), findsOneWidget);
    });
  });

  group('AdminTag', () {
    testWidgets('renders its label at the canvas height', (tester) async {
      await tester.pumpWidget(_host(const AdminTag(label: 'owner')));
      expect(find.text('owner'), findsOneWidget);
      expect(
        tester.getSize(find.byType(AdminTag)).height,
        AdminSizes.badgeHeight,
      );
    });
  });

  group('AdminEmptyState', () {
    testWidgets('shows title, description and action', (tester) async {
      await tester.pumpWidget(
        _host(
          AdminEmptyState(
            icon: FluentIcons.group,
            title: 'Групп пока нет',
            description: 'Создайте первую группу',
            action: AdminButton(label: 'Создать', onPressed: () {}),
          ),
        ),
      );
      expect(find.text('Групп пока нет'), findsOneWidget);
      expect(find.text('Создайте первую группу'), findsOneWidget);
      expect(find.byType(AdminButton), findsOneWidget);
    });

    testWidgets('description and action are optional', (tester) async {
      await tester.pumpWidget(
        _host(
          const AdminEmptyState(
            icon: FluentIcons.group,
            title: 'Ничего не найдено',
          ),
        ),
      );
      expect(find.text('Ничего не найдено'), findsOneWidget);
      expect(find.byType(AdminButton), findsNothing);
    });
  });

  group('AdminLoadingIndicator', () {
    testWidgets('has two sizes', (tester) async {
      await tester.pumpWidget(_host(const AdminLoadingIndicator()));
      expect(tester.getSize(find.byType(AdminLoadingIndicator)).width, 32);

      await tester.pumpWidget(
        _host(const AdminLoadingIndicator(inline: true)),
      );
      expect(tester.getSize(find.byType(AdminLoadingIndicator)).width, 16);
    });
  });
}

/// Const-constructible host, for the cases that pump a const widget.
class _host2 extends StatelessWidget {
  final Widget child;
  const _host2(this.child);

  @override
  Widget build(BuildContext context) => _host(child);
}
