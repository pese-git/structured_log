import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_ui/structured_log_admin_ui.dart';
import 'package:structured_log_admin_ui_example/main.dart';

void main() {
  /// The gallery is one long `ListView`, which builds only what fits. At the
  /// default 800x600 the later sections never exist, so the surface is sized
  /// to an artboard's width and enough height to hold the page.
  void useLargeSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('the gallery renders every family of component', (tester) async {
    useLargeSurface(tester);
    await tester.pumpWidget(const GalleryApp());
    // pump, not pumpAndSettle: the gallery shows AdminLoadingIndicator, and a
    // progress ring never stops animating — settling would wait forever.
    await tester.pump();

    expect(find.text('Галерея компонентов'), findsOneWidget);
    // One badge per level, which is the point of showing them together.
    expect(
      find.byType(AdminLogLevelBadge),
      findsNWidgets(AdminLogLevel.values.length),
    );
    expect(find.byType(AdminAppShell), findsOneWidget);
    expect(find.byType(AdminFilterBar), findsOneWidget);
    expect(find.byType(AdminResourceRow), findsWidgets);
  });

  testWidgets('the theme switch repaints the gallery', (tester) async {
    useLargeSurface(tester);
    await tester.pumpWidget(const GalleryApp());
    await tester.pump();

    await tester.tap(find.byType(ToggleSwitch));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Галерея компонентов'), findsOneWidget);
  });
}
