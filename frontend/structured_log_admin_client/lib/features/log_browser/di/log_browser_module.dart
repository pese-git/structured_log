import 'package:cherrypick/cherrypick.dart';
import 'package:cherrypick_annotations/cherrypick_annotations.dart';
import 'package:structured_log/structured_log.dart';

import '../../../shared/api/api_client.dart';
import '../application/load_scopes.dart';
import '../application/query_logs.dart';
import '../application/watch_logs.dart';
import '../domain/log_browser_repository.dart';
import '../infrastructure/log_browser_repository_impl.dart';
import '../infrastructure/log_stream_client.dart';
import '../presentation/log_feed_bloc.dart';

part 'log_browser_module.module.cherrypick.g.dart';

/// The log browser's own bindings, installed into their own subscope
/// (design.md decision 35).
@module()
abstract class LogBrowserModule extends Module {
  // Runs on `ApiClient.streamDio` — its own instance, but carrying the same
  // interceptor object as the generated clients, so the subscription gets
  // the same Authorization header and shares their refresh (decision 37).
  // It is separate only because the web needs an adapter that can deliver a
  // body as it arrives.
  @singleton()
  @provide()
  LogStreamClient logStreamClient(ApiClient api, BoundLogger logger) =>
      LogStreamClient(api.streamDio, logger: logger);

  @singleton()
  @provide()
  LogBrowserRepository logBrowserRepository(
    ApiClient api,
    LogStreamClient stream,
  ) => LogBrowserRepositoryImpl(api, stream);

  @provide()
  LoadScopes loadScopes(LogBrowserRepository repository) =>
      LoadScopes(repository);

  @provide()
  QueryLogs queryLogs(LogBrowserRepository repository) => QueryLogs(repository);

  @provide()
  WatchLogs watchLogs(LogBrowserRepository repository) => WatchLogs(repository);

  // Not a singleton: a bloc belongs to the screen that opened it and is
  // closed with it — which also closes its live subscription — so a second
  // visit gets a fresh one rather than a closed one.
  @provide()
  LogFeedBloc logFeedBloc(
    LoadScopes loadScopes,
    QueryLogs queryLogs,
    WatchLogs watchLogs,
  ) => LogFeedBloc(
    loadScopes: loadScopes,
    queryLogs: queryLogs,
    watchLogs: watchLogs,
  );
}

const logBrowserScopeName = 'log_browser';

Scope openLogBrowserScope(Scope parent) =>
    parent.openSubScope(logBrowserScopeName)
      ..installModules([$LogBrowserModule()]);

/// Disposes what log browser's scope created and forgets it, so the next
/// [openLogBrowserScope] starts from nothing rather than on top of the last one.
Future<void> closeLogBrowserScope(Scope parent) =>
    parent.closeSubScope(logBrowserScopeName);
