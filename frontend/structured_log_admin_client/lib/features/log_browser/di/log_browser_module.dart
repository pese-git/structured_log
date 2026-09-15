import 'package:cherrypick/cherrypick.dart';
import 'package:structured_log/structured_log.dart';

import '../../../shared/api/api_client.dart';
import '../application/load_scopes.dart';
import '../application/query_logs.dart';
import '../application/watch_logs.dart';
import '../domain/log_browser_repository.dart';
import '../infrastructure/log_browser_repository_impl.dart';
import '../infrastructure/log_stream_client.dart';
import '../presentation/log_feed_bloc.dart';

/// The log browser's own bindings, installed into their own subscope
/// (design.md decision 35).
class LogBrowserModule extends Module {
  @override
  void builder(Scope currentScope) {
    // Runs on `ApiClient.dio` — the same instance the generated clients use,
    // so the live stream carries the same Authorization header and the same
    // one-shot refresh (decision 37).
    bind<LogStreamClient>()
        .toProvide(
          () => LogStreamClient(
            currentScope.resolve<ApiClient>().dio,
            logger: currentScope.resolve<BoundLogger>(),
          ),
        )
        .singleton();

    bind<LogBrowserRepository>()
        .toProvide(
          () => LogBrowserRepositoryImpl(
            currentScope.resolve<ApiClient>(),
            currentScope.resolve<LogStreamClient>(),
          ),
        )
        .singleton();

    bind<LoadScopes>().toProvide(
      () => LoadScopes(currentScope.resolve<LogBrowserRepository>()),
    );
    bind<QueryLogs>().toProvide(
      () => QueryLogs(currentScope.resolve<LogBrowserRepository>()),
    );
    bind<WatchLogs>().toProvide(
      () => WatchLogs(currentScope.resolve<LogBrowserRepository>()),
    );

    // Not a singleton: a bloc belongs to the screen that opened it and is
    // closed with it — which also closes its live subscription — so a second
    // visit gets a fresh one rather than a closed one.
    bind<LogFeedBloc>().toProvide(
      () => LogFeedBloc(
        loadScopes: currentScope.resolve<LoadScopes>(),
        queryLogs: currentScope.resolve<QueryLogs>(),
        watchLogs: currentScope.resolve<WatchLogs>(),
      ),
    );
  }
}

Scope openLogBrowserScope(Scope parent) =>
    parent.openSubScope('log_browser')..installModules([LogBrowserModule()]);
