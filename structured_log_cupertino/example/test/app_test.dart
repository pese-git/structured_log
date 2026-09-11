import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_cupertino/structured_log_cupertino.dart';
import 'package:structured_log_cupertino_example/main.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

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
    await tester.pumpAndSettle();

    expect(buffer.entries.value, hasLength(1));
    expect(buffer.entries.value.single['event'], 'user_login');
  });

  testWidgets('"Open log viewer (full screen)" pushes CupertinoLogViewerPage',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ExampleApp(controller: controller));
    await tester.tap(find.text('Open log viewer (full screen)'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoLogViewerPage), findsOneWidget);
  });

  testWidgets('"Open embedded log viewer demo" pushes CupertinoLogViewer',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ExampleApp(controller: controller));
    await tester.tap(find.text('Open embedded log viewer demo'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoLogViewer), findsOneWidget);
    expect(find.byType(CupertinoLogViewerPage), findsNothing);
  });
}
