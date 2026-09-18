import 'package:cherrypick/cherrypick.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';
import 'package:structured_log_admin_client/testing/mock_server.dart';

/// The log screen over a real HTTP stack, live half included.
///
/// This is the suite with the most to say, because the live subscription is
/// the one part of the client that no other test reaches end to end:
/// `log_stream_client_test.dart` parses frames out of a stream built by hand,
/// `log_feed_bloc_test.dart` drives a `StreamController` the repository
/// hands it, and neither goes through `dio`'s stream response, the
/// `Authorization` header, or the reconnect. Here a subscription is an actual
/// request with a body that stays open, and a frame is actual bytes.
///
/// One thing these still cannot see: the browser. `dio` on the web cannot
/// stream a response at all, which is why the live feed reads through `fetch`
/// (`shared/api/streaming/`), and the VM these run on never takes that path.
void main() {
  late MockServer server;

  setUp(() {
    server = MockServer();
    server.groups.add({
      'id': 7,
      'name': 'acme',
      'created_at': '2026-02-14T00:00:00.000Z',
    });
    server.projects.add({
      'id': 1,
      'group_id': 7,
      'name': 'payments',
      'retention_days': 30,
      'max_entries': null,
      'max_bytes': null,
      'is_blocked': false,
      'created_at': '2026-02-14T00:00:00.000Z',
      'entry_count': 0,
      'total_bytes': 0,
    });
    server.logEntries.add(
      mockLogEntry(
        id: 918273,
        event: 'Webhook delivery failed after 3 attempts',
        level: 'error',
        category: 'webhooks',
        requestId: 'req-9f2c',
        context: const {
          'webhook_url': 'https://example.test/hooks',
          'attempt': 3,
        },
      ),
    );
  });

  tearDown(CherryPick.closeRootScope);

  Iterable<RecordedRequest> logQueries() =>
      server.requests.where((request) => request.path == '/v1/logs');

  /// Opens the log section and picks the one project.
  Future<void> openFeed(WidgetTester tester) async {
    await openLogs(tester);
    await tester.tap(find.text('payments'));
    await tester.pumpAndSettle();
  }

  testWidgets('the selector stands in place of the list, and queries nothing', (
    tester,
  ) async {
    await pumpApp(tester, server, signedIn: true);
    await openLogs(tester);

    expect(find.text('Выберите область'), findsOneWidget);
    expect(find.text('payments'), findsOneWidget);
    expect(find.text('acme'), findsOneWidget);
    expect(logQueries(), isEmpty);
    await closeApp(tester);
  });

  testWidgets('"Open logs" on a project opens that project\'s logs, not the '
      'selector', (tester) async {
    await pumpApp(tester, server, signedIn: true);

    // Groups → the group → its project → the project's own "Open logs".
    await tester.tap(find.text('Открыть').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть логи'));
    await tester.pumpAndSettle();

    expect(find.text('Выберите область'), findsNothing);
    expect(find.text('Проект: payments'), findsOneWidget);
    expect(logQueries().single.query['project_id'], '1');
    await closeApp(tester);
  });

  testWidgets('choosing a scope queries one project and shows what came back', (
    tester,
  ) async {
    await pumpApp(tester, server, signedIn: true);
    await openFeed(tester);

    final query = logQueries().single.query;
    expect(query['project_id'], '1');
    expect(
      query.containsKey('group_id'),
      isFalse,
      reason: 'exactly one scope per query — never both, never an aggregate',
    );
    expect(
      find.text('Webhook delivery failed after 3 attempts'),
      findsOneWidget,
    );
    expect(find.text('ERR'), findsOneWidget);
    expect(find.text('Проект: payments'), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('an entry keeps its arbitrary fields apart from its own', (
    tester,
  ) async {
    await pumpApp(tester, server, signedIn: true);
    await openFeed(tester);

    await tester.tap(find.text('Webhook delivery failed after 3 attempts'));
    await tester.pumpAndSettle();

    expect(find.text('СТАНДАРТНЫЕ ПОЛЯ'), findsOneWidget);
    expect(find.text('КОНТЕКСТ'), findsOneWidget);
    // The server spreads the context across the top level of the object, so
    // this split happens in the client and nowhere else: correlation is a
    // standard field, whatever the application bound is context.
    expect(find.text('request_id'), findsOneWidget);
    expect(find.text('webhook_url'), findsOneWidget);
    expect(find.text('attempt'), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('the subscription is opened from the newest entry on the page, '
      'with the filters the page was loaded with', (tester) async {
    await pumpApp(tester, server, signedIn: true);
    await openFeed(tester);

    expect(server.streams, hasLength(1));
    expect(
      server.stream.sinceId,
      918273,
      reason:
          'the server replays what landed between the page and the '
          'subscription, so the gap loses nothing and repeats nothing',
    );
    expect(server.stream.query['project_id'], '1');
    expect(
      server.stream.query.containsKey('cursor'),
      isFalse,
      reason: 'paging belongs to the list, not to the subscription',
    );
    await closeApp(tester);
  });

  testWidgets('a frame delivered on the open body lands at the end of the '
      'feed', (tester) async {
    await pumpApp(tester, server, signedIn: true);
    await openFeed(tester);

    // A keep-alive first: it carries no field and a client that mistook it
    // for a frame would break on the very next one.
    server.stream.keepAlive();
    server.stream.send(
      mockLogEntry(id: 918274, event: 'Payment captured', level: 'info'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Payment captured'), findsOneWidget);
    expect(find.text('В реальном времени'), findsOneWidget);
    expect(
      find.text('Лента в реальном времени — новые записи появляются снизу'),
      findsOneWidget,
    );
    await closeApp(tester);
  });

  testWidgets('a replayed entry the page already holds is not shown twice', (
    tester,
  ) async {
    await pumpApp(tester, server, signedIn: true);
    await openFeed(tester);

    // What the catch-up replay after a reconnect looks like: the server
    // resends from `since_id`, inclusive of what is already held.
    server.stream.send(server.logEntries.single);
    await tester.pumpAndSettle();

    expect(
      find.text('Webhook delivery failed after 3 attempts'),
      findsOneWidget,
    );
    await closeApp(tester);
  });

  testWidgets('pausing banks what arrives, and resuming lets it through', (
    tester,
  ) async {
    await pumpApp(tester, server, signedIn: true);
    await openFeed(tester);

    await tester.tap(find.text('Пауза'));
    await tester.pumpAndSettle();
    server.stream.send(
      mockLogEntry(id: 918274, event: 'Payment captured', level: 'info'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Payment captured'), findsNothing);
    expect(find.text('На паузе'), findsOneWidget);
    expect(find.textContaining('накоплено 1'), findsOneWidget);

    // Two of them: the toolbar's, and the status strip's below the feed.
    await tester.tap(find.text('Возобновить').first);
    await tester.pumpAndSettle();

    expect(find.text('Payment captured'), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('a subscription the server ends for good stops the feed and '
      'says why', (tester) async {
    await pumpApp(tester, server, signedIn: true);
    await openFeed(tester);

    server.stream.end('project_blocked');
    await tester.pumpAndSettle();

    expect(find.text('Живая трансляция остановлена'), findsOneWidget);
    expect(find.textContaining('Проект заблокирован'), findsOneWidget);
    expect(
      server.streams,
      hasLength(1),
      reason: 'a reason the client cannot settle by reconnecting is final',
    );
    await closeApp(tester);
  });

  // The reconnect after a body the server closed is covered in
  // `live_stream_integration_test.dart` instead: leaving a finished
  // connection cancels an `async*` subscription, and that cancellation never
  // completes under a widget test's fake clock. It is the harness, not the
  // client — see that file.

  testWidgets('a search and a level go out on the list and on the new '
      'subscription alike', (tester) async {
    await pumpApp(tester, server, signedIn: true);
    await openFeed(tester);

    await tester.enterText(find.byType(TextBox).first, 'webhook');
    // The chip cycles: "Любой уровень" → the first floor below it.
    await tester.tap(find.text('Любой уровень'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Найти'));
    await tester.pumpAndSettle();

    final listed = logQueries().last.query;
    expect(listed['q'], 'webhook');
    expect(listed['level'], isNotNull);
    expect(
      server.stream.query['q'],
      listed['q'],
      reason:
          'a stream narrower or wider than the list would deliver entries '
          'the list would never have shown, or drop ones it would',
    );
    expect(server.stream.query['level'], listed['level']);
    await closeApp(tester);
  });

  testWidgets('reaching the far end of the feed asks for the page before it', (
    tester,
  ) async {
    server.logEntries.clear();
    for (var id = 1; id <= 60; id++) {
      server.logEntries.add(mockLogEntry(id: id, event: 'Entry $id'));
    }

    await pumpApp(tester, server, signedIn: true);
    await openFeed(tester);
    expect(logQueries().single.query.containsKey('cursor'), isFalse);

    // The far end of a reversed list is the oldest entry held, and reaching
    // it is the request for the page before it. Driven through the position
    // rather than a fling so the test is about the request, not about how
    // hard someone swiped.
    final feed = find.descendant(
      // The feed's own list: the only reversed one on the screen.
      of: find.byWidgetPredicate(
        (widget) => widget is ListView && widget.reverse,
      ),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(feed).position;
    final heldBefore = position.maxScrollExtent;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();

    final paged = logQueries().last;
    expect(
      paged.query['cursor'],
      '11',
      reason:
          'the first page is the newest 50 of 60, so the cursor walks back '
          'from its oldest entry',
    );
    expect(
      tester.state<ScrollableState>(feed).position.maxScrollExtent,
      greaterThan(heldBefore),
      reason:
          'the older page is prepended at the far end, so the list grows '
          'without moving what the reader was looking at',
    );
    await closeApp(tester);
  });
}
