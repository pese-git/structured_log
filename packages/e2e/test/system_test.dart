import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_admin_client/features/log_browser/domain/log_browser_repository.dart';
import 'package:structured_log_admin_client/features/log_browser/domain/live_feed_event.dart';
import 'package:structured_log_admin_client/features/log_browser/domain/log_filter.dart';
import 'package:structured_log_admin_client/features/log_browser/domain/log_scope.dart';
import 'package:structured_log_admin_client/features/log_browser/infrastructure/log_browser_repository_impl.dart';
import 'package:structured_log_admin_client/features/log_browser/infrastructure/log_stream_client.dart';
import 'package:structured_log_admin_client/features/resources/domain/resources_repository.dart';
import 'package:structured_log_admin_client/features/resources/infrastructure/resources_repository_impl.dart';
import 'package:structured_log_admin_client/shared/api/api_client.dart';
import 'package:structured_log_admin_client/shared/api/api_failure.dart';
import 'package:structured_log_admin_client/shared/api/dto/auth_dto.dart';
import 'package:structured_log_admin_client/shared/auth/token_pair.dart';
import 'package:structured_log_admin_client/shared/auth/token_storage.dart';
import 'package:structured_log_admin_client/shared/config/app_config.dart';
import 'package:structured_log_http/structured_log_http.dart';

import 'harness.dart';

