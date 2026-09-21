import 'package:cherrypick/cherrypick.dart';
import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log/structured_log.dart';
import 'package:structured_log_admin_client/features/audit/application/query_audit_log.dart';
import 'package:structured_log_admin_client/features/audit/di/audit_module.dart';
import 'package:structured_log_admin_client/features/audit/domain/audit_repository.dart';
import 'package:structured_log_admin_client/features/audit/presentation/audit_cubit.dart';
import 'package:structured_log_admin_client/features/auth/application/change_password.dart';
import 'package:structured_log_admin_client/features/auth/application/delete_account.dart';
import 'package:structured_log_admin_client/features/auth/application/restore_session.dart';
import 'package:structured_log_admin_client/features/auth/application/sign_in.dart';
import 'package:structured_log_admin_client/features/auth/application/sign_out.dart';
import 'package:structured_log_admin_client/features/auth/di/auth_module.dart';
import 'package:structured_log_admin_client/features/auth/domain/auth_repository.dart';
import 'package:structured_log_admin_client/features/log_browser/application/load_scopes.dart';
import 'package:structured_log_admin_client/features/log_browser/application/query_logs.dart';
import 'package:structured_log_admin_client/features/log_browser/application/watch_logs.dart';
import 'package:structured_log_admin_client/features/log_browser/di/log_browser_module.dart';
import 'package:structured_log_admin_client/features/log_browser/domain/log_browser_repository.dart';
import 'package:structured_log_admin_client/features/log_browser/infrastructure/log_stream_client.dart';
import 'package:structured_log_admin_client/features/log_browser/presentation/log_feed_bloc.dart';
import 'package:structured_log_admin_client/features/resources/application/manage_resources.dart';
import 'package:structured_log_admin_client/features/resources/di/resources_module.dart';
import 'package:structured_log_admin_client/features/resources/domain/resources_repository.dart';
import 'package:structured_log_admin_client/features/role_assignments/application/manage_role_assignments.dart';
import 'package:structured_log_admin_client/features/role_assignments/domain/role_assignments_repository.dart';
import 'package:structured_log_admin_client/features/users/application/manage_users.dart';
import 'package:structured_log_admin_client/features/users/di/users_module.dart';
import 'package:structured_log_admin_client/features/users/domain/users_repository.dart';
import 'package:structured_log_admin_client/features/users/presentation/users_cubit.dart';
import 'package:structured_log_admin_client/shared/api/api_client.dart';
import 'package:structured_log_admin_client/shared/auth/token_storage.dart';
import 'package:structured_log_admin_client/shared/config/app_config.dart';
import 'package:structured_log_admin_client/shared/di/app_module.dart';
import 'package:structured_log_admin_client/shared/di/structured_log_observer.dart';

import '../api/fake_adapter.dart';

const _config = AppConfig(baseUrl: 'https://logs.example.test');

/// Remembers whether the connection it stands in for was closed.
class _ClosingAdapter extends FakeAdapter {
  var closed = false;

  _ClosingAdapter() : super((_) => const FakeReply(200, body: {}));

  @override
  void close({bool force = false}) => closed = true;
}

Scope _root([HttpClientAdapter? adapter]) => openAppScope(
  config: _config,
  logger: getLogger('test'),
  tokenStorage: InMemoryTokenStorage(),
  httpAdapter: adapter ?? FakeAdapter((_) => const FakeReply(200, body: {})),
);

/// A cubit or bloc a scope hands out is the caller's to close.
Future<void> _closeIfClosable(Object? instance) async {
  if (instance is BlocBase) await instance.close();
}

