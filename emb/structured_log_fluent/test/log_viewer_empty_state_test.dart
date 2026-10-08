import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_fluent/structured_log_fluent.dart';

Future<void> _pump(WidgetTester tester,
    {required Size host, required bool hasLogs}) {
  return tester.pumpWidget(
    FluentApp(
      home: Center(
        child: SizedBox(
          width: host.width,
          height: host.height,
          child: LogViewerEmptyState(hasLogs: hasLogs, onClearFilters: () {}),
        ),
      ),
    ),
  );
}

void main() {
  for (final hasLogs in [false, true]) {
    testWidgets(
      'does not overflow in a short, narrow host (hasLogs: $hasLogs)',
      (tester) async {
        await _pump(tester, host: const Size(320, 140), hasLogs: hasLogs);

        expect(tester.takeException(), isNull);
        expect(find.text(hasLogs ? 'No results found' : 'No logs yet'),
            findsOneWidget);
      },
    );
  }

  testWidgets('stays centered when the host is taller than the content',
      (tester) async {
    await _pump(tester, host: const Size(600, 600), hasLogs: false);

    final center = tester.getCenter(find.text('No logs yet'));
    expect(center.dx, closeTo(400, 1));
    expect(tester.takeException(), isNull);
  });
}