/// One system, from the call that logs a line to the screen that reads it
/// back.
///
/// Every other suite in this repository stops at a seam: the server's tests
/// build handlers, the client's tests answer HTTP from a fake adapter, and
/// the sender's tests talk to a stub socket. Both defects found on 2026-09-15
/// lived exactly in the seams those tests do not cross — a collection
/// envelope the client spelled one way and the server another, and a body
/// that streams on the VM and does not in a browser. This file crosses the
/// first kind; only a browser crosses the second, and that is written down as
/// not covered rather than pretended.
void main() {
  late ServerProcess server;
  late ApiClient api;
  late InMemoryTokenStorage storage;
  late ResourcesRepository resources;
  late LogBrowserRepository browser;

  /// Raised by the client's interceptor when the server refuses everything
  /// until the password is changed.
  var passwordChangeRequired = 0;

  const newPassword = 'chosen-by-the-operator';

  setUpAll(() async {
    StructlogConfiguration.configure(
      sinks: [LogSink(name: 'silent', output: (_, _) {})],
    );
    server = await ServerProcess.start();

    storage = InMemoryTokenStorage();
    api = ApiClient(
      config: AppConfig(baseUrl: server.baseUrl),
      storage: storage,
      onPasswordChangeRequired: () => passwordChangeRequired++,
    );
    resources = ResourcesRepositoryImpl(api);
    browser = LogBrowserRepositoryImpl(
      api,
      LogStreamClient(
        api.streamDio,
        logger: getLogger('e2e'),
        // The reconnect ladder is not what this file is testing, and a long
        // first wait would only make a failure slower to see.
        initialBackoff: const Duration(milliseconds: 50),
      ),
    );
  });

  tearDownAll(() async {
    await server.stop();
    StructlogConfiguration.reset();
  });

  /// Signs in and keeps the tokens where the interceptor will find them.
  Future<void> signIn(String password) async {
    final tokens = await api.auth.signIn('password', 'admin', password);
    await storage.write(
      TokenPair(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      ),
    );
  }

  // The tests below run in order and build on each other: this is one
  // deployment being set up, not five independent cases. `setUpAll` starts
  // the server once because starting it costs a `dart run` compile.

  test(
    'a fresh deployment refuses everything until the password changes',
    () async {
      await signIn(server.bootstrapPassword);

      final refused = await resources.groups();

      expect(
        refused.isLeft(),
        isTrue,
        reason: 'the generated password is temporary by construction',
      );
      refused.match(
        (failure) => expect(failure, isA<ForbiddenFailure>()),
        (_) => fail('the gate should have stopped this'),
      );
      expect(
        passwordChangeRequired,
        1,
        reason:
            'the screen learns about the gate from the network layer, not '
            'from the call site',
      );

      await api.auth.changePassword(
        ChangePasswordRequestDto(
          currentPassword: server.bootstrapPassword,
          newPassword: newPassword,
        ),
      );

      final allowed = await resources.groups();

      expect(
        allowed.isRight(),
        isTrue,
        reason:
            'the same request, once the password is no longer temporary — '
            'and through the same session, which the change does not end',
      );
    },
  );

  late int projectId;
  late String secretKey;

  test(
    'a group, a project and a key can be created through the client',
    () async {
      final group = (await resources.createGroup(
        'payments',
      )).getOrElse((failure) => fail('creating a group failed: $failure'));

      final project = (await resources.createProject(
        groupId: group.id,
        name: 'checkout',
        retentionDays: 30,
        maxEntries: 1000000,
      )).getOrElse((failure) => fail('creating a project failed: $failure'));
      projectId = project.id;

      final key = (await resources.createSecretKey(
        projectId: projectId,
        label: 'e2e',
      )).getOrElse((failure) => fail('creating a key failed: $failure'));
      secretKey = key.secret!;

      expect(secretKey, startsWith('slk_'));

      // The list is the shape that was wrong for a whole section: the server
      // wraps collections in `{"items": [...]}`, and a client expecting a bare
      // array reported the 200 as "the server is unreachable".
      final groups = (await resources.groups()).getOrElse((_) => []);
      expect(groups.map((g) => g.name), contains('payments'));

      final projects = (await resources.projectsOf(
        group.id,
      )).getOrElse((_) => []);
      expect(projects.map((p) => p.name), ['checkout']);

      final keys = (await resources.secretKeys(projectId)).getOrElse((_) => []);
      expect(keys.single.label, 'e2e');
      expect(
        keys.single.secret,
        isNull,
        reason: 'the value is answered once, at creation, and never again',
      );
    },
  );

  test('an entry logged by the library is read back by the client', () async {
    final output = HttpLogOutput(
      serverUrl: server.baseUrl,
      projectSecretKey: secretKey,
      // Small, so the test does not wait out a batching window.
      batchSize: 2,
      batchTimeout: const Duration(milliseconds: 200),
    );
    StructlogConfiguration.configure(
      sinks: [LogSink(name: 'server', output: output.call)],
    );

    getLogger('checkout.service')
        .bind({'service': 'checkout', 'deploy': 'e2e'})
        .withCorrelation(requestId: 'req-1')
        .error(
          'webhook_delivery_failed',
          context: {'attempt': 3, 'status_code': 504},
        );
    await output.flushed;

    final page = (await browser.query(
      scope: ProjectScope(id: projectId, name: 'checkout'),
      filter: const LogFilter(),
    )).getOrElse((failure) => fail('reading the logs back failed: $failure'));

    final entry = page.entries.single;
    expect(entry.event, 'webhook_delivery_failed');
    expect(entry.level, 'error');
    expect(entry.logger, 'checkout.service');
    expect(
      entry.requestId,
      'req-1',
      reason: 'correlation is a standard field, not part of the free context',
    );
    expect(
      entry.context,
      containsPair('attempt', 3),
      reason: 'whatever the application bound survives the whole trip',
    );
    expect(entry.context, containsPair('service', 'checkout'));
    expect(entry.context, containsPair('status_code', 504));
  });

  test('the live subscription delivers what is sent after it opens', () async {
    final page = (await browser.query(
      scope: ProjectScope(id: projectId, name: 'checkout'),
      filter: const LogFilter(),
    )).getOrElse((failure) => fail('reading the logs back failed: $failure'));
    final newestHeld = page.entries.first.id;

    final delivered = <String>[];
    final subscription = browser
        .watch(
          scope: ProjectScope(id: projectId, name: 'checkout'),
          filter: const LogFilter(),
          sinceId: newestHeld,
        )
        .listen((event) {
          if (event is LiveFeedEntry) delivered.add(event.entry.event);
        });
    addTearDown(subscription.cancel);

    // The subscription is opened asynchronously; nothing may be sent until
    // the server has it, or the entry would land in the `since_id` replay
    // instead and prove nothing about the live path.
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final output = HttpLogOutput(
      serverUrl: server.baseUrl,
      projectSecretKey: secretKey,
      batchSize: 1,
    );
    StructlogConfiguration.configure(
      sinks: [LogSink(name: 'server', output: output.call)],
    );
    getLogger('checkout.service').info('payment_authorized');
    await output.flushed;

    await _until(() => delivered.contains('payment_authorized'));

    expect(delivered, ['payment_authorized']);
  });

  test('a quota is changed through the client and read back', () async {
    final updated = (await resources.updateQuota(
      projectId: projectId,
      retentionDays: 7,
      maxEntries: null,
      maxBytes: 5 * 1024 * 1024,
    )).getOrElse((failure) => fail('updating the quota failed: $failure'));

    expect(updated.retentionDays, 7);
    expect(
      updated.maxEntries,
      isNull,
      reason:
          'an unlimited limit is sent as an explicit null, and the server '
          'distinguishes that from "leave it alone" by the key being there',
    );
    expect(updated.maxBytes, 5 * 1024 * 1024);

    final reread = (await resources.project(projectId)).getOrElse(
      (failure) => fail('reading the project back failed: $failure'),
    );
    expect(reread.retentionDays, 7);
    expect(reread.maxEntries, isNull);
    expect(
      reread.entryCount,
      greaterThan(0),
      reason: 'usage comes from this endpoint and nowhere else',
    );
  });

  test('a revoked key stops being accepted', () async {
    final keys = (await resources.secretKeys(projectId)).getOrElse((_) => []);

    final revoked = await resources.revokeSecretKey(
      projectId: projectId,
      keyId: keys.single.id,
    );
    expect(revoked.isRight(), isTrue);

    final rejected = <String>[];
    final output = HttpLogOutput(
      serverUrl: server.baseUrl,
      projectSecretKey: secretKey,
      batchSize: 1,
      // One attempt: a revoked key answers 401 forever, and retrying it would
      // only make the test slower.
      maxAttempts: 1,
      report: rejected.add,
    );
    StructlogConfiguration.configure(
      sinks: [LogSink(name: 'server', output: output.call)],
    );
    getLogger('checkout.service').info('after_revocation');
    await output.flushed;

    expect(
      rejected,
      isNotEmpty,
      reason:
          'the sender reports what it could not deliver rather than '
          'dropping it silently',
    );

    final page = (await browser.query(
      scope: ProjectScope(id: projectId, name: 'checkout'),
      filter: const LogFilter(),
    )).getOrElse((failure) => fail('reading the logs back failed: $failure'));
    expect(
      page.entries.map((e) => e.event),
      isNot(contains('after_revocation')),
    );
  });
}

/// Waits for something the server does on its own schedule.
Future<void> _until(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('the condition never became true', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
