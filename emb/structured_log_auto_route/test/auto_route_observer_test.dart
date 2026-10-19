import 'dart:collection';
import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_auto_route/structured_log_auto_route.dart';

List<Map<String, dynamic>> captureEntries() {
  final entries = <Map<String, dynamic>>[];
  StructlogConfiguration.configure(
    sinks: [
      LogSink(
        name: 'capture',
        output: (entry, level) => entries.add(Map.of(entry)),
        minLevel: LogLevel.trace,
      ),
    ],
  );
  return entries;
}

List<String> eventsOf(List<Map<String, dynamic>> entries) => [
  for (final entry in entries) entry['event'] as String,
];

Widget page(String label) => Scaffold(body: Text(label));

AutoRoute route(String name, String path, {bool initial = false}) => AutoRoute(
  page: PageInfo.builder(name, builder: (_, _) => page(name)),
  path: path,
  initial: initial,
);

class TestRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    route('Home', '/', initial: true),
    route('User', '/user/:id'),
    route('Reset', '/reset/:token'),
    route('File', '/files/:name/:token'),
    route('Search', '/search'),
    AutoRoute(
      page: PageInfo('Shell', builder: (_) => const _Tabs()),
      path: '/shell',
      children: [route('A', 'a', initial: true), route('B', 'b')],
    ),
  ];
}

class _Tabs extends StatelessWidget {
  const _Tabs();

  @override
  Widget build(BuildContext context) => AutoTabsRouter(
    routes: const [PageRouteInfo('A'), PageRouteInfo('B')],
    builder: (context, child) => child,
  );
}

