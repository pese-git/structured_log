import 'package:structured_log_material_example/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';
import 'package:structured_log_material/structured_log_material.dart';

void main() {
  late LogBuffer buffer;
  late LogViewerController controller;

  setUp(() {
    buffer = LogBuffer();
    controller = LogViewerController(buffer);
    // Same wiring main() does: the sink the demo buttons log through feeds
    // the same buffer the pumped controller reads from.
    StructlogConfiguration.configure(
      sinks: [LogSink(name: 'viewer', output: buffer.capture)],
    );
  });

  tearDown(() {
    controller.dispose();
    StructlogConfiguration.reset();
  });

  testWidgets('logging a demo event captures it into the buffer',
      (tester) async {
    await tester.pumpWidget(ExampleApp(controller: controller));
    await tester.tap(find.text('Log an info event'));
    await tester.pump();

    expect(buffer.entries.value, hasLength(1));
    expect(buffer.entries.value.single['event'], 'user_login');
  });

  testWidgets('"Open log viewer" pushes MaterialLogViewerPage', (tester) async {
    await tester.pumpWidget(ExampleApp(controller: controller));
    await tester.tap(find.text('Open log viewer'));
    await tester.pumpAndSettle();

    expect(find.byType(MaterialLogViewerPage), findsOneWidget);
  });
}
