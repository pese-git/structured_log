import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_client/features/log_browser/domain/log_scope.dart';
import 'package:structured_log_admin_client/features/log_browser/presentation/scope_selector.dart';

import '../../support/localized_app.dart';

Widget _host(ScopeSelector selector) =>
    localizedApp(home: ScaffoldPage(content: selector));

void main() {
  const groups = [GroupScope(id: 1, name: 'acme')];
  const projects = [ProjectScope(id: 2, name: 'payments')];

  testWidgets('says there is more only while the server has more', (
    tester,
  ) async {
    final asked = <bool>[];
    await tester.pumpWidget(
      _host(
        ScopeSelector(
          options: const ScopeOptions(
            groups: groups,
            projects: projects,
            groupsCursor: '1',
          ),
          onSelected: (_) {},
          onShowMore: asked.add,
        ),
      ),
    );

    expect(
      find.text('Показать ещё'),
      findsOneWidget,
      reason: 'only the groups list has a cursor, so only it can be extended',
    );

    await tester.tap(find.text('Показать ещё'));
    await tester.pumpAndSettle();
    expect(asked, [true], reason: 'true names the groups list');
  });

  testWidgets('a list that is complete offers nothing to extend', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ScopeSelector(
          options: const ScopeOptions(groups: groups, projects: projects),
          onSelected: (_) {},
          onShowMore: (_) {},
        ),
      ),
    );

    expect(find.text('Показать ещё'), findsNothing);
  });

  testWidgets('a full page of groups and projects scrolls instead of '
      'overflowing the window', (tester) async {
    // The server serves fifty of each: two hundred pixels of tiles per ten
    // names is far past a 600-pixel window, and a column that does not scroll
    // paints the overflow stripes over the rest of the screen.
    tester.view.physicalSize = const Size(1000, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _host(
        ScopeSelector(
          options: ScopeOptions(
            groups: [
              for (var i = 0; i < 50; i++) GroupScope(id: i, name: 'group-$i'),
            ],
            projects: [
              for (var i = 0; i < 50; i++)
                ProjectScope(id: 100 + i, name: 'project-$i'),
            ],
            groupsCursor: '1',
          ),
          onSelected: (_) {},
          onShowMore: (_) {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text('Показать ещё'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Показать ещё'), findsOneWidget);
  });
}