void main() {
  setUp(CherryPick.closeRootScope);
  tearDown(CherryPick.closeRootScope);

  // A module that never resolves is a feature that is tested and inert: the
  // screen builds, the scope throws, and no unit test above it notices
  // (`project_optional_wiring_hazard`). Resolving every type a module promises
  // is what pins the wiring — and since the modules are generated, it is also
  // what pins the generator's reading of them.
  group('every feature scope resolves what it declares', () {
    final features = <String, ({Scope Function(Scope) open, List<Type> types})>{
      'resources': (
        open: openResourcesScope,
        types: [
          ResourcesRepository,
          RoleAssignmentsRepository,
          ManageGroups,
          ManageProjects,
          ManageTeams,
          ManageSecretKeys,
          ManageRoleAssignments,
        ],
      ),
      'users': (
        open: openUsersScope,
        types: [
          UsersRepository,
          ResourcesRepository,
          RoleAssignmentsRepository,
          AuditRepository,
          ManageUsers,
          ManageRoleAssignments,
          QueryAuditLog,
          UsersCubit,
        ],
      ),
      'audit': (
        open: openAuditScope,
        types: [AuditRepository, QueryAuditLog, AuditCubit],
      ),
      'log browser': (
        open: openLogBrowserScope,
        types: [
          LogStreamClient,
          LogBrowserRepository,
          LoadScopes,
          QueryLogs,
          WatchLogs,
          LogFeedBloc,
        ],
      ),
      'auth': (
        open: openAuthScope,
        types: [
          AuthRepository,
          SignIn,
          SignOut,
          RestoreSession,
          ChangePassword,
          CurrentUsername,
          IsGlobalAdmin,
          DeleteAccount,
        ],
      ),
    };

    for (final MapEntry(key: name, value: feature) in features.entries) {
      test(name, () async {
        final scope = feature.open(_root());
        for (final type in feature.types) {
          final instance = _resolveByType(scope, type);
          expect(instance, isNotNull, reason: '$type from the $name scope');
          await _closeIfClosable(instance);
        }
      });
    }
  });

  group('the auth scope, shared by the gate and the shell', () {
    test(
      'a second open joins the scope instead of installing the module again',
      () {
        final installed = <String>[];
        StructlogConfiguration.configure(
          sinks: [
            LogSink(
              name: 'capture',
              output: (entry, _) {
                if (entry['event'] == 'di.modules_installed') {
                  installed.addAll((entry['modules'] as List).cast<String>());
                }
              },
            ),
          ],
        );
        addTearDown(StructlogConfiguration.reset);
        final root = _root();
        installed.clear();

        final first = openAuthScope(root);
        final second = openAuthScope(root);

        expect(second, same(first));
        expect(installed, [r'$AuthModule']);
        expect(second.resolve<SignIn>(), isNotNull);
      },
    );

    test('after it is closed the next open installs it afresh', () async {
      final root = _root();
      final before = openAuthScope(root).resolve<AuthRepository>();

      await closeAuthScope(root);
      final after = openAuthScope(root).resolve<AuthRepository>();

      expect(after, isNot(same(before)));
    });
  });

  group('singletons and screen-owned objects', () {
    test(
      'a repository is one object, a cubit is a new one each time',
      () async {
        final scope = openAuditScope(_root());

        expect(
          scope.resolve<AuditRepository>(),
          same(scope.resolve<AuditRepository>()),
        );
        final first = scope.resolve<AuditCubit>();
        final second = scope.resolve<AuditCubit>();
        expect(first, isNot(same(second)));
        await first.close();
        await second.close();
      },
    );
  });

  group('lifetime', () {
    test(
      'closing a feature scope forgets it: the next one starts fresh',
      () async {
        final root = _root();
        final before = openAuditScope(root).resolve<AuditRepository>();

        await closeAuditScope(root);
        final after = openAuditScope(root).resolve<AuditRepository>();

        expect(after, isNot(same(before)));
      },
    );

    test(
      'closing the root scope closes the connections the client holds',
      () async {
        final adapter = _ClosingAdapter();
        final root = _root(adapter);
        root.resolve<ApiClient>();
        expect(adapter.closed, isFalse);

        await CherryPick.closeRootScope();

        expect(adapter.closed, isTrue);
      },
    );

    test('a client that was never resolved has nothing to close', () async {
      final adapter = _ClosingAdapter();
      _root(adapter);

      await CherryPick.closeRootScope();

      expect(adapter.closed, isFalse);
    });
  });

  group('cycle detection', () {
    test('is on once the application scope is open', () {
      _root();

      expect(CherryPick.isGlobalCycleDetectionEnabled, isTrue);
      expect(CherryPick.isGlobalCrossScopeCycleDetectionEnabled, isTrue);
    });

    test('a cycle is reported instead of overflowing the stack', () {
      final scope = _root();
      scope.installModules([_CycleModule()]);

      expect(
        () => scope.resolve<_A>(),
        throwsA(isA<CircularDependencyException>()),
      );
    });
  });

  group('the observer', () {
    late List<({Map<String, dynamic> entry, LogLevel level})> captured;
    late StructuredLogCherryPickObserver observer;

    setUp(() {
      captured = [];
      StructlogConfiguration.configure(
        sinks: [
          LogSink(
            name: 'capture',
            output: (entry, level) =>
                captured.add((entry: entry, level: level)),
          ),
        ],
      );
      observer = StructuredLogCherryPickObserver(getLogger('test'));
    });
    tearDown(StructlogConfiguration.reset);

    test('says when a scope opens and closes', () {
      observer.onScopeOpened('audit');
      observer.onScopeClosed('audit');

      expect(captured.map((c) => c.entry['event']), [
        'di.scope_opened',
        'di.scope_closed',
      ]);
      expect(captured.first.entry['scope'], 'audit');
    });

    test('reports a cycle as an error', () {
      observer.onCycleDetected(['A', 'B', 'A'], scopeName: 'root');

      expect(captured.single.level, LogLevel.error);
      expect(captured.single.entry['chain'], ['A', 'B', 'A']);
    });

    test('never prints an instance, and stays quiet about requests', () {
      final secret = 'refresh-token-value';
      observer.onInstanceCreated('TokenStorage', String, secret);
      observer.onInstanceDisposed('TokenStorage', String, secret);
      observer.onInstanceRequested('TokenStorage', String);
      observer.onCacheHit('TokenStorage', String);
      observer.onDiagnostic('Successfully resolved: TokenStorage');

      expect(captured.map((c) => c.entry['event']), ['di.instance_disposed']);
      expect(captured.toString(), isNot(contains(secret)));
    });
  });
}

