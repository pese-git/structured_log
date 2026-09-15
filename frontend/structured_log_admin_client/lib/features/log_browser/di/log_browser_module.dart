import 'package:cherrypick/cherrypick.dart';

import '../../../shared/api/api_client.dart';
import '../application/load_scopes.dart';
import '../application/query_logs.dart';
import '../domain/log_browser_repository.dart';
import '../infrastructure/log_browser_repository_impl.dart';
import '../presentation/log_browser_cubit.dart';

/// The log browser's own bindings, installed into their own subscope
/// (design.md decision 35).
class LogBrowserModule extends Module {
  @override
  void builder(Scope currentScope) {
    bind<LogBrowserRepository>()
        .toProvide(
          () => LogBrowserRepositoryImpl(currentScope.resolve<ApiClient>()),
        )
        .singleton();

    bind<LoadScopes>().toProvide(
      () => LoadScopes(currentScope.resolve<LogBrowserRepository>()),
    );
    bind<QueryLogs>().toProvide(
      () => QueryLogs(currentScope.resolve<LogBrowserRepository>()),
    );

    // Not a singleton: a cubit belongs to the screen that opened it and is
    // closed with it, so a second visit gets a fresh one rather than a
    // closed one.
    bind<LogBrowserCubit>().toProvide(
      () => LogBrowserCubit(
        loadScopes: currentScope.resolve<LoadScopes>(),
        queryLogs: currentScope.resolve<QueryLogs>(),
      ),
    );
  }
}

Scope openLogBrowserScope(Scope parent) =>
    parent.openSubScope('log_browser')..installModules([LogBrowserModule()]);
