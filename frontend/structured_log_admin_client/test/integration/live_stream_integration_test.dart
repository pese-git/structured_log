import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_admin_client/features/log_browser/domain/live_feed_event.dart';
import 'package:structured_log_admin_client/features/log_browser/domain/log_filter.dart';
import 'package:structured_log_admin_client/features/log_browser/domain/log_scope.dart';
import 'package:structured_log_admin_client/features/log_browser/infrastructure/log_stream_client.dart';
import 'package:structured_log_admin_client/shared/api/api_client.dart';
import 'package:structured_log_admin_client/shared/api/api_failure.dart';
import 'package:structured_log_admin_client/shared/auth/token_pair.dart';
import 'package:structured_log_admin_client/shared/auth/token_storage.dart';
import 'package:structured_log_admin_client/shared/config/app_config.dart';
import 'package:structured_log_admin_client/shared/logging/setup.dart';

import 'app_harness.dart';
import 'package:structured_log_admin_client/testing/mock_server.dart';

/// The live subscription against a real HTTP stack, one layer below the
/// screen.
///
/// `test`, not `testWidgets`, and that is not a preference. Reconnection is
/// the behaviour worth pinning here, and it cannot be driven under a widget
/// test's fake clock: the client leaves a finished connection by breaking out
/// of `await for`, which cancels an `async*` generator's subscription, and
/// that cancellation never completes under `fake_async` — the reconnect loop
/// simply stops there and no timer is left to advance it towards. A dropped
/// body, which ends the same loop without a cancel, reconnects under the fake
/// clock perfectly well, so this is the harness rather than the client: in
/// real async both paths reconnect, which is what these show.
///
/// It is the third such trap in this package, after a `Bloc` built in `setUp`
/// never processing events and `Bloc.close()` never completing — all three
/// are `testWidgets` and none is our code.
void main() {
  late MockServer server;
  late InMemoryTokenStorage storage;
  late ApiClient api;
  late LogStreamClient client;
  late int expired;

  setUp(() {
    server = MockServer();
    final issued = server.issueSession();
    storage = InMemoryTokenStorage(
      TokenPair(
        accessToken: issued.accessToken,
        refreshToken: issued.refreshToken,
      ),
    );
    expired = 0;
    api = ApiClient(
      config: const AppConfig(baseUrl: testBaseUrl),
      storage: storage,
      onSessionExpired: () => expired++,
      adapter: server,
    );
    client = LogStreamClient(
      api.streamDio,
      logger: configureClientLogging(),
      // Milliseconds rather than the shipped seconds: what is being tested is
      // that a reconnect happens and what it asks for, not how long the client
      // is willing to wait.
      initialBackoff: const Duration(milliseconds: 20),
      maxBackoff: const Duration(milliseconds: 60),
    );
  });

  /// Real time, because there is no fake clock here — long enough for a
  /// backoff and the request after it.
  Future<void> settle([int milliseconds = 120]) =>
      Future<void>.delayed(Duration(milliseconds: milliseconds));

  /// Subscribes, and makes sure the subscription is closed with the test.
  List<LiveFeedEvent> listen({int? sinceId}) {
    final events = <LiveFeedEvent>[];
    final subscription = client
        .connect(
          scope: const ProjectScope(id: 1, name: 'payments'),
          filter: const LogFilter(),
          sinceId: sinceId,
        )
        .listen(events.add);
    addTearDown(subscription.cancel);
    return events;
  }

  test('the subscription goes out with the session it shares', () async {
    listen(sinceId: 7);
    await settle();

    expect(server.streams, hasLength(1));
    expect(server.stream.sinceId, 7);
    expect(
      server.requests.last.bearer,
      isNotNull,
      reason:
          'the stream runs on its own Dio instance but carries the same '
          'interceptor object as the typed clients',
    );
  });

  test('a frame on the open body becomes an entry', () async {
    final events = listen();
    await settle();

    server.stream.keepAlive();
    server.stream.send(mockLogEntry(id: 42, event: 'Payment captured'));
    await settle(40);

    expect(events, hasLength(1));
    final event = events.single as LiveFeedEntry;
    expect(event.entry.id, 42);
    expect(event.entry.event, 'Payment captured');
  });

  test('a dropped body is reopened from the last entry delivered, and the '
      'reader is never told', () async {
    final events = listen();
    await settle();

    server.stream.send(mockLogEntry(id: 42));
    await settle(40);
    server.stream.drop();
    await settle();

    expect(server.streams, hasLength(2));
    expect(
      server.streams.last.sinceId,
      42,
      reason:
          'the server replays the gap, so a reconnect costs the reader '
          'nothing but a second',
    );
    expect(
      events.whereType<LiveFeedEnded>(),
      isEmpty,
      reason: 'a gap of a second is not something the screen has to say',
    );
  });

  test('a revoked token is reopened rather than reported', () async {
    final events = listen();
    await settle();

    server.stream.send(mockLogEntry(id: 42));
    await settle(40);
    server.stream.end('token_revoked');
    await settle();

    expect(server.streams, hasLength(2));
    expect(server.streams.last.sinceId, 42);
    expect(
      events.whereType<LiveFeedEnded>(),
      isEmpty,
      reason:
          'the new request is what gets a 401 the interceptor can refresh '
          'against — waiting for the server to hang up would not',
    );
  });

  test(
    'a reason a reconnect cannot settle ends the subscription for good',
    () async {
      final events = listen();
      await settle();

      server.stream.end('project_blocked');
      await settle();

      expect(
        events.whereType<LiveFeedEnded>().single.reason,
        'project_blocked',
      );
      expect(
        server.streams,
        hasLength(1),
        reason: 'a feed that stops visibly beats one that reconnects forever',
      );
    },
  );

  test('an aged-out token is renewed on the very interceptor the typed '
      'clients use', () async {
    // The guarantee is "one refresh in flight", and it lives in the
    // interceptor *instance*. Two instances — one for the typed clients, one
    // for the stream — would each spend the refresh token.
    server.expireAccessTokens();
    final events = listen();
    await settle();

    expect(
      server.requests.where(
        (request) =>
            request.path == '/v1/auth/token' &&
            request.form['grant_type'] == 'refresh_token',
      ),
      hasLength(1),
    );
    expect(
      server.streams,
      hasLength(1),
      reason: 'the refused request was replayed with the new token',
    );
    expect(events.whereType<LiveFeedFailed>(), isEmpty);
    expect(expired, 0);

    server.stream.send(mockLogEntry(id: 1));
    await settle(40);
    expect(events.whereType<LiveFeedEntry>(), hasLength(1));
  });

  test(
    'a refusal that is not about the session is reported, not retried',
    () async {
      server.script(
        'GET',
        '/v1/logs/stream',
        const MockReply(403, body: {'error': 'forbidden'}),
      );
      final events = listen();
      await settle();

      expect(
        events.whereType<LiveFeedFailed>().single.failure,
        isA<ForbiddenFailure>(),
      );
      expect(server.streams, isEmpty);
    },
  );

  test('a session that cannot be renewed ends rather than looping', () async {
    server
      ..expireAccessTokens()
      ..revokeRefreshTokens();
    final events = listen();
    await settle();

    expect(expired, 1);
    expect(await storage.read(), isNull);
    expect(events.whereType<LiveFeedFailed>(), hasLength(1));
    expect(
      server.streams,
      isEmpty,
      reason:
          'a 401 that reaches the client means the session is finished — '
          'asking again would get the same answer',
    );
  });
}
