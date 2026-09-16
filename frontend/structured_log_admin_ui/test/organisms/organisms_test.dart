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
    /// The shell chooses its shape from its own width, and a widget test's
    /// default surface (800) is below the breakpoint — so a test about the
    /// labelled pane has to say how wide it is.
    void useWideSurface(WidgetTester tester) {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    void useNarrowSurface(WidgetTester tester) {
      tester.view.physicalSize = const Size(720, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('draws sections, items and the page title', (tester) async {
      useWideSurface(tester);
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
      useWideSurface(tester);
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

    testWidgets('narrow, the pane becomes a rail of icons', (tester) async {
      useNarrowSurface(tester);
      await tester.pumpWidget(
        _host(
          AdminAppShell(
            sections: _sections,
            selectedIndex: 0,
            onSelected: (_) {},
            accountName: 'Jana Novak',
            accountRole: 'Администратор',
            content: const SizedBox.shrink(),
          ),
        ),
      );

      // Labels, section titles and the account name are what the rail drops.
      expect(find.text('Обзор'), findsNothing);
      expect(find.text('Пользователи'), findsNothing);
      expect(find.text('Jana Novak'), findsNothing);
      // The initials stay: they are the account button, which is still one.
      expect(find.text('JN'), findsOneWidget);
      // And every item is still there to be pressed.
      expect(find.byIcon(FluentIcons.people), findsOneWidget);
      expect(find.byIcon(FluentIcons.group), findsOneWidget);
    });

    testWidgets('a rail item still reports the same index', (tester) async {
      useNarrowSurface(tester);
      final selected = <int>[];
      await tester.pumpWidget(
        _host(
          AdminAppShell(
            sections: _sections,
            selectedIndex: 0,
            onSelected: selected.add,
            accountName: 'Jana Novak',
            accountRole: 'Администратор',
            content: const SizedBox.shrink(),
          ),
        ),
      );

      await tester.tap(find.byIcon(FluentIcons.group));
      await tester.pumpAndSettle();

      expect(
        selected,
        [2],
        reason: 'collapsing changes what is drawn, not what it means',
      );
    });

    testWidgets('hidden entries are simply absent', (tester) async {
      useWideSurface(tester);
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

  group('AdminFeedStatusStrip', () {
    testWidgets('the live strip only reports', (tester) async {
      await tester.pumpWidget(
        _host(const AdminFeedStatusStrip.live(
            message: 'Лента в реальном времени')),
      );

      expect(find.text('Лента в реальном времени'), findsOneWidget);
      expect(find.byType(AdminButton), findsNothing);
      expect(find.byType(HyperlinkButton), findsNothing);
    });

    testWidgets('the unseen strip is itself the way back', (tester) async {
      var pressed = 0;
      await tester.pumpWidget(
        _host(
          AdminFeedStatusStrip.unseen(
            message: '12 новых записей · перейти к свежим',
            onAction: () => pressed++,
          ),
        ),
      );

      await tester.tap(find.text('12 новых записей · перейти к свежим'));
      await tester.pumpAndSettle();
      expect(pressed, 1);
    });

    testWidgets('a held feed says what is waiting and offers to resume',
        (tester) async {
      var resumed = 0;
      await tester.pumpWidget(
        _host(
          AdminFeedStatusStrip.held(
            message: 'Лента на паузе · накоплено 38 записей',
            actionLabel: 'Возобновить',
            onAction: () => resumed++,
          ),
        ),
      );

      expect(
          find.text('Лента на паузе · накоплено 38 записей'), findsOneWidget);
      await tester.tap(find.text('Возобновить'));
      await tester.pumpAndSettle();
      expect(resumed, 1);
    });

    testWidgets('a stalled feed explains itself on a second line',
        (tester) async {
      await tester.pumpWidget(
        _host(
          AdminFeedStatusStrip.stalled(
            message: 'Пауза длилась слишком долго',
            description: 'Часть событий не поместилась в буфер.',
            actionLabel: 'Перезагрузить и продолжить',
            onAction: () {},
          ),
        ),
      );

      expect(find.text('Пауза длилась слишком долго'), findsOneWidget);
      expect(
          find.text('Часть событий не поместилась в буфер.'), findsOneWidget);
      expect(find.text('Перезагрузить и продолжить'), findsOneWidget);
    });

    testWidgets('the loading strip spins and offers nothing', (tester) async {
      await tester.pumpWidget(
        _host(
          const AdminFeedStatusStrip.loadingOlder(
            message: 'Загружаются более ранние записи…',
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(AdminLoadingIndicator), findsOneWidget);
      expect(find.byType(HyperlinkButton), findsNothing);
    });
  });

  group('AdminTable', () {
    const columns = [
      AdminColumn('Время', width: 120),
      AdminColumn('Инициатор', width: 100),
      AdminColumn.flexible('Детали'),
    ];

    testWidgets('renders the headings and every cell', (tester) async {
      await tester.pumpWidget(
        _host(
          const AdminTable(
            columns: columns,
            rows: [
              AdminTableRow(
                cells: [
                  Text('13.09 14:02'),
                  Text('admin'),
                  Text('retention_days 30 → 7'),
                ],
              ),
            ],
          ),
        ),
      );

      expect(find.text('Время'), findsOneWidget);
      expect(find.text('Инициатор'), findsOneWidget);
      expect(find.text('Детали'), findsOneWidget);
      expect(find.text('13.09 14:02'), findsOneWidget);
      expect(find.text('retention_days 30 → 7'), findsOneWidget);
    });

    testWidgets(
        'a fixed column is the width it asked for, and the flexible '
        'one takes what is left', (tester) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 600,
            child: AdminTable(
              columns: columns,
              rows: [
                AdminTableRow(
                  cells: [Text('время'), Text('актор'), Text('детали')],
                ),
              ],
            ),
          ),
        ),
      );

      // Measured through the cells rather than through the widget tree: what
      // matters is that a timestamp and the one below it start at the same x,
      // which is the whole reason this is a table and not a list of rows.
      final time = tester.getSize(find.text('время'));
      expect(time.width, lessThanOrEqualTo(120));

      expect(
        tester.getSize(find.text('детали')).width,
        greaterThan(120),
        reason: 'the flexible column absorbs the remaining room',
      );
      expect(
        tester.getTopLeft(find.text('детали')).dx,
        tester.getTopLeft(find.text('Детали')).dx,
        reason: 'a cell starts where its heading does — that alignment is the '
            'only thing this widget exists to provide',
      );
    });

    testWidgets('a row shorter than the columns leaves the tail empty',
        (tester) async {
      // Heterogeneous records are the norm in an audit log — an event with no
      // target has nothing to put in that column, and padding the list by hand
      // at every call site would be ceremony.
      await tester.pumpWidget(
        _host(
          const AdminTable(
            columns: columns,
            rows: [
              AdminTableRow(cells: [Text('13.09 14:02')]),
            ],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('13.09 14:02'), findsOneWidget);
    });

    testWidgets('a tinted row paints its own background', (tester) async {
      await tester.pumpWidget(
        _host(
          const AdminTable(
            columns: columns,
            rows: [
              AdminTableRow(cells: [Text('обычная')]),
              AdminTableRow(
                cells: [Text('системная')],
                background: Color(0xFFFFF4CE),
              ),
            ],
          ),
        ),
      );

      Color? backgroundOf(String text) {
        final container = tester.widget<Container>(
          find
              .ancestor(of: find.text(text), matching: find.byType(Container))
              .first,
        );
        return (container.decoration! as BoxDecoration).color;
      }

      expect(backgroundOf('обычная'), isNull);
      expect(backgroundOf('системная'), const Color(0xFFFFF4CE));
    });
  });
}
