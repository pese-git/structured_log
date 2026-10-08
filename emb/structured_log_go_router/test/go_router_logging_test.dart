import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_go_router/structured_log_go_router.dart';

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

List<RouteBase> routes() => [
  GoRoute(
    path: '/',
    name: 'home',
    builder: (_, __) => page('home'),
    routes: [
      GoRoute(
        path: 'users/:id',
        name: 'user',
        builder: (_, state) => page('user ${state.pathParameters['id']}'),
      ),
      GoRoute(path: 'settings', builder: (_, __) => page('settings')),
    ],
  ),
  GoRoute(path: '/login', builder: (_, __) => page('login')),
];

/// Pumps an app around [router] and waits for it to settle.
Future<void> pumpRouter(WidgetTester tester, GoRouter router) async {
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
}

void main() {
  late List<Map<String, dynamic>> entries;

  setUp(() => entries = captureEntries());
  tearDown(StructlogConfiguration.reset);

  group('route_changed', () {
    testWidgets('logs the initial location and each navigation', (
      tester,
    ) async {
      final routeLog = StructuredLogGoRouter();
      final router = GoRouter(routes: routes());
      addTearDown(router.dispose);
      await pumpRouter(tester, router);
      routeLog.attach(router);
      addTearDown(routeLog.detach);

      router.go('/users/42');
      await tester.pumpAndSettle();

      expect(eventsOf(entries), ['route_changed', 'route_changed']);
      final [initial, user] = entries;
      expect(initial, containsPair('location', '/'));
      expect(initial, containsPair('route_name', 'home'));
      expect(initial.keys, isNot(contains('previous_location')));
      expect(user, containsPair('location', '/users/42'));
      expect(user, containsPair('route', '/users/:id'));
      expect(user, containsPair('route_name', 'user'));
      expect(user, containsPair('previous_location', '/'));
      expect(user, containsPair('previous_route', '/'));
      expect(user, containsPair('category', 'navigation'));
      expect(user, containsPair('logger', 'router'));
      expect(user, containsPair('level', 'info'));
    });

    testWidgets('a push and a pop are navigations too', (tester) async {
      final routeLog = StructuredLogGoRouter();
      final router = GoRouter(routes: routes());
      addTearDown(router.dispose);
      await pumpRouter(tester, router);
      routeLog.attach(router);
      addTearDown(routeLog.detach);

      router.push('/settings');
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();

      final locations = [for (final e in entries) e['location']];
      expect(locations, ['/', '/settings', '/']);
      expect(entries.last, containsPair('previous_location', '/settings'));
    });

    testWidgets('going to the same location again is not a new entry', (
      tester,
    ) async {
      final routeLog = StructuredLogGoRouter();
      final router = GoRouter(routes: routes());
      addTearDown(router.dispose);
      await pumpRouter(tester, router);
      routeLog.attach(router);
      addTearDown(routeLog.detach);

      router.go('/');
      await tester.pumpAndSettle();

      expect(eventsOf(entries), ['route_changed']);
    });

    testWidgets('a notification without a new location is not an entry', (
      tester,
    ) async {
      final routeLog = StructuredLogGoRouter();
      final router = GoRouter(routes: routes());
      addTearDown(router.dispose);
      await pumpRouter(tester, router);
      routeLog.attach(router);
      addTearDown(routeLog.detach);

      // The delegate is a ChangeNotifier and is free to notify for reasons
      // other than a new location; go_router itself skips an unchanged one,
      // so the only way to exercise that path is to notify directly.
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      router.routerDelegate.notifyListeners();
      await tester.pumpAndSettle();

      expect(eventsOf(entries), ['route_changed']);
    });

    testWidgets('attaching before the first frame logs the first location', (
      tester,
    ) async {
      final routeLog = StructuredLogGoRouter();
      final router = GoRouter(routes: routes(), initialLocation: '/settings');
      addTearDown(router.dispose);
      routeLog.attach(router);
      addTearDown(routeLog.detach);
      await pumpRouter(tester, router);

      expect(eventsOf(entries), ['route_changed']);
      expect(entries.single, containsPair('location', '/settings'));
    });

    testWidgets('detach stops logging, and attach moves to another router', (
      tester,
    ) async {
      final routeLog = StructuredLogGoRouter();
      final first = GoRouter(routes: routes());
      addTearDown(first.dispose);
      await pumpRouter(tester, first);
      routeLog.attach(first);

      routeLog.detach();
      first.go('/settings');
      await tester.pumpAndSettle();
      expect(entries, hasLength(1));

      final second = GoRouter(routes: routes(), initialLocation: '/login');
      addTearDown(second.dispose);
      await pumpRouter(tester, second);
      routeLog.attach(second);
      addTearDown(routeLog.detach);

      expect(entries.last, containsPair('location', '/login'));
      expect(entries.last.keys, isNot(contains('previous_location')));
    });

    testWidgets('filter keeps navigations it rejects out of the log', (
      tester,
    ) async {
      final routeLog = StructuredLogGoRouter(
        filter: (state) => state.fullPath != '/settings',
      );
      final router = GoRouter(routes: routes());
      addTearDown(router.dispose);
      await pumpRouter(tester, router);
      routeLog.attach(router);
      addTearDown(routeLog.detach);

      router.go('/settings');
      await tester.pumpAndSettle();
      router.go('/login');
      await tester.pumpAndSettle();

      expect([for (final e in entries) e['location']], ['/', '/login']);
      // The skipped navigation still counts as where the user came from —
      // by its route, which names no parameters, not by its location,
      // which may be exactly what the filter was meant to keep out.
      expect(entries.last, containsPair('previous_route', '/settings'));
      expect(entries.last.keys, isNot(contains('previous_location')));
    });

    testWidgets('a filtered location appears in no later entry', (
      tester,
    ) async {
      final routeLog = StructuredLogGoRouter(
        filter: (state) => state.fullPath != '/users/:id',
      );
      final router = GoRouter(routes: routes());
      addTearDown(router.dispose);
      await pumpRouter(tester, router);
      routeLog.attach(router);
      addTearDown(routeLog.detach);

      router.go('/users/alice@example.com');
      await tester.pumpAndSettle();
      router.go('/login');
      await tester.pumpAndSettle();

      expect(jsonEncode(entries), isNot(contains('alice')));
      expect(entries.last, containsPair('previous_route', '/users/:id'));
    });
  });

  group('redaction', () {
    testWidgets('token-like query parameters are replaced', (tester) async {
      final routeLog = StructuredLogGoRouter();
      final router = GoRouter(routes: routes());
      addTearDown(router.dispose);
      await pumpRouter(tester, router);
      routeLog.attach(router);
      addTearDown(routeLog.detach);

      router.go('/login?Token=abc&next=%2Fhome&code=x1&code=x2');
      await tester.pumpAndSettle();

      final location = Uri.parse(entries.last['location'] as String);
      expect(location.queryParametersAll, {
        'Token': ['REDACTED'],
        'next': ['/home'],
        'code': ['REDACTED', 'REDACTED'],
      });
      expect(jsonEncode(entries), isNot(contains('abc')));
    });

    testWidgets('a fragment shaped like a query is redacted too', (
      tester,
    ) async {
      final routeLog = StructuredLogGoRouter();
      final router = GoRouter(routes: routes());
      addTearDown(router.dispose);
      await pumpRouter(tester, router);
      routeLog.attach(router);
      addTearDown(routeLog.detach);

      router.go('/login#access_token=secret&state=s');
      await tester.pumpAndSettle();

      final location = Uri.parse(entries.last['location'] as String);
      expect(Uri.splitQueryString(location.fragment), {
        'access_token': 'REDACTED',
        'state': 's',
      });
      expect(jsonEncode(entries), isNot(contains('secret')));
    });

    testWidgets('a plain fragment and a clean query are left alone', (
      tester,
    ) async {
      final routeLog = StructuredLogGoRouter();
      final router = GoRouter(routes: routes());
      addTearDown(router.dispose);
      await pumpRouter(tester, router);
      routeLog.attach(router);
      addTearDown(routeLog.detach);

      router.go('/settings?tab=privacy#section-2');
      await tester.pumpAndSettle();

      expect(
        entries.last,
        containsPair('location', '/settings?tab=privacy#section-2'),
      );
    });

    testWidgets('the redaction set can be replaced', (tester) async {
      final routeLog = StructuredLogGoRouter(redactedQueryParameters: {'tab'});
      final router = GoRouter(routes: routes());
      addTearDown(router.dispose);
      await pumpRouter(tester, router);
      routeLog.attach(router);
      addTearDown(routeLog.detach);

      router.go('/settings?tab=privacy&token=t');
      await tester.pumpAndSettle();

      expect(
        entries.last,
        containsPair('location', '/settings?tab=REDACTED&token=t'),
      );
    });
  });

  group('route_redirected', () {
    testWidgets('a synchronous redirect is logged and still applied', (
      tester,
    ) async {
      final routeLog = StructuredLogGoRouter();
      final router = GoRouter(
        routes: routes(),
        redirect: routeLog.redirect(
          (context, state) =>
              state.uri.path == '/settings' ? '/login?token=t' : null,
        ),
      );
      addTearDown(router.dispose);
      await pumpRouter(tester, router);
      routeLog.attach(router);
      addTearDown(routeLog.detach);

      router.go('/settings');
      await tester.pumpAndSettle();

      expect(find.text('login'), findsOneWidget);
      final redirected = entries.singleWhere(
        (e) => e['event'] == 'route_redirected',
      );
      expect(redirected, containsPair('from', '/settings'));
      expect(redirected, containsPair('to', '/login?token=REDACTED'));
      expect(redirected, containsPair('level', 'debug'));
      expect(entries.last, containsPair('location', '/login?token=REDACTED'));
    });

    testWidgets('a redirect from a filtered location is not logged', (
      tester,
    ) async {
      final routeLog = StructuredLogGoRouter(
        filter: (state) => state.fullPath != '/users/:id',
      );
      final router = GoRouter(
        routes: routes(),
        redirect: routeLog.redirect(
          (context, state) => state.fullPath == '/users/:id' ? '/login' : null,
        ),
      );
      addTearDown(router.dispose);
      await pumpRouter(tester, router);
      routeLog.attach(router);
      addTearDown(routeLog.detach);

      router.go('/users/alice@example.com');
      await tester.pumpAndSettle();

      expect(find.text('login'), findsOneWidget);
      expect(entries.where((e) => e['event'] == 'route_redirected'), isEmpty);
      expect(jsonEncode(entries), isNot(contains('alice')));
    });

    testWidgets('a redirect to a filtered location names its route only', (
      tester,
    ) async {
      final routeLog = StructuredLogGoRouter(
        filter: (state) => state.fullPath != '/users/:id',
      );
      final router = GoRouter(
        routes: routes(),
        redirect: routeLog.redirect(
          (context, state) =>
              state.uri.path == '/login' ? '/users/alice@example.com' : null,
        ),
      );
      addTearDown(router.dispose);
      await pumpRouter(tester, router);
      routeLog.attach(router);
      addTearDown(routeLog.detach);

      router.go('/login');
      await tester.pumpAndSettle();

      final redirected = entries.singleWhere(
        (e) => e['event'] == 'route_redirected',
      );
      expect(redirected, containsPair('from', '/login'));
      expect(redirected, containsPair('to_route', '/users/:id'));
      expect(redirected.keys, isNot(contains('to')));
      expect(jsonEncode(entries), isNot(contains('alice')));
    });

    testWidgets('a redirect to a location the filter accepts keeps its to', (
      tester,
    ) async {
      final routeLog = StructuredLogGoRouter(
        filter: (state) => state.fullPath != '/users/:id',
      );
      final router = GoRouter(
        routes: routes(),
        redirect: routeLog.redirect(
          (context, state) => state.uri.path == '/settings' ? '/login' : null,
        ),
      );
      addTearDown(router.dispose);
      await pumpRouter(tester, router);
      routeLog.attach(router);
      addTearDown(routeLog.detach);

      router.go('/settings');
      await tester.pumpAndSettle();

      final redirected = entries.singleWhere(
        (e) => e['event'] == 'route_redirected',
      );
      expect(redirected, containsPair('to', '/login'));
      expect(redirected.keys, isNot(contains('to_route')));
    });

    testWidgets('with a filter and no router attached, to is withheld', (
      tester,
    ) async {
      final routeLog = StructuredLogGoRouter(filter: (_) => true);
      final router = GoRouter(
        routes: routes(),
        redirect: routeLog.redirect(
          (context, state) => state.uri.path == '/settings' ? '/login' : null,
        ),
      );
      addTearDown(router.dispose);
      await pumpRouter(tester, router);

      router.go('/settings');
      await tester.pumpAndSettle();

      final redirected = entries.singleWhere(
        (e) => e['event'] == 'route_redirected',
      );
      expect(redirected, containsPair('from', '/settings'));
      expect(redirected.keys, isNot(contains('to')));
    });

    testWidgets('an asynchronous redirect is logged and still applied', (
      tester,
    ) async {
      final routeLog = StructuredLogGoRouter();
      final router = GoRouter(
        routes: routes(),
        redirect: routeLog.redirect((context, state) async {
          await Future<void>.delayed(Duration.zero);
          return state.uri.path == '/settings' ? '/login' : null;
        }),
      );
      addTearDown(router.dispose);
      await pumpRouter(tester, router);
      routeLog.attach(router);
      addTearDown(routeLog.detach);

      router.go('/settings');
      await tester.pumpAndSettle();

      expect(find.text('login'), findsOneWidget);
      expect(entries.where((e) => e['event'] == 'route_redirected'), [
        containsPair('to', '/login'),
      ]);
    });

    testWidgets('no redirect, or one to the same place, is not logged', (
      tester,
    ) async {
      final routeLog = StructuredLogGoRouter();
      final router = GoRouter(
        routes: routes(),
        redirect: routeLog.redirect((context, state) => state.uri.toString()),
      );
      addTearDown(router.dispose);
      await pumpRouter(tester, router);

      expect(entries.where((e) => e['event'] == 'route_redirected'), isEmpty);
    });

    testWidgets('a redirect that throws reaches the caller unchanged', (
      tester,
    ) async {
      // A real context and state, captured from a router mid-redirect, so
      // that the only thing that can throw below is the wrapped redirect.
      late BuildContext context;
      late GoRouterState state;
      final router = GoRouter(
        routes: routes(),
        redirect: (c, s) {
          context = c;
          state = s;
          return null;
        },
      );
      addTearDown(router.dispose);
      await pumpRouter(tester, router);

      final wrapped = StructuredLogGoRouter().redirect(
        (_, __) => throw StateError('broke'),
      );
      expect(
        () => wrapped(context, state),
        throwsA(isA<StateError>().having((e) => e.message, 'message', 'broke')),
      );
      expect(entries, isEmpty);
    });
  });

  group('route_error', () {
    testWidgets('an unknown location shown on the error page is logged', (
      tester,
    ) async {
      final routeLog = StructuredLogGoRouter();
      final router = GoRouter(
        routes: routes(),
        errorBuilder: (_, __) => page('not found'),
      );
      addTearDown(router.dispose);
      await pumpRouter(tester, router);
      routeLog.attach(router);
      addTearDown(routeLog.detach);

      router.go('/nowhere?token=t');
      await tester.pumpAndSettle();

      final error = entries.last;
      expect(error, containsPair('event', 'route_error'));
      expect(error, containsPair('level', 'warning'));
      expect(error, containsPair('location', '/nowhere?token=REDACTED'));
      expect(error['error'], contains('/nowhere?token=REDACTED'));
      expect(error['error'], isNot(contains('token=t')));
    });

    testWidgets('the locations a redirect loop names are redacted too', (
      tester,
    ) async {
      final routeLog = StructuredLogGoRouter();
      final router = GoRouter(
        routes: routes(),
        redirect: (_, state) => switch (state.uri.path) {
          '/settings' => '/login?token=t',
          '/login' => '/settings?token=t',
          _ => null,
        },
        errorBuilder: (_, __) => page('not found'),
      );
      addTearDown(router.dispose);
      await pumpRouter(tester, router);
      routeLog.attach(router);
      addTearDown(routeLog.detach);

      router.go('/settings?token=t');
      await tester.pumpAndSettle();

      final error = entries.last;
      expect(error, containsPair('event', 'route_error'));
      expect(error['error'], contains('redirect loop'));
      expect(error['error'], contains('token=REDACTED'));
      expect(error['error'], isNot(contains('token=t')));
    });

    testWidgets('an error handled by onException is logged through the '
        'wrapper, and the handler still runs', (tester) async {
      final routeLog = StructuredLogGoRouter();
      var handled = false;
      final router = GoRouter(
        routes: routes(),
        onException: routeLog.onException((context, state, router) {
          handled = true;
          router.go('/');
        }),
      );
      addTearDown(router.dispose);
      await pumpRouter(tester, router);
      routeLog.attach(router);
      addTearDown(routeLog.detach);

      router.go('/nowhere');
      await tester.pumpAndSettle();

      expect(handled, isTrue);
      expect(entries.where((e) => e['event'] == 'route_error'), [
        containsPair('location', '/nowhere'),
      ]);
    });
  });

  group('configuration', () {
    testWidgets('a null level turns that entry off', (tester) async {
      final routeLog = StructuredLogGoRouter(
        levels: const RouteLogLevels(navigation: null),
      );
      final router = GoRouter(routes: routes());
      addTearDown(router.dispose);
      await pumpRouter(tester, router);
      routeLog.attach(router);
      addTearDown(routeLog.detach);

      router.go('/settings');
      await tester.pumpAndSettle();

      expect(entries, isEmpty);
    });

    testWidgets('a given logger and category replace the defaults', (
      tester,
    ) async {
      final routeLog = StructuredLogGoRouter(
        logger: getLogger('app').bind({'screen_set': 'main'}),
        category: 'ui',
      );
      final router = GoRouter(routes: routes());
      addTearDown(router.dispose);
      await pumpRouter(tester, router);
      routeLog.attach(router);
      addTearDown(routeLog.detach);

      expect(entries.single, containsPair('logger', 'app'));
      expect(entries.single, containsPair('screen_set', 'main'));
      expect(entries.single, containsPair('category', 'ui'));
    });

    testWidgets('a null category keeps the one the logger carries', (
      tester,
    ) async {
      final routeLog = StructuredLogGoRouter(
        logger: getLogger().bind({'category': 'mine'}),
        category: null,
      );
      final router = GoRouter(routes: routes());
      addTearDown(router.dispose);
      await pumpRouter(tester, router);
      routeLog.attach(router);
      addTearDown(routeLog.detach);

      expect(entries.single, containsPair('category', 'mine'));
    });

    testWidgets('a later configure() reaches a logger built without one', (
      tester,
    ) async {
      final routeLog = StructuredLogGoRouter();
      final router = GoRouter(routes: routes());
      addTearDown(router.dispose);
      await pumpRouter(tester, router);
      final later = captureEntries();
      routeLog.attach(router);
      addTearDown(routeLog.detach);

      expect(entries, isEmpty);
      expect(eventsOf(later), ['route_changed']);
    });
  });

  group('never breaks navigation', () {
    testWidgets('a throwing filter costs the entry, not the navigation', (
      tester,
    ) async {
      final routeLog = StructuredLogGoRouter(
        filter: (_) => throw StateError('no'),
      );
      final router = GoRouter(routes: routes());
      addTearDown(router.dispose);
      await pumpRouter(tester, router);
      routeLog.attach(router);
      addTearDown(routeLog.detach);

      router.go('/settings');
      await tester.pumpAndSettle();

      expect(find.text('settings'), findsOneWidget);
      expect(entries, isEmpty);
    });

    testWidgets('every entry survives jsonEncode', (tester) async {
      final routeLog = StructuredLogGoRouter();
      final router = GoRouter(
        routes: routes(),
        redirect: routeLog.redirect(
          (_, state) => state.uri.path == '/settings' ? '/login' : null,
        ),
        errorBuilder: (_, __) => page('not found'),
      );
      addTearDown(router.dispose);
      await pumpRouter(tester, router);
      routeLog.attach(router);
      addTearDown(routeLog.detach);

      router.go('/settings');
      await tester.pumpAndSettle();
      router.go('/nowhere');
      await tester.pumpAndSettle();

      expect(eventsOf(entries).toSet(), {
        'route_changed',
        'route_redirected',
        'route_error',
      });
      expect(() => jsonEncode(entries), returnsNormally);
    });
  });
}
