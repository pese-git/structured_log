import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

Widget _host(Widget child) => FluentApp(
      theme: AdminTheme.light(),
      home: ScaffoldPage(padding: EdgeInsets.zero, content: child),
    );

const _sections = [
  AdminNavSection(
    title: 'Обзор',
    items: [AdminNavItem(icon: FluentIcons.view_dashboard, label: 'Дашборд')],
  ),
  AdminNavSection(
    title: 'Администрирование',
    items: [
      AdminNavItem(icon: FluentIcons.people, label: 'Пользователи'),
      AdminNavItem(icon: FluentIcons.group, label: 'Группы'),
    ],
  ),
];

void main() {
  group('AdminResourceRow', () {
    testWidgets('shows identifier, title, subtitle, tags and actions',
        (tester) async {
      await tester.pumpWidget(
        _host(
          AdminResourceRow(
            identifier: 'r.silva',
            title: 'Rita Silva',
            subtitle: 'user · mobile-ios',
            tags: const [
              AdminStatusTag(
                label: 'Заблокирован',
                tone: AdminStatusTone.error,
              ),
            ],
            actions: [
              AdminButton(
                label: 'Изменить',
                onPressed: () {},
                size: AdminButtonSize.tonal,
              ),
            ],
          ),
        ),
      );

      expect(find.text('r.silva'), findsOneWidget);
      expect(find.text('Rita Silva'), findsOneWidget);
      expect(find.text('user · mobile-ios'), findsOneWidget);
      expect(find.text('Заблокирован'), findsOneWidget);
      expect(find.text('Изменить'), findsOneWidget);
    });

    testWidgets('an action does not also open the row', (tester) async {
      var opened = 0;
      var edited = 0;
      await tester.pumpWidget(
        _host(
          AdminResourceRow(
            title: 'payments-api',
            onPressed: () => opened++,
            actions: [
              AdminButton(
                label: 'Изменить',
                onPressed: () => edited++,
                size: AdminButtonSize.tonal,
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.text('Изменить'));
      await tester.pumpAndSettle();
      expect(edited, 1);
      expect(opened, 0);
    });

    testWidgets('a row without a callback is not interactive', (tester) async {
      await tester.pumpWidget(
        _host(const AdminResourceRow(title: 'CI pipeline')),
      );
      expect(
        tester.widget<HoverButton>(find.byType(HoverButton)).onPressed,
        isNull,
      );
    });
  });

  group('AdminFilterBar', () {
    testWidgets('renders leading, filters and trailing', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _host(
          AdminFilterBar(
            leading: AdminSearchField(
              controller: controller,
              placeholder: 'Поиск',
            ),
            filters: const [
              AdminFilterChip(label: 'Категория', value: 'payments'),
              AdminFilterChip(value: 'Warning and above', hasMenu: true),
            ],
            trailing: const [AdminTag(label: 'В реальном времени')],
          ),
        ),
      );

      expect(find.byType(AdminSearchField), findsOneWidget);
      expect(find.text('Категория: payments'), findsOneWidget);
      expect(find.text('Warning and above'), findsOneWidget);
      expect(find.text('В реальном времени'), findsOneWidget);
    });

    testWidgets('wraps its controls rather than overflowing', (tester) async {
      // 360 is far narrower than any artboard; the canvas sets flex-wrap on
      // this row, so the Dart side must wrap too instead of asserting.
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 360,
            child: AdminFilterBar(
              filters: [
                AdminFilterChip(label: 'Категория', value: 'payments'),
                AdminFilterChip(label: 'Logger', value: 'webhook.sender'),
                AdminFilterChip(label: 'С', value: '09:00'),
                AdminFilterChip(label: 'По', value: '10:00'),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(AdminFilterChip), findsNWidgets(4));
    });
  });

  group('AdminConfirmDialog', () {
    testWidgets('reports confirm and cancel separately', (tester) async {
      var confirmed = 0;
      var cancelled = 0;
      await tester.pumpWidget(
        _host(
          AdminConfirmDialog(
            title: 'Отозвать секретный ключ?',
            message: 'Ключ «CI pipeline» перестанет приниматься немедленно.',
            confirmLabel: 'Отозвать',
            destructive: true,
            onConfirm: () => confirmed++,
            onCancel: () => cancelled++,
          ),
        ),
      );

      await tester.tap(find.text('Отозвать'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();

      expect(confirmed, 1);
      expect(cancelled, 1);
    });

    testWidgets('a null onConfirm leaves the action disabled', (tester) async {
      await tester.pumpWidget(
        _host(
          AdminConfirmDialog(
            title: 'Удалить аккаунт?',
            message: 'Действие необратимо.',
            confirmLabel: 'Удалить',
            destructive: true,
            onConfirm: null,
            onCancel: () {},
            content: const Text('Введите пароль'),
          ),
        ),
      );

      expect(find.text('Введите пароль'), findsOneWidget);
      final confirm = tester.widget<AdminButton>(
        find.widgetWithText(AdminButton, 'Удалить'),
      );
      expect(confirm.onPressed, isNull);
    });
  });

  group('AdminAppShell', () {
    testWidgets('draws sections, items and the page title', (tester) async {
      await tester.pumpWidget(
        _host(
          AdminAppShell(
            sections: _sections,
            selectedIndex: 0,
            onSelected: (_) {},
            title: 'Дашборд',
            accountName: 'Jana Novak',
            accountRole: 'Администратор',
            content: const SizedBox.shrink(),
          ),
        ),
      );

      expect(find.text('Обзор'), findsOneWidget);
      expect(find.text('Администрирование'), findsOneWidget);
      expect(find.text('Пользователи'), findsOneWidget);
      // Title and nav item are both "Дашборд" — the artboards repeat it.
      expect(find.text('Дашборд'), findsNWidgets(2));
      expect(find.text('JN'), findsOneWidget);
    });

    testWidgets('reports a flat index across sections', (tester) async {
      final selected = <int>[];
      await tester.pumpWidget(
        _host(
          AdminAppShell(
            sections: _sections,
            selectedIndex: 0,
            onSelected: selected.add,
            title: 'Дашборд',
            accountName: 'Jana Novak',
            accountRole: 'Администратор',
            content: const SizedBox.shrink(),
          ),
        ),
      );

      await tester.tap(find.text('Группы'));
      await tester.pumpAndSettle();
      // Дашборд is 0; Пользователи 1; Группы 2 — counted across sections, not
      // within one.
      expect(selected, [2]);
    });

    testWidgets('hidden entries are simply absent', (tester) async {
      await tester.pumpWidget(
        _host(
          AdminAppShell(
            sections: [_sections.first],
            selectedIndex: 0,
            onSelected: (_) {},
            title: 'Дашборд',
            accountName: 'Rita Silva',
            accountRole: 'Пользователь',
            content: const SizedBox.shrink(),
          ),
        ),
      );
      expect(find.text('Пользователи'), findsNothing);
      expect(find.text('Администрирование'), findsNothing);
    });
  });

  group('AdminLogEntryRow', () {
    testWidgets('shows level, time, event and category', (tester) async {
      await tester.pumpWidget(
        _host(
          const AdminLogEntryRow(
            level: AdminLogLevel.error,
            time: '09:12:55',
            event: 'Webhook delivery failed after 3 attempts',
            category: 'webhooks',
          ),
        ),
      );

      expect(find.text('ERR'), findsOneWidget);
      expect(find.text('09:12:55'), findsOneWidget);
      expect(
        find.text('Webhook delivery failed after 3 attempts'),
        findsOneWidget,
      );
      expect(find.text('webhooks'), findsOneWidget);
    });

    testWidgets('an entry without a category shows no chip', (tester) async {
      await tester.pumpWidget(
        _host(
          const AdminLogEntryRow(
            level: AdminLogLevel.info,
            time: '09:10:58',
            event: 'Refund processed',
          ),
        ),
      );
      expect(find.byType(AdminTag), findsNothing);
    });

    testWidgets('reports a tap', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        _host(
          AdminLogEntryRow(
            level: AdminLogLevel.info,
            time: '09:10:58',
            event: 'Refund processed',
            onPressed: () => opened++,
          ),
        ),
      );

      await tester.tap(find.text('Refund processed'));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });
  });
}