/// Pumps an app around a router whose navigator carries [observer].
Future<TestRouter> pumpRouter(
  WidgetTester tester,
  StructuredLogAutoRouteObserver observer,
) async {
  final router = TestRouter();
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router.config(navigatorObservers: () => [observer]),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

PageRouteInfo user(int id, {Map<String, dynamic> query = const {}}) =>
    PageRouteInfo('User', rawPathParams: {'id': id}, rawQueryParams: query);

void main() {
  late List<Map<String, dynamic>> entries;

  setUp(() => entries = captureEntries());
  tearDown(StructlogConfiguration.reset);

  group('events', () {
    testWidgets('a pushed screen is logged with its name, pattern and place', (
      tester,
    ) async {
      final router = await pumpRouter(tester, StructuredLogAutoRouteObserver());
      entries.clear();

      router.push(user(7));
      await tester.pumpAndSettle();

      expect(eventsOf(entries), ['route_pushed']);
      expect(
        entries.single,
        allOf(
          containsPair('category', 'navigation'),
          containsPair('logger', 'router'),
          containsPair('route', 'User'),
          containsPair('route_path', '/user/:id'),
          containsPair('location', '/user/7'),
          containsPair('previous_route', 'Home'),
          containsPair('previous_location', '/'),
        ),
      );
    });

    testWidgets('the screen shown first is logged without a previous one', (
      tester,
    ) async {
      await pumpRouter(tester, StructuredLogAutoRouteObserver());

      expect(entries.first, containsPair('event', 'route_pushed'));
      expect(entries.first, containsPair('route', 'Home'));
      expect(entries.first, containsPair('location', '/'));
      expect(entries.first, isNot(contains('previous_route')));
    });

    testWidgets('a popped screen names the one that shows again', (
      tester,
    ) async {
      final router = await pumpRouter(tester, StructuredLogAutoRouteObserver());
      router.push(user(7));
      await tester.pumpAndSettle();
      entries.clear();

      await router.maybePop();
      await tester.pumpAndSettle();

      expect(eventsOf(entries), ['route_popped']);
      expect(entries.single, containsPair('route', 'User'));
      expect(entries.single['location'], startsWith('/user/7'));
      expect(entries.single, containsPair('previous_route', 'Home'));
    });

    testWidgets('a replace is a push of the new screen and a removal', (
      tester,
    ) async {
      final router = await pumpRouter(tester, StructuredLogAutoRouteObserver());
      router.push(user(7));
      await tester.pumpAndSettle();
      entries.clear();

      router.replace(const PageRouteInfo('Search'));
      await tester.pumpAndSettle();

      expect(eventsOf(entries), ['route_pushed', 'route_removed']);
      expect(entries[0], containsPair('route', 'Search'));
      expect(entries[1], containsPair('route', 'User'));
    });

    testWidgets('a replacement the navigator reports is route_replaced', (
      tester,
    ) async {
      final observer = StructuredLogAutoRouteObserver();
      MaterialPageRoute<void> screen(String name) => MaterialPageRoute<void>(
        settings: RouteSettings(name: name),
        builder: (_) => page(name),
      );

      observer.didReplace(newRoute: screen('new'), oldRoute: screen('old'));
      observer.didReplace(oldRoute: screen('old'));

      expect(eventsOf(entries), ['route_replaced']);
      expect(entries.single, containsPair('route', 'new'));
      expect(entries.single, containsPair('previous_route', 'old'));
    });

    testWidgets('tabs are logged by index, and a return names the one left', (
      tester,
    ) async {
      final router = await pumpRouter(tester, StructuredLogAutoRouteObserver());
      entries.clear();

      router.navigate(const PageRouteInfo('Shell'));
      await tester.pumpAndSettle();
      final tabs = router.innerRouterOf<TabsRouter>('Shell')!;
      tabs.setActiveIndex(1);
      await tester.pumpAndSettle();
      tabs.setActiveIndex(0);
      await tester.pumpAndSettle();

      final tabEntries = [
        for (final entry in entries)
          if (entry['event'] == 'route_tab_changed') entry,
      ];
      expect(tabEntries, hasLength(3));
      expect(
        tabEntries[0],
        allOf(
          containsPair('route', 'A'),
          containsPair('tab_event', 'init'),
          containsPair('tab_index', 0),
        ),
      );
      // The first visit to a second tab is `init` on auto_route 11 and
      // `change` on 10; either way it is that tab, and it names where from.
      expect(tabEntries[1], containsPair('route', 'B'));
      expect(tabEntries[1], containsPair('tab_index', 1));
      expect(tabEntries[1], containsPair('previous_route', 'A'));
      expect(
        tabEntries[2],
        allOf(
          containsPair('route', 'A'),
          containsPair('tab_event', 'change'),
          containsPair('tab_index', 0),
          containsPair('previous_route', 'B'),
        ),
      );
    });

    testWidgets('a nested screen is located below its parents', (tester) async {
      final router = await pumpRouter(tester, StructuredLogAutoRouteObserver());
      entries.clear();

      router.navigate(
        const PageRouteInfo('Shell', initialChildren: [PageRouteInfo('B')]),
      );
      await tester.pumpAndSettle();

      expect(entries.first, containsPair('route', 'Shell'));
      expect(entries.first, containsPair('location', '/shell'));
    });

    testWidgets('a screen opened outside the router has no location', (
      tester,
    ) async {
      final router = await pumpRouter(tester, StructuredLogAutoRouteObserver());
      entries.clear();

      showDialog<void>(
        context: router.navigatorKey.currentContext!,
        routeSettings: const RouteSettings(name: 'confirm'),
        builder: (_) => const AlertDialog(title: Text('sure?')),
      );
      await tester.pumpAndSettle();
      showDialog<void>(
        context: router.navigatorKey.currentContext!,
        builder: (_) => const AlertDialog(title: Text('anonymous')),
      );
      await tester.pumpAndSettle();

      expect(eventsOf(entries), ['route_pushed', 'route_pushed']);
      expect(entries[0], containsPair('route', 'confirm'));
      expect(entries[1]['route'], contains('DialogRoute'));
      expect(entries[0], isNot(contains('location')));
      expect(entries[0], containsPair('previous_route', 'Home'));
    });
  });

  group('redaction', () {
    testWidgets('a token in the query is replaced, other parameters stay', (
      tester,
    ) async {
      final router = await pumpRouter(tester, StructuredLogAutoRouteObserver());
      entries.clear();

      router.push(user(7, query: {'token': 'abc', 'page': '2'}));
      await tester.pumpAndSettle();

      final location = entries.single['location'] as String;
      expect(location, startsWith('/user/7?'));
      expect(location, contains('token=REDACTED'));
      expect(location, contains('page=2'));
      expect(jsonEncode(entries.single), isNot(contains('abc')));
    });

    testWidgets('the name is matched without regard to case', (tester) async {
      final router = await pumpRouter(tester, StructuredLogAutoRouteObserver());
      entries.clear();

      router.push(user(7, query: {'Access_Token': 'abc'}));
      await tester.pumpAndSettle();

      expect(entries.single['location'], contains('Access_Token=REDACTED'));
    });

    testWidgets('a sensitive path parameter is replaced, its pattern is not', (
      tester,
    ) async {
      final router = await pumpRouter(tester, StructuredLogAutoRouteObserver());
      entries.clear();

      router.push(
        const PageRouteInfo('Reset', rawPathParams: {'token': 's3cr3t'}),
      );
      await tester.pumpAndSettle();

      expect(entries.single, containsPair('location', '/reset/REDACTED'));
      expect(entries.single, containsPair('route_path', '/reset/:token'));
      expect(jsonEncode(entries.single), isNot(contains('s3cr3t')));
      // And as the neighbour of the next screen.
      entries.clear();
      router.push(const PageRouteInfo('Search'));
      await tester.pumpAndSettle();
      expect(
        entries.single,
        containsPair('previous_location', '/reset/REDACTED'),
      );
    });

    testWidgets('an OAuth-style fragment is redacted like a query', (
      tester,
    ) async {
      final router = await pumpRouter(tester, StructuredLogAutoRouteObserver());
      entries.clear();

      router.push(
        PageRouteInfo('Search', fragment: 'access_token=abc&state=ok'),
      );
      await tester.pumpAndSettle();
      router.push(const PageRouteInfo('Search', fragment: 'top'));
      await tester.pumpAndSettle();
      router.push(const PageRouteInfo('Search', fragment: 'a=b'));
      await tester.pumpAndSettle();

      final locations = [for (final entry in entries) entry['location']];
      expect(locations[0], contains('#access_token=REDACTED&state=ok'));
      expect(locations[1], endsWith('#top'));
      expect(locations[2], endsWith('#a=b'));
      expect(jsonEncode(entries), isNot(contains('abc')));
    });

    testWidgets('a value that does not decode is kept as it is', (
      tester,
    ) async {
      final router = await pumpRouter(tester, StructuredLogAutoRouteObserver());
      entries.clear();

      router.push(
        const PageRouteInfo(
          'File',
          rawPathParams: {'name': '%zz', 'token': 's3cr3t'},
        ),
      );
      await tester.pumpAndSettle();

      expect(entries.single['location'], endsWith('/REDACTED'));
      expect(jsonEncode(entries.single), isNot(contains('s3cr3t')));
    });

    testWidgets('the names to redact can be replaced', (tester) async {
      final router = await pumpRouter(
        tester,
        StructuredLogAutoRouteObserver(redactedParameters: {'page'}),
      );
      entries.clear();

      router.push(user(7, query: {'token': 'abc', 'page': '2'}));
      await tester.pumpAndSettle();

      expect(entries.single['location'], contains('token=abc'));
      expect(entries.single['location'], contains('page=REDACTED'));
    });

    testWidgets('a neighbour is located by its path, not by a query that is '
        "the moving screen's", (tester) async {
      final router = await pumpRouter(tester, StructuredLogAutoRouteObserver());
      router.push(user(7, query: {'token': 'abc'}));
      await tester.pumpAndSettle();
      entries.clear();

      router.push(const PageRouteInfo('Search', rawQueryParams: {'q': 'dart'}));
      await tester.pumpAndSettle();

      expect(entries.single, containsPair('previous_location', '/user/7'));
      expect(entries.single['location'], contains('q=dart'));
    });
  });

  group('configuration', () {
    testWidgets('an event turned off writes nothing, the rest are written', (
      tester,
    ) async {
      final router = await pumpRouter(
        tester,
        StructuredLogAutoRouteObserver(
          levels: const RouteLogLevels(popped: null),
        ),
      );
      router.push(user(7));
      await tester.pumpAndSettle();
      entries.clear();

      await router.maybePop();
      await tester.pumpAndSettle();
      expect(entries, isEmpty);

      router.push(user(8));
      await tester.pumpAndSettle();
      expect(eventsOf(entries), ['route_pushed']);
    });

    testWidgets('the level of each event is its own', (tester) async {
      final router = await pumpRouter(
        tester,
        StructuredLogAutoRouteObserver(
          levels: const RouteLogLevels(pushed: LogLevel.debug),
        ),
      );
      entries.clear();

      router.push(user(7));
      await tester.pumpAndSettle();

      expect(entries.single, containsPair('level', 'debug'));
    });

    testWidgets('category and logger name can be changed or dropped', (
      tester,
    ) async {
      final router = await pumpRouter(
        tester,
        StructuredLogAutoRouteObserver(loggerName: 'nav', category: null),
      );
      entries.clear();

      router.push(user(7));
      await tester.pumpAndSettle();

      expect(entries.single, containsPair('logger', 'nav'));
      expect(entries.single, isNot(contains('category')));
    });

    testWidgets('a logger that is given is the one used', (tester) async {
      final own = <Map<String, dynamic>>[];
      final logger = BoundLogger(
        StructlogConfiguration(
          sinks: [
            LogSink(
              name: 'own',
              output: (entry, level) => own.add(Map.of(entry)),
              minLevel: LogLevel.trace,
            ),
          ],
        ),
      );
      final router = await pumpRouter(
        tester,
        StructuredLogAutoRouteObserver(logger: logger),
      );

      router.push(user(7));
      await tester.pumpAndSettle();

      expect(eventsOf(own), contains('route_pushed'));
      expect(entries, isEmpty);
    });

    testWidgets('a later configure reaches an observer made before it', (
      tester,
    ) async {
      final router = await pumpRouter(tester, StructuredLogAutoRouteObserver());
      final later = <Map<String, dynamic>>[];
      StructlogConfiguration.configure(
        sinks: [
          LogSink(
            name: 'later',
            output: (entry, level) => later.add(Map.of(entry)),
            minLevel: LogLevel.trace,
          ),
        ],
      );

      router.push(user(7));
      await tester.pumpAndSettle();

      expect(eventsOf(later), ['route_pushed']);
    });

    testWidgets('nothing is built for a level no sink takes', (tester) async {
      var filtered = 0;
      StructlogConfiguration.configure(
        sinks: [
          LogSink(
            name: 'errors',
            output: (entry, level) => entries.add(Map.of(entry)),
            minLevel: LogLevel.error,
          ),
        ],
      );
      final router = await pumpRouter(
        tester,
        StructuredLogAutoRouteObserver(
          filter: (_) {
            filtered++;
            return true;
          },
        ),
      );

      router.push(user(7));
      await tester.pumpAndSettle();

      expect(entries, isEmpty);
      expect(filtered, 0);
    });
  });

  group('filter', () {
    testWidgets('a rejected screen is left out, and as a neighbour too', (
      tester,
    ) async {
      final router = await pumpRouter(
        tester,
        StructuredLogAutoRouteObserver(filter: (route) => route.name != 'User'),
      );
      entries.clear();

      router.push(user(7));
      await tester.pumpAndSettle();
      expect(entries, isEmpty);

      router.push(const PageRouteInfo('Search'));
      await tester.pumpAndSettle();
      expect(eventsOf(entries), ['route_pushed']);
      expect(entries.single, containsPair('route', 'Search'));
      expect(entries.single, isNot(contains('previous_route')));
      expect(entries.single, isNot(contains('previous_location')));
    });

    testWidgets(
      'a filter that throws on a neighbour only drops the neighbour',
      (tester) async {
        final router = await pumpRouter(
          tester,
          StructuredLogAutoRouteObserver(
            filter: (route) =>
                route.name == 'Home' ? throw StateError('no') : true,
          ),
        );
        entries.clear();

        router.push(user(7));
        await tester.pumpAndSettle();

        expect(eventsOf(entries), ['route_pushed']);
        expect(entries.single, containsPair('route', 'User'));
        expect(entries.single, isNot(contains('previous_route')));
      },
    );

    testWidgets('a filter that throws costs the entry, not the navigation', (
      tester,
    ) async {
      final router = await pumpRouter(
        tester,
        StructuredLogAutoRouteObserver(filter: (_) => throw StateError('no')),
      );
      entries.clear();

      router.push(user(7));
      await tester.pumpAndSettle();

      expect(entries, isEmpty);
      expect(tester.takeException(), isNull);
      expect(find.text('User'), findsOneWidget);
    });
  });

  group('safety', () {
    testWidgets('a reader that throws leaves the route and its failure', (
      tester,
    ) async {
      final router = await pumpRouter(
        tester,
        StructuredLogAutoRouteObserver(redactedParameters: _ThrowingSet()),
      );
      entries.clear();

      router.push(user(7));
      await tester.pumpAndSettle();

      expect(entries.single, containsPair('route', 'User'));
      expect(entries.single, containsPair('route_failed', 'StateError'));
      expect(entries.single, isNot(contains('location')));
      expect(jsonEncode(entries.single), isNot(contains('no ')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a logger that throws does not reach the navigator', (
      tester,
    ) async {
      final router = await pumpRouter(
        tester,
        StructuredLogAutoRouteObserver(logger: _ThrowingLogger()),
      );

      router.push(user(7));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('User'), findsOneWidget);
    });
  });
}

/// A set whose lookups throw, standing in for whatever might go wrong while
/// a route is being read.
class _ThrowingSet extends SetBase<String> {
  @override
  bool contains(Object? value) => throw StateError('no reading today');

  @override
  bool add(String value) => false;

  @override
  Iterator<String> get iterator => const <String>[].iterator;

  @override
  int get length => 0;

  @override
  String? lookup(Object? object) => null;

  @override
  bool remove(Object? value) => false;

  @override
  Set<String> toSet() => this;
}

class _ThrowingLogger implements BoundLogger {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('no logging today');
}
