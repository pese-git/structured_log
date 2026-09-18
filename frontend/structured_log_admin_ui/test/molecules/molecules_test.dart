import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';

Widget _host(Widget child) => FluentApp(
      theme: AdminTheme.light(),
      home: ScaffoldPage(
        content: Center(child: SizedBox(width: 400, child: child)),
      ),
    );

void main() {
  group('AdminSearchField', () {
    testWidgets('reports what was typed', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      String? seen;

      await tester.pumpWidget(
        _host(
          AdminSearchField(
            controller: controller,
            placeholder: 'Поиск',
            onChanged: (v) => seen = v,
          ),
        ),
      );
      await tester.enterText(find.byType(TextBox), 'webhook');
      expect(seen, 'webhook');
    });

    testWidgets('offers no clear button until there is something to clear',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _host(
          AdminSearchField(controller: controller, placeholder: 'Поиск'),
        ),
      );
      expect(find.byType(IconButton), findsNothing);

      await tester.enterText(find.byType(TextBox), 'payments');
      await tester.pump();
      expect(find.byType(IconButton), findsOneWidget);
    });

    testWidgets('clearing empties the field and reports it', (tester) async {
      final controller = TextEditingController(text: 'payments');
      addTearDown(controller.dispose);
      var cleared = 0;
      String? lastChange;

      await tester.pumpWidget(
        _host(
          AdminSearchField(
            controller: controller,
            placeholder: 'Поиск',
            onChanged: (v) => lastChange = v,
            onCleared: () => cleared++,
          ),
        ),
      );
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(controller.text, isEmpty);
      expect(lastChange, isEmpty);
      expect(cleared, 1);
    });
  });

  group('AdminFilterChip', () {
    testWidgets('joins label and value the way the canvas writes them',
        (tester) async {
      await tester.pumpWidget(
        _host(const AdminFilterChip(label: 'Категория', value: 'payments')),
      );
      expect(find.text('Категория: payments'), findsOneWidget);
    });

    testWidgets('a chip without a label shows the value alone', (tester) async {
      await tester.pumpWidget(
        _host(const AdminFilterChip(value: 'Warning and above')),
      );
      expect(find.text('Warning and above'), findsOneWidget);
    });

    testWidgets('reports taps and clears separately', (tester) async {
      var pressed = 0;
      var cleared = 0;
      await tester.pumpWidget(
        _host(
          AdminFilterChip(
            value: 'payments',
            onPressed: () => pressed++,
            onCleared: () => cleared++,
          ),
        ),
      );

      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();
      expect(cleared, 1);
      expect(pressed, 0, reason: 'clearing is not selecting');

      await tester.tap(find.text('payments'));
      await tester.pumpAndSettle();
      expect(pressed, 1);
    });
  });

  group('AdminQuotaBar', () {
    testWidgets('states usage and limit as one quantity', (tester) async {
      await tester.pumpWidget(
        _host(
          const AdminQuotaBar(
            label: 'Записей (max_entries)',
            usageLabel: '842',
            limitLabel: '1 000',
            fraction: 0.84,
          ),
        ),
      );
      expect(find.text('842 / 1 000'), findsOneWidget);
    });

    testWidgets('an unset quota drops the track instead of drawing it empty',
        (tester) async {
      await tester.pumpWidget(
        _host(const AdminQuotaBar(label: 'Объём', usageLabel: '128 МБ')),
      );
      expect(find.text('128 МБ'), findsOneWidget);
      expect(find.byType(FractionallySizedBox), findsNothing);
    });
  });

  group('AdminKeyValueRow', () {
    testWidgets('shows both halves', (tester) async {
      await tester.pumpWidget(
        _host(
          const AdminKeyValueRow(label: 'status_code', value: '504'),
        ),
      );
      expect(find.text('status_code'), findsOneWidget);
      expect(find.text('504'), findsOneWidget);
    });

    testWidgets('can render the value monospaced', (tester) async {
      await tester.pumpWidget(
        _host(
          const AdminKeyValueRow(
            label: 'request_id',
            value: '1f82-e887',
            monospaceValue: true,
          ),
        ),
      );
      final text = tester.widget<Text>(find.text('1f82-e887'));
      expect(text.style?.fontFamily, AdminTypography.monoFontFamily);
    });
  });

  group('AdminStatusTag', () {
    testWidgets('hugs its label instead of filling the row', (tester) async {
      // A Container with `alignment` and no width expands to its constraints;
      // in a Wrap or a stretched column that turns every status tag into a
      // full-width bar. Widget tests that only checked the height missed it,
      // the gallery showed it immediately.
      await tester.pumpWidget(
        _host(
          const Align(
            alignment: Alignment.centerLeft,
            child: AdminStatusTag(
              label: 'Заблокирован',
              tone: AdminStatusTone.error,
            ),
          ),
        ),
      );
      final width = tester.getSize(find.byType(AdminStatusTag)).width;
      expect(width, lessThan(200));
      expect(width, greaterThan(AdminSpacing.x8 * 2));
    });

    testWidgets('each tone gets its own pair', (tester) async {
      for (final tone in AdminStatusTone.values) {
        await tester.pumpWidget(
          _host(AdminStatusTag(label: 'Заблокирован', tone: tone)),
        );
        expect(find.text('Заблокирован'), findsOneWidget);
      }
    });
  });

  group('AdminLabeledToggle', () {
    testWidgets('reports the new value', (tester) async {
      bool? changed;
      await tester.pumpWidget(
        _host(
          AdminLabeledToggle(
            label: 'Разрешить регистрацию',
            value: false,
            onChanged: (v) => changed = v,
          ),
        ),
      );
      await tester.tap(find.byType(ToggleSwitch));
      await tester.pumpAndSettle();
      expect(changed, isTrue);
    });

    testWidgets('a null callback disables the switch', (tester) async {
      await tester.pumpWidget(
        _host(
          const AdminLabeledToggle(
            label: 'Разрешить регистрацию',
            description: 'Сервер отклонит POST /v1/auth/register',
            value: true,
            onChanged: null,
          ),
        ),
      );
      expect(
          find.text('Сервер отклонит POST /v1/auth/register'), findsOneWidget);
      expect(
        tester.widget<ToggleSwitch>(find.byType(ToggleSwitch)).onChanged,
        isNull,
      );
    });
  });

  group('AdminTextField', () {
    testWidgets('shows its label and reports typing', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      String? seen;

      await tester.pumpWidget(
        _host(
          AdminTextField(
            label: 'Имя пользователя',
            controller: controller,
            onChanged: (v) => seen = v,
          ),
        ),
      );

      expect(find.text('Имя пользователя'), findsOneWidget);
      await tester.enterText(find.byType(TextBox), 'dana.kim');
      expect(seen, 'dana.kim');
    });

    testWidgets('a password field masks what is typed', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _host(
          AdminTextField(
            label: 'Пароль',
            controller: controller,
            obscure: true,
          ),
        ),
      );
      expect(tester.widget<TextBox>(find.byType(TextBox)).obscureText, isTrue);
    });

    testWidgets('an error message is shown under the field', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _host(
          AdminTextField(
            label: 'Email',
            controller: controller,
            errorText: 'Укажите email',
          ),
        ),
      );
      expect(find.text('Укажите email'), findsOneWidget);
    });

    testWidgets('a disabled field does not accept input', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _host(
          AdminTextField(
            label: 'Пароль',
            controller: controller,
            enabled: false,
          ),
        ),
      );
      expect(tester.widget<TextBox>(find.byType(TextBox)).enabled, isFalse);
    });

    testWidgets('the label line can carry a link', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _host(
          AdminTextField(
            label: 'Пароль',
            controller: controller,
            labelAction: const Text('Забыли пароль?'),
          ),
        ),
      );
      expect(find.text('Забыли пароль?'), findsOneWidget);
    });
  });

  group('AdminBanner', () {
    testWidgets('renders its message in each tone', (tester) async {
      for (final tone in AdminBannerTone.values) {
        await tester.pumpWidget(
          _host(AdminBanner(message: 'Что-то произошло', tone: tone)),
        );
        expect(find.text('Что-то произошло'), findsOneWidget, reason: '$tone');
      }
    });

    testWidgets('an action belongs to the message', (tester) async {
      await tester.pumpWidget(
        _host(
          AdminBanner(
            message: 'Email не подтверждён',
            tone: AdminBannerTone.info,
            action: AdminButton(
              label: 'Отправить ещё раз',
              onPressed: () {},
              size: AdminButtonSize.tonal,
            ),
          ),
        ),
      );
      expect(find.text('Email не подтверждён'), findsOneWidget);
      expect(find.text('Отправить ещё раз'), findsOneWidget);
    });
  });

  group('AdminLivePill', () {
    testWidgets('says which state the feed is in', (tester) async {
      await tester.pumpWidget(
        _host(const AdminLivePill(label: 'В реальном времени')),
      );
      expect(find.text('В реальном времени'), findsOneWidget);

      await tester.pumpWidget(
        _host(
          const AdminLivePill(
            label: 'На паузе',
            tone: AdminLiveTone.paused,
          ),
        ),
      );
      expect(find.text('На паузе'), findsOneWidget);
    });

    testWidgets('the two tones do not share a colour', (tester) async {
      Color dotOf(WidgetTester tester) {
        final dot = tester.widget<Container>(
          find.descendant(
            of: find.byType(AdminLiveDot),
            matching: find.byType(Container),
          ),
        );
        return (dot.decoration! as BoxDecoration).color!;
      }

      await tester.pumpWidget(_host(const AdminLivePill(label: 'Живая')));
      final live = dotOf(tester);

      await tester.pumpWidget(
        _host(
          const AdminLivePill(label: 'Пауза', tone: AdminLiveTone.paused),
        ),
      );
      expect(dotOf(tester), isNot(live));
    });
  });

  group('AdminDateRangeField', () {
    String day(DateTime value) => '${value.day}.${value.month}';

    Widget field({
      DateTime? from,
      DateTime? to,
      ValueChanged<DateTime?>? onFrom,
      ValueChanged<DateTime?>? onTo,
    }) =>
        AdminDateRangeField(
          from: from,
          to: to,
          formatDate: day,
          onFromChanged: onFrom ?? (_) {},
          onToChanged: onTo ?? (_) {},
        );

    testWidgets('an open end says so instead of showing a date',
        (tester) async {
      await tester.pumpWidget(_host(field(from: DateTime(2026, 9, 1))));

      expect(find.text('С: 1.9'), findsOneWidget);
      expect(
        find.text('По: любая'),
        findsOneWidget,
        reason: 'the upper bound is unset, and an unset bound must not read as '
            'today — that would be a filter nobody asked for',
      );
    });

    testWidgets('each end opens its own calendar', (tester) async {
      await tester.pumpWidget(_host(field(from: DateTime(2026, 9, 1))));

      await tester.tap(find.text('С: 1.9'));
      await tester.pumpAndSettle();

      expect(find.byType(CalendarView), findsOneWidget);
    });

    testWidgets('the calendar offers a way back to an open end',
        (tester) async {
      // Without this command a reader who once picked a date could only move
      // it, never take it back, and "since Monday, up to whenever" would be
      // unaskable.
      DateTime? reported = DateTime(2026, 9, 1);
      var reports = 0;

      await tester.pumpWidget(
        _host(
          field(
            from: DateTime(2026, 9, 1),
            onFrom: (value) {
              reported = value;
              reports++;
            },
          ),
        ),
      );

      await tester.tap(find.text('С: 1.9'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Любая дата'));
      await tester.pumpAndSettle();

      expect(reports, 1);
      expect(reported, isNull);
      expect(find.byType(CalendarView), findsNothing);
    });

    testWidgets('picking a day reports it and closes the calendar',
        (tester) async {
      DateTime? reported;

      await tester.pumpWidget(
        _host(field(from: DateTime(2026, 9, 1), onFrom: (v) => reported = v)),
      );

      await tester.tap(find.text('С: 1.9'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('17').first);
      await tester.pumpAndSettle();

      expect(reported, isNotNull);
      expect(reported!.day, 17);
      expect(reported!.month, 9);
      expect(find.byType(CalendarView), findsNothing);
    });

    testWidgets('the two ends fence each other in', (tester) async {
      // A range with its end before its start returns nothing; saying so in
      // the calendar beats reporting an empty page afterwards.
      await tester.pumpWidget(
        _host(field(from: DateTime(2026, 9, 10), to: DateTime(2026, 9, 20))),
      );

      await tester.tap(find.text('С: 10.9'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CalendarView>(find.byType(CalendarView)).maxDate,
        DateTime(2026, 9, 20),
      );
      await tester.tap(find.text('Любая дата'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('По: 20.9'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CalendarView>(find.byType(CalendarView)).minDate,
        DateTime(2026, 9, 10),
      );
    });
  });

  group('AdminTimeRangeField', () {
    String hm(DateTime value) => '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';

    Widget field({
      DateTime? from,
      DateTime? to,
      ValueChanged<DateTime?>? onFrom,
      ValueChanged<DateTime?>? onTo,
    }) =>
        AdminTimeRangeField(
          from: from,
          to: to,
          formatTime: hm,
          onFromChanged: onFrom ?? (_) {},
          onToChanged: onTo ?? (_) {},
        );

    testWidgets('an open end says so instead of showing a time', (
      tester,
    ) async {
      await tester.pumpWidget(_host(field(from: DateTime(2026, 9, 1, 9, 30))));

      expect(find.text('С: 09:30'), findsOneWidget);
      expect(
        find.text('По: любое'),
        findsOneWidget,
        reason: 'the upper bound is unset, and an unset bound must not read as '
            'now — that would be a filter nobody asked for',
      );
    });

    testWidgets('each end opens its own hour and minute pickers', (
      tester,
    ) async {
      await tester.pumpWidget(_host(field(from: DateTime(2026, 9, 1, 9, 30))));

      await tester.tap(find.text('С: 09:30'));
      await tester.pumpAndSettle();

      expect(find.byWidgetPredicate((w) => w is ComboBox), findsNWidgets(2));
    });

    testWidgets('the flyout offers a way back to an open end', (
      tester,
    ) async {
      DateTime? reported = DateTime(2026, 9, 1, 9, 30);
      var reports = 0;

      await tester.pumpWidget(
        _host(
          field(
            from: DateTime(2026, 9, 1, 9, 30),
            onFrom: (value) {
              reported = value;
              reports++;
            },
          ),
        ),
      );

      await tester.tap(find.text('С: 09:30'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Любое время'));
      await tester.pumpAndSettle();

      expect(reports, 1);
      expect(reported, isNull);
    });

    testWidgets(
      "picking an hour and a minute applies them on the bound's own day",
      (tester) async {
        DateTime? reported;

        await tester.pumpWidget(
          _host(
            field(
              from: DateTime(2026, 9, 1, 9, 30),
              onFrom: (value) => reported = value,
            ),
          ),
        );

        await tester.tap(find.text('С: 09:30'));
        await tester.pumpAndSettle();

        // Driven directly rather than through the popup: fluent_ui's own
        // ComboBox lazily builds its (up to 60-item) list, so an item far
        // from the current selection is not built until scrolled into view.
        // This widget's own logic — combining the two picks onto the
        // bound's day — is what is under test here, not the popup's own
        // scroll mechanics.
        ComboBox<int> hourCombo() =>
            tester.widgetList<ComboBox<int>>(find.byType(ComboBox<int>)).first;
        ComboBox<int> minuteCombo() =>
            tester.widgetList<ComboBox<int>>(find.byType(ComboBox<int>)).last;

        hourCombo().onChanged!(14);
        await tester.pump();
        minuteCombo().onChanged!(45);
        await tester.pump();

        await tester.tap(find.text('Применить'));
        await tester.pumpAndSettle();

        expect(reported, isNotNull);
        expect(reported!.year, 2026);
        expect(reported!.month, 9);
        expect(reported!.day, 1);
        expect(reported!.hour, 14);
        expect(reported!.minute, 45);
      },
    );

    testWidgets('applying with no prior value anchors to today', (
      tester,
    ) async {
      DateTime? reported;
      final before = DateTime.now();

      await tester
          .pumpWidget(_host(field(onFrom: (value) => reported = value)));

      await tester.tap(find.text('С: любое'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Применить'));
      await tester.pumpAndSettle();

      expect(reported, isNotNull);
      expect(reported!.year, before.year);
      expect(reported!.month, before.month);
      expect(reported!.day, before.day);
    });
  });

  group('AdminSearchPicker', () {
    testWidgets(
      'a result that resolves after the suggestions overlay has already '
      'opened is still shown, not lost behind it',
      (tester) async {
        // `fluent_ui`'s `AutoSuggestBox` (this repo's pinned 4.15.1) opens its
        // overlay the instant the field's text changes, painting whatever
        // `items` it was given at that exact moment — before this widget's
        // own debounced search has had a chance to answer. A `Completer`
        // held open across that gap reproduces the race deterministically,
        // without depending on real wall-clock timing the way the browser
        // integration test that first found this had to.
        final resultsCompleter = Completer<List<AdminSearchPickerItem<int>>>();
        AdminSearchPickerItem<int>? selected;

        await tester.pumpWidget(
          _host(
            AdminSearchPicker<int>(
              label: 'Пользователь',
              onSearch: (_) => resultsCompleter.future,
              onSelected: (item) => selected = item,
            ),
          ),
        );

        await tester.tap(find.byType(AutoSuggestBox<int>));
        await tester.pump();
        // Typing is what opens the overlay (a focus with empty text does
        // not) — it opens synchronously, well before the 300ms debounce
        // below even starts, let alone before `onSearch` answers.
        await tester.enterText(find.byType(AutoSuggestBox<int>), 'op');
        await tester.pump(const Duration(milliseconds: 350));
        expect(
          find.text('operator'),
          findsNothing,
          reason: 'the search has not answered yet',
        );

        resultsCompleter.complete([
          const AdminSearchPickerItem(value: 5, label: 'operator'),
        ]);
        await tester.pumpAndSettle();

        expect(
          find.text('operator'),
          findsOneWidget,
          reason: 'the overlay was already open when the result arrived — it '
              'must still pick it up rather than stay on what it opened with',
        );

        await tester.tap(find.text('operator'));
        await tester.pumpAndSettle();
        expect(selected?.value, 5);
      },
    );
  });
}
