import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_admin_client/features/log_browser/domain/log_filter.dart';
import 'package:structured_log_admin_client/features/log_browser/domain/log_scope.dart';
import 'package:structured_log_admin_client/features/log_browser/infrastructure/log_stream_client.dart';
import 'package:structured_log_admin_client/features/resources/infrastructure/resources_repository_impl.dart';
import 'package:structured_log_admin_client/shared/api/api_client.dart';
import 'package:structured_log_admin_client/shared/api/dto/auth_dto.dart';
import 'package:structured_log_admin_client/shared/auth/token_pair.dart';
import 'package:structured_log_admin_client/shared/auth/token_storage.dart';
import 'package:structured_log_admin_client/shared/config/app_config.dart';

import 'harness.dart';

/// Stopping the server.
///
/// Its own file because it is the one property that cannot be checked
/// alongside anything else: it ends the process it is checking.
void main() {
  setUpAll(
    () => StructlogConfiguration.configure(
      sinks: [LogSink(name: 'silent', output: (_, _) {})],
    ),
  );
  tearDownAll(StructlogConfiguration.reset);

  test('SIGTERM stops the server while a subscription is open', () async {
    final server = await ServerProcess.start();
    var stopped = false;
    addTearDown(() async {
      if (!stopped) await server.stop();
    });

    final storage = InMemoryTokenStorage();
    final api = ApiClient(
      config: AppConfig(baseUrl: server.baseUrl),
      storage: storage,
    );

    Future<void> signIn(String password) async {
      final tokens = await api.auth.signIn('password', 'admin', password);
      await storage.write(
        TokenPair(
          accessToken: tokens.accessToken,
          refreshToken: tokens.refreshToken,
        ),
      );
    }

    await signIn(server.bootstrapPassword);
    await api.auth.changePassword(
      ChangePasswordRequestDto(
        currentPassword: server.bootstrapPassword,
        newPassword: 'chosen-by-the-operator',
      ),
    );

    final resources = ResourcesRepositoryImpl(api);
    final group = (await resources.createGroup(
      'payments',
    )).getOrElse((failure) => fail('creating a group failed: $failure'));
    final project = (await resources.createProject(
      groupId: group.id,
      name: 'checkout',
      retentionDays: 30,
    )).getOrElse((failure) => fail('creating a project failed: $failure'));

    final stream = LogStreamClient(
      api.streamDio,
      logger: getLogger('e2e'),
      // Long, so the client is not busy redialling a server that is on its
      // way down while the shutdown is being timed.
      initialBackoff: const Duration(seconds: 30),
    );
    final subscription = stream
        .connect(
          scope: ProjectScope(id: project.id, name: 'checkout'),
          filter: const LogFilter(),
        )
        .listen((_) {});
    addTearDown(subscription.cancel);
    // Give the subscription time to be established before pulling the rug.
    await Future<void>.delayed(const Duration(seconds: 1));

    final started = DateTime.now();
    await server.stop();
    stopped = true;
    final took = DateTime.now().difference(started);

    // `shelf_io`'s graceful close waits for active connections to finish, and
    // a live subscription is a connection that never finishes on its own. A
    // server that does not stop when told is not a test problem: `docker
    // stop` waits ten seconds and then kills it, which is how a SQLite
    // database ends up recovering a WAL on every deploy that had a watcher
    // open.
    expect(
      took,
      lessThan(const Duration(seconds: 10)),
      reason: 'shutdown must not wait out an open log subscription',
    );
    // That the subscriber is *told* — an `event: end` frame rather than a
    // socket that goes quiet — is checked where the frame is written, in the
    // server's own `log_stream_route_test.dart`. From here only the timing is
    // observable, and the timing is the defect this test exists for.
  }, timeout: const Timeout(Duration(minutes: 2)));
}