// `Scope.resolve` takes a type argument, and a table of types has none to give.
Object? _resolveByType(Scope scope, Type type) => switch (type) {
  const (ResourcesRepository) => scope.resolve<ResourcesRepository>(),
  const (RoleAssignmentsRepository) =>
    scope.resolve<RoleAssignmentsRepository>(),
  const (ManageGroups) => scope.resolve<ManageGroups>(),
  const (ManageProjects) => scope.resolve<ManageProjects>(),
  const (ManageTeams) => scope.resolve<ManageTeams>(),
  const (ManageSecretKeys) => scope.resolve<ManageSecretKeys>(),
  const (ManageRoleAssignments) => scope.resolve<ManageRoleAssignments>(),
  const (UsersRepository) => scope.resolve<UsersRepository>(),
  const (AuditRepository) => scope.resolve<AuditRepository>(),
  const (ManageUsers) => scope.resolve<ManageUsers>(),
  const (QueryAuditLog) => scope.resolve<QueryAuditLog>(),
  const (UsersCubit) => scope.resolve<UsersCubit>(),
  const (AuditCubit) => scope.resolve<AuditCubit>(),
  const (LogStreamClient) => scope.resolve<LogStreamClient>(),
  const (LogBrowserRepository) => scope.resolve<LogBrowserRepository>(),
  const (LoadScopes) => scope.resolve<LoadScopes>(),
  const (QueryLogs) => scope.resolve<QueryLogs>(),
  const (WatchLogs) => scope.resolve<WatchLogs>(),
  const (LogFeedBloc) => scope.resolve<LogFeedBloc>(),
  const (AuthRepository) => scope.resolve<AuthRepository>(),
  const (SignIn) => scope.resolve<SignIn>(),
  const (SignOut) => scope.resolve<SignOut>(),
  const (RestoreSession) => scope.resolve<RestoreSession>(),
  const (ChangePassword) => scope.resolve<ChangePassword>(),
  const (CurrentUsername) => scope.resolve<CurrentUsername>(),
  const (IsGlobalAdmin) => scope.resolve<IsGlobalAdmin>(),
  const (DeleteAccount) => scope.resolve<DeleteAccount>(),
  _ => throw ArgumentError('no resolver for $type'),
};

class _A {
  _A(_B _);
}

class _B {
  _B(_A _);
}

class _CycleModule extends Module {
  @override
  void builder(Scope currentScope) {
    bind<_A>().toProvide(() => _A(currentScope.resolve<_B>()));
    bind<_B>().toProvide(() => _B(currentScope.resolve<_A>()));
  }
}
