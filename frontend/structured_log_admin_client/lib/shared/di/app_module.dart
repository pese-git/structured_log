import 'package:cherrypick/cherrypick.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:structured_log/structured_log.dart';

import '../api/api_client.dart';
import '../auth/token_storage.dart';
import '../config/app_config.dart';
import 'structured_log_observer.dart';

/// The application's shared dependencies.
///
/// Everything below is a singleton within the scope, because each is a
/// connection or a store rather than a value: a second [ApiClient] would mean
/// a second set of interceptors, and two token storages would disagree about
/// whose session is current.
///
/// Feature repositories belong in per-feature modules installed into their own
/// subscopes (design.md decision 35), so a feature can be composed — and torn
/// down — without touching this one. No `Bloc` or widget builds an
/// infrastructure dependency itself; they resolve one.
class AppModule extends Module {
  final AppConfig config;

  /// Created once by `main()` and handed in, not built here: constructing it
  /// installs the global `StructlogConfiguration`, and a provider that did
  /// that would reinstall it every time the scope was rebuilt.
  final BoundLogger logger;

  /// Supplied by tests and by the web build, which has no keychain. Left null
  /// in a real desktop or mobile build, where [SecureTokenStorage] is right.
  final TokenStorage? tokenStorageOverride;

  /// Answers HTTP without a socket. Supplied by tests that drive the whole
  /// app — the same seam as [tokenStorageOverride], for the same reason: a
  /// widget test has no network, and a screen wired to a real client cannot be
  /// exercised end to end.
  final HttpClientAdapter? httpAdapter;

  /// Raised when a session cannot be renewed — the router sends the user back
  /// to sign-in. Passed in rather than resolved to keep this module free of
  /// any navigation dependency.
  final void Function()? onSessionExpired;

  /// Raised when the server refuses everything until the password is changed.
  /// Passed in for the same reason as [onSessionExpired]: the interceptor has
  /// no widget tree to reach into.
  final void Function()? onPasswordChangeRequired;

  AppModule({
    required this.config,
    required this.logger,
    this.tokenStorageOverride,
    this.httpAdapter,
    this.onSessionExpired,
    this.onPasswordChangeRequired,
  });

  @override
  void builder(Scope currentScope) {
    bind<AppConfig>().toInstance(config);

    bind<BoundLogger>().toInstance(logger);

    bind<TokenStorage>()
        .toProvide(
          () =>
              tokenStorageOverride ??
              const SecureTokenStorage(FlutterSecureStorage()),
        )
        .singleton();

    bind<ApiClient>()
        .toProvide(
          () => ApiClient(
            config: currentScope.resolve<AppConfig>(),
            storage: currentScope.resolve<TokenStorage>(),
            onSessionExpired: onSessionExpired,
            onPasswordChangeRequired: onPasswordChangeRequired,
            adapter: httpAdapter,
          ),
        )
        .singleton();
  }
}

/// Opens the root scope with [AppModule] installed.
///
/// The one place that composes the application; `main()` calls it and hands
/// the scope to the widget tree.
Scope openAppScope({
  required AppConfig config,
  required BoundLogger logger,
  TokenStorage? tokenStorage,
  HttpClientAdapter? httpAdapter,
  void Function()? onSessionExpired,
  void Function()? onPasswordChangeRequired,
}) {
  // Before the root scope is opened: a scope takes the global observer when it
  // is created. Cycle detection stays on in release too — a cycle is a mistake
  // in the wiring, and the alternative to reporting it is a stack overflow.
  CherryPick.setGlobalObserver(StructuredLogCherryPickObserver(logger));
  CherryPick.enableGlobalCycleDetection();
  CherryPick.enableGlobalCrossScopeCycleDetection();

  final scope = CherryPick.openRootScope();
  scope.installModules([
    AppModule(
      config: config,
      logger: logger,
      tokenStorageOverride: tokenStorage,
      httpAdapter: httpAdapter,
      onSessionExpired: onSessionExpired,
      onPasswordChangeRequired: onPasswordChangeRequired,
    ),
  ]);
  return scope;
}
