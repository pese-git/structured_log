import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';
import 'package:structured_log_fluent/structured_log_fluent.dart';

Map<String, dynamic> _entry({required String event, String? category}) {
  return {
    'event': event,
    'level': 'info',
    'timestamp': '2026-01-01T12:00:00.000',
    if (category != null) 'category': category,
  };
}

Future<void> _pump(
  WidgetTester tester,
  LogViewerController controller, {
  String allLabel = 'All types',
}) async {
  await tester.pumpWidget(
    FluentApp(
      home: ScaffoldPage(
        content: Center(
          child: SizedBox(
            width: 220,
            child: LogCategoryComboBox(
              controller: controller,
              allLabel: allLabel,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  late LogBuffer buffer;
  late LogViewerController controller;

  setUp(() {
    buffer = LogBuffer();
    controller = LogViewerController(buffer);
  });

  tearDown(() => controller.dispose());

  testWidgets('renders nothing when the buffer has no categorized entries',
      (tester) async {
    buffer.capture(_entry(event: 'a'), LogLevel.info);
    await _pump(tester, controller);

    expect(find.byType(ComboBox<String?>), findsNothing);
  });

  testWidgets('renders nothing when only one distinct category is present',
      (tester) async {
    buffer.capture(_entry(event: 'a', category: 'application'), LogLevel.info);
    buffer.capture(_entry(event: 'b', category: 'application'), LogLevel.info);
    await _pump(tester, controller);

    expect(find.byType(ComboBox<String?>), findsNothing);
  });

  testWidgets(
      'renders a ComboBox with sorted distinct categories once two or more '
      'are present', (tester) async {
    buffer.capture(_entry(event: 'a', category: 'protocol'), LogLevel.info);
    buffer.capture(_entry(event: 'b', category: 'application'), LogLevel.info);
    buffer.capture(_entry(event: 'c'), LogLevel.info); // no category
    await _pump(tester, controller);

    expect(find.byType(ComboBox<String?>), findsOneWidget);

    await tester.tap(find.byType(ComboBox<String?>));
    await tester.pumpAndSettle();

    // "All types" appears both as the closed-field placeholder and as the
    // open overlay's own item; the category items only appear once (in the
    // overlay), since neither is currently selected.
    expect(find.text('All types'), findsNWidgets(2));
    expect(find.text('application'), findsOneWidget);
    expect(find.text('protocol'), findsOneWidget);
  });

  testWidgets('selecting a category sets the controller filter',
      (tester) async {
    buffer.capture(_entry(event: 'a', category: 'protocol'), LogLevel.info);
    buffer.capture(_entry(event: 'b', category: 'application'), LogLevel.info);
    await _pump(tester, controller);

    await tester.tap(find.byType(ComboBox<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('protocol').last);
    await tester.pumpAndSettle();

    expect(controller.categoryFilter, 'protocol');
  });

  testWidgets('selecting the all-label option clears the controller filter',
      (tester) async {
    buffer.capture(_entry(event: 'a', category: 'protocol'), LogLevel.info);
    buffer.capture(_entry(event: 'b', category: 'application'), LogLevel.info);
    await _pump(tester, controller);
    controller.categoryFilter = 'protocol';
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ComboBox<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All types').last);
    await tester.pumpAndSettle();

    expect(controller.categoryFilter, isNull);
  });

  testWidgets(
      'a custom allLabel is used as the placeholder and "no filter" option',
      (tester) async {
    buffer.capture(_entry(event: 'a', category: 'protocol'), LogLevel.info);
    buffer.capture(_entry(event: 'b', category: 'application'), LogLevel.info);
    await _pump(tester, controller, allLabel: 'Any category');

    expect(find.text('Any category'), findsOneWidget);
  });
}
