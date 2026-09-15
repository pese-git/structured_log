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
}
