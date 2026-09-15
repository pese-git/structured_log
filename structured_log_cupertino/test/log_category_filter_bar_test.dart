import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_cupertino/structured_log_cupertino.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

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
    CupertinoApp(
      home: CupertinoPageScaffold(
        child: SizedBox(
          width: 400,
          child: LogCategoryFilterBar(
            controller: controller,
            allLabel: allLabel,
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

    expect(find.byType(CupertinoButton), findsNothing);
  });

  testWidgets('renders nothing when only one distinct category is present',
      (tester) async {
    buffer.capture(_entry(event: 'a', category: 'application'), LogLevel.info);
    buffer.capture(_entry(event: 'b', category: 'application'), LogLevel.info);
    await _pump(tester, controller);

    expect(find.byType(CupertinoButton), findsNothing);
  });

  testWidgets(
      'renders sorted distinct category pills plus the all-label once two '
      'or more are present', (tester) async {
    buffer.capture(_entry(event: 'a', category: 'protocol'), LogLevel.info);
    buffer.capture(_entry(event: 'b', category: 'application'), LogLevel.info);
    buffer.capture(_entry(event: 'c'), LogLevel.info); // no category

    await _pump(tester, controller);

    expect(find.text('All'), findsOneWidget);
    expect(find.text('application'), findsOneWidget);
    expect(find.text('protocol'), findsOneWidget);
  });

  testWidgets('selecting a category sets the controller filter',
      (tester) async {
    buffer.capture(_entry(event: 'a', category: 'protocol'), LogLevel.info);
    buffer.capture(_entry(event: 'b', category: 'application'), LogLevel.info);
    await _pump(tester, controller);

    await tester.tap(find.text('protocol'));
    await tester.pumpAndSettle();

    expect(controller.categoryFilter, 'protocol');
  });

  testWidgets('selecting the all-label pill clears the controller filter',
      (tester) async {
    buffer.capture(_entry(event: 'a', category: 'protocol'), LogLevel.info);
    buffer.capture(_entry(event: 'b', category: 'application'), LogLevel.info);
    controller.categoryFilter = 'protocol';
    await _pump(tester, controller);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    expect(controller.categoryFilter, isNull);
  });

  testWidgets('a custom allLabel is used for the "no filter" pill',
      (tester) async {
    buffer.capture(_entry(event: 'a', category: 'protocol'), LogLevel.info);
    buffer.capture(_entry(event: 'b', category: 'application'), LogLevel.info);
    await _pump(tester, controller, allLabel: 'Any category');

    expect(find.text('Any category'), findsOneWidget);
  });
}
