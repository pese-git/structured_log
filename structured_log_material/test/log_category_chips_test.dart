import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';
import 'package:structured_log_material/structured_log_material.dart';

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
  String allLabel = 'All',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          child: LogCategoryChips(controller: controller, allLabel: allLabel),
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

    expect(find.byType(ChoiceChip), findsNothing);
  });

  testWidgets('renders nothing when only one distinct category is present',
      (tester) async {
    buffer.capture(_entry(event: 'a', category: 'application'), LogLevel.info);
    buffer.capture(_entry(event: 'b', category: 'application'), LogLevel.info);
    await _pump(tester, controller);

    expect(find.byType(ChoiceChip), findsNothing);
  });

  testWidgets(
      'renders sorted distinct category chips plus the all-label once two '
      'or more are present', (tester) async {
    buffer.capture(_entry(event: 'a', category: 'protocol'), LogLevel.info);
    buffer.capture(_entry(event: 'b', category: 'application'), LogLevel.info);
    buffer.capture(_entry(event: 'c'), LogLevel.info); // no category

    await _pump(tester, controller);

    expect(find.widgetWithText(ChoiceChip, 'All'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'application'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'protocol'), findsOneWidget);
  });

  testWidgets('selecting a category sets the controller filter',
      (tester) async {
    buffer.capture(_entry(event: 'a', category: 'protocol'), LogLevel.info);
    buffer.capture(_entry(event: 'b', category: 'application'), LogLevel.info);
    await _pump(tester, controller);

    await tester.tap(find.widgetWithText(ChoiceChip, 'protocol'));
    await tester.pumpAndSettle();

    expect(controller.categoryFilter, 'protocol');
  });

  testWidgets('selecting the all-label chip clears the controller filter',
      (tester) async {
    buffer.capture(_entry(event: 'a', category: 'protocol'), LogLevel.info);
    buffer.capture(_entry(event: 'b', category: 'application'), LogLevel.info);
    controller.categoryFilter = 'protocol';
    await _pump(tester, controller);

    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await tester.pumpAndSettle();

    expect(controller.categoryFilter, isNull);
  });

  testWidgets('a custom allLabel is used for the "no filter" chip',
      (tester) async {
    buffer.capture(_entry(event: 'a', category: 'protocol'), LogLevel.info);
    buffer.capture(_entry(event: 'b', category: 'application'), LogLevel.info);
    await _pump(tester, controller, allLabel: 'Any category');

    expect(find.widgetWithText(ChoiceChip, 'Any category'), findsOneWidget);
  });
}
